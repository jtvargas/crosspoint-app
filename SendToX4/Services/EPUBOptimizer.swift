import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

/// Configuration for the pre-upload EPUB optimizer.
///
/// Defaults mirror the CrossPoint firmware's browser-side "Optimize EPUB"
/// feature: images are downscaled to the device panel, converted to true
/// grayscale, and re-encoded as baseline JPEG.
nonisolated struct EPUBOptimizerConfig: Sendable {
    /// Maximum output pixel size for content images (the device panel).
    var maxPixelSize: CGSize = DeviceSpecification.x4.resolution

    /// JPEG encode quality (CrossPoint default is 85%).
    var jpegQuality: CGFloat = 0.85

    /// Images smaller than this on both axes are treated as separators or
    /// ornaments: they are never downscaled, only transcoded when the source
    /// format is not device-friendly.
    var minProcessDimension: Int = 200

    /// Decompression-bomb guard: images that would decode to more megapixels
    /// than this are copied through unmodified (never fully decoded).
    var maxDecodedMegapixels: Double = 50

    /// EPUBs with more entries than this are passed through untouched.
    var maxEntries = 2_000

    /// EPUBs larger than this are passed through untouched (bounds peak memory).
    var maxEPUBBytes = 150 * 1024 * 1024

    /// Single zip entries larger than this abort optimization (pass-through).
    var maxEntryBytes = 64 * 1024 * 1024

    /// JPEG sources already within the target size and below this byte count
    /// are considered optimal and copied as-is.
    var skipOptimalJPEGBytes = 200 * 1024
}

/// Optimizes EPUB files for e-ink devices before upload, mirroring the
/// CrossPoint firmware's client-side optimizer:
/// raster images (PNG/GIF/WebP/BMP/JPEG) are downscaled to fit the device
/// panel, converted to grayscale, and re-encoded as baseline JPEG. Original
/// entry paths are preserved; only the OPF `media-type` is rewritten, so no
/// XHTML/NCX references ever need touching.
///
/// The optimizer NEVER fails the upload path: any structural or per-image
/// error results in the original data (or original entry) passing through
/// unchanged.
nonisolated enum EPUBOptimizer {

    /// Raster formats the optimizer will re-encode.
    private static let rasterExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp"]

    /// Formats the target device can already display; tiny separator images
    /// in these formats are copied through untouched.
    private static let deviceFriendlyExtensions: Set<String> = ["png", "jpg", "jpeg"]

    /// Whether a zip entry path has a raster image extension the optimizer re-encodes.
    private static func isRasterImagePath(_ path: String) -> Bool {
        rasterExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    // MARK: - Public API

    /// Convenience gate used by upload call sites.
    /// Runs the optimizer only when `enabled` and the file is an EPUB.
    static func optimizeIfNeeded(
        _ data: Data,
        filename: String,
        enabled: Bool,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> Data {
        guard enabled, filename.lowercased().hasSuffix(".epub") else { return data }
        return await optimize(epubData: data, progress: progress)
    }

    /// Optimize an EPUB's images for the target device.
    ///
    /// - Returns: The optimized EPUB, or the original `epubData` unchanged if
    ///   the EPUB contains no raster images, optimization would not help, or
    ///   any error occurs. This function never throws into the upload path.
    static func optimize(
        epubData: Data,
        config: EPUBOptimizerConfig = EPUBOptimizerConfig(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> Data {
        // Structural guard rails: pass very large books through untouched.
        guard epubData.count <= config.maxEPUBBytes else {
            DebugLogger.log(
                "EPUB optimizer skipped: file exceeds \(config.maxEPUBBytes) bytes",
                level: .info, category: .conversion
            )
            return epubData
        }

        guard let source = Archive(data: epubData, accessMode: .read) else {
            DebugLogger.log(
                "EPUB optimizer skipped: could not open archive",
                level: .warning, category: .conversion
            )
            return epubData
        }

        let entries = source.compactMap { $0 }
        guard entries.count <= config.maxEntries else {
            DebugLogger.log(
                "EPUB optimizer skipped: \(entries.count) entries exceeds cap",
                level: .info, category: .conversion
            )
            return epubData
        }

        // Fast path: no raster images means nothing to optimize
        // (this covers every text-only CrossX conversion at ~zero cost).
        let imagePaths = Set(entries.filter { isRasterImagePath($0.path) }.map { $0.path })
        guard !imagePaths.isEmpty else { return epubData }

        do {
            let optimized = try rebuild(
                source: source,
                entries: entries,
                imagePaths: imagePaths,
                config: config,
                progress: progress
            )
            // Only adopt the result when it actually helps.
            if optimized.count < epubData.count {
                DebugLogger.log(
                    "EPUB optimized: \(epubData.count) -> \(optimized.count) bytes (\(imagePaths.count) image(s))",
                    level: .info, category: .conversion
                )
                return optimized
            }
            DebugLogger.log(
                "EPUB optimizer: result not smaller, keeping original",
                level: .info, category: .conversion
            )
            return epubData
        } catch {
            DebugLogger.log(
                "EPUB optimizer failed, uploading original: \(error.localizedDescription)",
                level: .warning, category: .conversion
            )
            return epubData
        }
    }

    // MARK: - Archive Rebuild

    private enum OptimizerError: Error {
        case outputArchiveCreationFailed
        case entryTooLarge(String)
        case outputDataUnavailable
    }

    /// Rebuilds the archive, re-encoding raster images and copying every
    /// other entry verbatim. Output is written to a temporary file so peak
    /// memory stays bounded to the input data plus a single entry.
    private static func rebuild(
        source: Archive,
        entries: [Entry],
        imagePaths: Set<String>,
        config: EPUBOptimizerConfig,
        progress: (@Sendable (Double) -> Void)?
    ) throws -> Data {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub-optimize-\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let output = Archive(url: tempURL, accessMode: .create) else {
            throw OptimizerError.outputArchiveCreationFailed
        }

        // Resolve the OPF (for media-type rewriting). Failures here are
        // non-fatal: images are still optimized, the manifest just keeps
        // its original media-types (readers sniff image bytes anyway).
        let opfPath = findOPFPath(in: source, entries: entries, config: config)
        var convertedPaths: Set<String> = []

        // 1. mimetype MUST be the first entry and STOREd.
        let mimetypeData: Data
        if let mimetypeEntry = entries.first(where: { $0.path == "mimetype" }) {
            mimetypeData = (try? extractData(mimetypeEntry, from: source, cap: config.maxEntryBytes))
                ?? Data(EPUBTemplates.mimetype.utf8)
        } else {
            mimetypeData = Data(EPUBTemplates.mimetype.utf8)
        }
        try addEntry(to: output, path: "mimetype", data: mimetypeData, compression: .none)

        // 2. Image entries (recording which ones were actually converted).
        //    OPF is deferred to the end so the rewrite can see `convertedPaths`.
        let workEntries = entries.filter {
            $0.type == .file && $0.path != "mimetype" && $0.path != opfPath
        }
        var processed = 0
        for entry in workEntries {
            try autoreleasepool {
                let data = try extractData(entry, from: source, cap: config.maxEntryBytes)

                if imagePaths.contains(entry.path),
                   let converted = processImage(data: data, config: config),
                   converted.count < data.count {
                    try addEntry(to: output, path: entry.path, data: converted, compression: .none)
                    convertedPaths.insert(entry.path)
                } else {
                    try addEntry(to: output, path: entry.path, data: data, compression: .deflate)
                }
            }
            processed += 1
            progress?(Double(processed) / Double(workEntries.count + 1))
        }

        // 3. OPF, with media-types rewritten for converted images.
        if let opfPath, let opfEntry = entries.first(where: { $0.path == opfPath }) {
            let opfData = try extractData(opfEntry, from: source, cap: config.maxEntryBytes)
            let rewritten = rewriteMediaTypes(
                opfData: opfData,
                opfPath: opfPath,
                convertedPaths: convertedPaths
            )
            try addEntry(to: output, path: opfPath, data: rewritten, compression: .deflate)
        }
        progress?(1.0)

        guard let result = try? Data(contentsOf: tempURL) else {
            throw OptimizerError.outputDataUnavailable
        }
        return result
    }

    // MARK: - Image Processing

    /// Re-encode a single image for the device.
    /// Returns nil when the image should be kept as-is.
    private static func processImage(data: Data, config: EPUBOptimizerConfig) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(imageSource) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, sourceOptions)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil // Undecodable — copy through unchanged
        }

        // Decompression-bomb guard: never fully decode enormous images.
        let megapixels = Double(width) * Double(height) / 1_000_000
        guard megapixels <= config.maxDecodedMegapixels else {
            DebugLogger.log(
                "EPUB optimizer: skipping \(width)x\(height) image (decode guard)",
                level: .warning, category: .conversion
            )
            return nil
        }

        let sourceType = CGImageSourceGetType(imageSource) as String?
        let isJPEG = sourceType == UTType.jpeg.identifier

        let maxW = Int(config.maxPixelSize.width)
        let maxH = Int(config.maxPixelSize.height)
        let fitsScreen = width <= maxW && height <= maxH

        // Already-optimal fast path: small JPEG that fits the panel.
        if isJPEG && fitsScreen && data.count <= config.skipOptimalJPEGBytes {
            return nil
        }

        // Separator/ornament protection (CrossPoint parity): tiny images keep
        // their dimensions; device-friendly formats are left untouched.
        let isTiny = width < config.minProcessDimension && height < config.minProcessDimension
        if isTiny, let ext = sourceType.flatMap({ UTType($0)?.preferredFilenameExtension }),
           deviceFriendlyExtensions.contains(ext.lowercased()) {
            return nil
        }

        // Target size: fit within the panel, never upscale.
        let scale = min(CGFloat(maxW) / CGFloat(width), CGFloat(maxH) / CGFloat(height), 1.0)
        let targetW = isTiny ? width : max(1, Int((CGFloat(width) * scale).rounded()))
        let targetH = isTiny ? height : max(1, Int((CGFloat(height) * scale).rounded()))

        // Memory-bounded decode: thumbnail API never materializes full-res pixels.
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(targetW, targetH)
        ] as CFDictionary
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions) else {
            return nil
        }

        // Draw onto a white-filled grayscale canvas (transparent PNGs must
        // land on white, not black, for e-ink).
        guard let context = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        guard let grayImage = context.makeImage() else { return nil }

        // Encode baseline JPEG (ImageIO default; progressive is never set).
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        let encodeOptions = [
            kCGImageDestinationLossyCompressionQuality: config.jpegQuality
        ] as CFDictionary
        CGImageDestinationAddImage(destination, grayImage, encodeOptions)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return encoded as Data
    }

    // MARK: - OPF Handling

    /// Locates the OPF package document via META-INF/container.xml.
    private static func findOPFPath(
        in archive: Archive,
        entries: [Entry],
        config: EPUBOptimizerConfig
    ) -> String? {
        guard let containerEntry = entries.first(where: { $0.path == "META-INF/container.xml" }),
              let containerData = try? extractData(containerEntry, from: archive, cap: config.maxEntryBytes),
              let container = String(data: containerData, encoding: .utf8) else {
            return nil
        }
        guard let match = firstMatch(
            pattern: "full-path\\s*=\\s*\"([^\"]+)\"",
            in: container
        ) else {
            return nil
        }
        return match
    }

    /// Rewrites `media-type` to `image/jpeg` on manifest items whose href
    /// resolves to a converted image. Any parse trouble returns the OPF
    /// unmodified.
    private static func rewriteMediaTypes(
        opfData: Data,
        opfPath: String,
        convertedPaths: Set<String>
    ) -> Data {
        guard !convertedPaths.isEmpty,
              let opf = String(data: opfData, encoding: .utf8) else {
            return opfData
        }

        let opfDir = opfPath.contains("/")
            ? String(opfPath[..<opfPath.range(of: "/", options: .backwards)!.lowerBound])
            : ""

        guard let itemRegex = try? NSRegularExpression(pattern: "<item\\b[^>]*>") else {
            return opfData
        }
        guard let hrefRegex = try? NSRegularExpression(pattern: "href\\s*=\\s*\"([^\"]+)\""),
              let mediaTypeRegex = try? NSRegularExpression(pattern: "media-type\\s*=\\s*\"[^\"]*\"") else {
            return opfData
        }

        let nsOPF = opf as NSString
        var result = opf
        // Iterate matches back-to-front so replacements don't shift ranges.
        let matches = itemRegex.matches(in: opf, range: NSRange(location: 0, length: nsOPF.length))
        for match in matches.reversed() {
            let itemTag = nsOPF.substring(with: match.range)
            let nsItem = itemTag as NSString
            guard let hrefMatch = hrefRegex.firstMatch(
                in: itemTag, range: NSRange(location: 0, length: nsItem.length)
            ) else { continue }
            let href = nsItem.substring(with: hrefMatch.range(at: 1))
            let resolved = resolve(href: href, relativeTo: opfDir)
            guard convertedPaths.contains(resolved) else { continue }

            let updatedTag = mediaTypeRegex.stringByReplacingMatches(
                in: itemTag,
                range: NSRange(location: 0, length: nsItem.length),
                withTemplate: "media-type=\"image/jpeg\""
            )
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: updatedTag)
            }
        }

        return Data(result.utf8)
    }

    /// Resolves a (possibly percent-encoded, possibly relative) manifest href
    /// against the OPF's directory into a zip entry path.
    private static func resolve(href: String, relativeTo opfDir: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        var components = opfDir.isEmpty ? [] : opfDir.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/").map(String.init) {
            switch part {
            case "", ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(part)
            }
        }
        return components.joined(separator: "/")
    }

    // MARK: - Zip Helpers

    /// Extracts a full entry into memory with a hard byte cap.
    private static func extractData(_ entry: Entry, from archive: Archive, cap: Int) throws -> Data {
        guard Int(entry.uncompressedSize) <= cap else {
            throw OptimizerError.entryTooLarge(entry.path)
        }
        var data = Data()
        data.reserveCapacity(Int(entry.uncompressedSize))
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    /// Adds a data entry to the output archive.
    private static func addEntry(
        to archive: Archive,
        path: String,
        data: Data,
        compression: CompressionMethod
    ) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: UInt32(Int64(data.count)),
            compressionMethod: compression,
            provider: { position, size in
                data.subdata(in: position..<(position + size))
            }
        )
    }

    /// First capture group of `pattern` in `text`, or nil.
    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(
            in: text, range: NSRange(location: 0, length: nsText.length)
        ), match.numberOfRanges > 1 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }
}
