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
/// panel, converted to grayscale, and re-encoded as baseline JPEG. Converted
/// images receive .jpg paths, with references and reader-facing markup
/// rewritten together.
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

    /// Optimize an EPUB's images and container for the target device.
    ///
    /// - Returns: The optimized EPUB, or the original `epubData` unchanged if
    ///   optimization would not help or any error occurs. This function never
    ///   throws into the upload path.
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

        let imagePaths = Set(entries.filter { isRasterImagePath($0.path) }.map { $0.path })

        do {
            // Inspect only XHTML when there are no raster candidates. Ordinary
            // text-only books never enter the rebuild or regex rewrite pass.
            guard try !imagePaths.isEmpty || containsSVG(in: source, entries: entries, config: config) else {
                return epubData
            }
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

    /// Images are written first so the text pass sees only successful conversions.
    /// A file-backed output keeps memory bounded to the input plus one entry.
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

        let opfPath = findOPFPath(in: source, entries: entries, config: config)
        var renamedPaths: [String: String] = [:]
        var occupiedPaths = Set(entries.map(\.path))

        // 1. mimetype MUST be the first entry and STOREd.
        let mimetypeData: Data
        if let mimetypeEntry = entries.first(where: { $0.path == "mimetype" }) {
            mimetypeData = (try? extractData(mimetypeEntry, from: source, cap: config.maxEntryBytes))
                ?? Data(EPUBTemplates.mimetype.utf8)
        } else {
            mimetypeData = Data(EPUBTemplates.mimetype.utf8)
        }
        try addEntry(to: output, path: "mimetype", data: mimetypeData, compression: .none)

        // 2. Process all images before rewriting any references.
        let workEntries = entries.filter {
            $0.type == .file && $0.path != "mimetype" && $0.path != opfPath
        }
        let total = workEntries.count + (opfPath == nil ? 0 : 1)
        var processed = 0
        for entry in workEntries where imagePaths.contains(entry.path) {
            try autoreleasepool {
                let data = try extractData(entry, from: source, cap: config.maxEntryBytes)

                if let converted = processImage(data: data, config: config),
                   converted.count < data.count {
                    let stem = (entry.path as NSString).deletingPathExtension
                    var jpgPath = stem + ".jpg"
                    var suffix = 1
                    // Never overwrite an existing image or another renamed entry.
                    while jpgPath != entry.path && occupiedPaths.contains(jpgPath) {
                        jpgPath = "\(stem)-\(suffix).jpg"
                        suffix += 1
                    }
                    try addEntry(to: output, path: jpgPath, data: converted, compression: .none)
                    occupiedPaths.insert(jpgPath)
                    renamedPaths[entry.path] = jpgPath
                } else {
                    try addEntry(to: output, path: entry.path, data: data, compression: .deflate)
                }
            }
            processed += 1
            progress?(Double(processed) / Double(max(1, total)))
        }

        // 3. Skip all text rewriting unless conversion or SVG markup needs it.
        let rewriteText = try !renamedPaths.isEmpty
            || containsSVG(in: source, entries: entries, config: config)
        let identifier: String?
        if rewriteText, let opfPath, let entry = source[opfPath],
           let text = String(data: try extractData(entry, from: source, cap: config.maxEntryBytes), encoding: .utf8) {
            identifier = packageIdentifier(in: text)
        } else {
            identifier = nil
        }
        for entry in workEntries where !imagePaths.contains(entry.path) {
            try autoreleasepool {
                let data = try extractData(entry, from: source, cap: config.maxEntryBytes)
                let rewritten = rewriteText
                    ? rewriteEntry(data, path: entry.path, renamedPaths: renamedPaths, identifier: identifier)
                    : data
                try addEntry(to: output, path: entry.path, data: rewritten, compression: .deflate)
            }
            processed += 1
            progress?(Double(processed) / Double(max(1, total)))
        }

        // 4. Package document last; mimetype remains first and uncompressed.
        if let opfPath, let opfEntry = source[opfPath] {
            let data = try extractData(opfEntry, from: source, cap: config.maxEntryBytes)
            let rewritten = rewriteText
                ? rewriteEntry(data, path: opfPath, renamedPaths: renamedPaths, identifier: identifier)
                : data
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
            pattern: #"(?i)full-path\s*=\s*["']([^"']+)["']"#,
            in: container
        ) else {
            return nil
        }
        return resolve(href: match, relativeTo: "")
    }

    // MARK: - Container Rewriting

    private static let xhtmlExtensions: Set<String> = ["xhtml", "html", "htm", "xht"]
    private static let defensiveStyle = """
    <style type="text/css">img,svg{max-width:100%;height:auto}body{overflow-wrap:break-word}table{max-width:100%;table-layout:fixed}pre,code{white-space:pre-wrap;word-wrap:break-word}*{box-sizing:border-box}</style>
    """

    // Compile once, not once per image/reference. Failure disables the text pass.
    private static let rewritePatterns = try? RewritePatterns()

    private nonisolated struct RewritePatterns {
        let tags: NSRegularExpression
        let attributes: NSRegularExpression
        let dimensions: NSRegularExpression
        let declarations: NSRegularExpression
        let cssURLs: NSRegularExpression
        let styles: NSRegularExpression
        let svg: NSRegularExpression
        let identifier: NSRegularExpression
        let document: NSRegularExpression

        init() throws {
            func regex(_ pattern: String) throws -> NSRegularExpression {
                try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
            }
            // Treat comments, CDATA and scripts as opaque; quoted '>' is not a tag end.
            tags = try regex(#"<!--.*?-->|<!\[CDATA\[.*?\]\]>|<script\b[^>]*>.*?</script\s*>|</?([\w:-]+)\b(?:[^<>"']|"[^"]*"|'[^']*')*>"#)
            attributes = try regex(#"\s+([\w:-]+)\s*=\s*(["'])(.*?)\2"#)
            dimensions = try regex(#"\s+([\w:-]+)\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>/]+)"#)
            // Same declaration boundaries as the plugin: don't split quoted or
            // parenthesized values (e.g. a data URL containing semicolons).
            declarations = try regex(#"(?:^|(?<=;))\s*([-\w]+)\s*:(?:[^;"'()]|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\((?:\\.|[^()\\])*\))*;?"#)
            cssURLs = try regex(#"\burl\(\s*(?:(["'])(.*?)\1|([^'")\s]+))\s*\)"#)
            styles = try regex(#"(<style\b(?:[^<>"']|"[^"]*"|'[^']*')*>)(.*?)(</style\s*>)"#)
            svg = try regex(#"<(?:svg:)?svg\b(?:[^<>"']|"[^"]*"|'[^']*')*>.*?</(?:svg:)?svg\s*>"#)
            identifier = try regex(#"<(?:\w+:)?identifier\b((?:[^<>"']|"[^"]*"|'[^']*')*)>([^<]*)</(?:\w+:)?identifier\s*>"#)
            document = try regex(#"<(?:\w+:)?(html|package|ncx)\b(?:[^<>"']|"[^"]*"|'[^']*')*>.*</(?:\w+:)?\1\s*>"#)
        }
    }

    private static func containsSVG(in source: Archive, entries: [Entry], config: EPUBOptimizerConfig) throws -> Bool {
        for entry in entries where entry.type == .file
            && xhtmlExtensions.contains((entry.path as NSString).pathExtension.lowercased()) {
            let found = try autoreleasepool {
                let data = try extractData(entry, from: source, cap: config.maxEntryBytes)
                return String(data: data, encoding: .utf8)?.range(of: "<svg", options: .caseInsensitive) != nil
            }
            if found { return true }
        }
        return false
    }

    /// Byte-preserving fallback for undecodable or malformed text. All mutations
    /// are local; no partial rewrite escapes on failure.
    private static func rewriteEntry(
        _ data: Data, path: String, renamedPaths: [String: String], identifier: String?
    ) -> Data {
        let ext = (path as NSString).pathExtension.lowercased()
        guard xhtmlExtensions.contains(ext) || ["css", "opf", "ncx"].contains(ext),
              let text = String(data: data, encoding: .utf8),
              let patterns = rewritePatterns else { return data }
        if ext != "css" && patterns.document.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil {
            return data
        }
        let directory = (path as NSString).deletingLastPathComponent
        var result = text
        if ext == "css" {
            result = rewriteCSS(text, directory: directory, renamedPaths: renamedPaths, patterns: patterns)
        } else {
            var coverID: String?
            var fallbackCoverID: String?
            result = replacing(text, using: patterns.tags) { match, source in
                guard match.range(at: 1).location != NSNotFound else { return source.substring(with: match.range) }
                var tag = source.substring(with: match.range)
                let name = source.substring(with: match.range(at: 1)).lowercased().split(separator: ":").last.map(String.init) ?? ""
                guard !tag.hasPrefix("</") else { return tag }

                if ext == "opf" && name == "item" {
                    if let href = attribute("href", in: tag, patterns: patterns),
                       renamedReference(href, directory: directory, renamedPaths: renamedPaths) != nil {
                        tag = settingAttribute("media-type", to: "image/jpeg", in: tag, patterns: patterns)
                    }
                    if let properties = attribute("properties", in: tag, patterns: patterns) {
                        let remaining = properties.split(whereSeparator: \.isWhitespace).filter { $0 != "svg" }
                        tag = settingAttribute("properties", to: remaining.isEmpty ? nil : remaining.joined(separator: " "), in: tag, patterns: patterns)
                    }
                    if let id = attribute("id", in: tag, patterns: patterns),
                       attribute("media-type", in: tag, patterns: patterns)?.hasPrefix("image/") == true {
                        let properties = attribute("properties", in: tag, patterns: patterns) ?? ""
                        if properties.split(whereSeparator: \.isWhitespace).contains("cover-image") && coverID == nil {
                            coverID = id
                        }
                        let href = attribute("href", in: tag, patterns: patterns) ?? ""
                        if fallbackCoverID == nil && (id.lowercased().contains("cover") || href.lowercased().contains("cover")) {
                            fallbackCoverID = id
                        }
                    }
                }
                if xhtmlExtensions.contains(ext) && name == "img" {
                    tag = replacing(tag, using: patterns.dimensions) { dimension, source in
                        let name = source.substring(with: dimension.range(at: 1)).lowercased()
                        return name == "width" || name == "height" ? "" : source.substring(with: dimension.range)
                    }
                    if let style = attribute("style", in: tag, patterns: patterns) {
                        let stripped = replacing(style, using: patterns.declarations) { declaration, source in
                            let property = source.substring(with: declaration.range(at: 1)).lowercased()
                            return property == "width" || property == "height" ? "" : source.substring(with: declaration.range)
                        }
                        if stripped != style {
                            tag = settingAttribute("style", to: stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : stripped, in: tag, patterns: patterns)
                        }
                    }
                }
                if ext == "ncx" && name == "meta",
                   attribute("name", in: tag, patterns: patterns) == "dtb:uid", let identifier {
                    tag = settingAttribute("content", to: identifier, in: tag, patterns: patterns)
                }
                return replacing(tag, using: patterns.attributes) { attribute, source in
                    let name = source.substring(with: attribute.range(at: 1)).lowercased()
                    let value = source.substring(with: attribute.range(at: 3))
                    let rewritten: String
                    if ["src", "href", "xlink:href"].contains(name) {
                        rewritten = renamedReference(value, directory: directory, renamedPaths: renamedPaths) ?? value
                    } else if name == "style" {
                        rewritten = rewriteCSS(value, directory: directory, renamedPaths: renamedPaths, patterns: patterns)
                    } else {
                        return source.substring(with: attribute.range)
                    }
                    return replacingAttributeValue(attribute, source: source, with: rewritten)
                }
            }
            if xhtmlExtensions.contains(ext) {
                // Strip old img dimensions before unwrapping so the new image
                // keeps its intentional height:auto.
                result = replacing(result, using: patterns.svg) { match, source in
                    let block = source.substring(with: match.range)
                    for image in patterns.tags.matches(in: block, range: NSRange(block.startIndex..., in: block)) {
                        guard image.range(at: 1).location != NSNotFound else { continue }
                        let nsBlock = block as NSString
                        let name = nsBlock.substring(with: image.range(at: 1)).lowercased()
                        guard name == "image" || name == "svg:image" else { continue }
                        let tag = nsBlock.substring(with: image.range)
                        if let href = attribute("xlink:href", in: tag, patterns: patterns) ?? attribute("href", in: tag, patterns: patterns),
                           isRasterImagePath(String(href.prefix { $0 != "#" && $0 != "?" }).removingPercentEncoding ?? href) {
                            return #"<img style="max-width:100%;height:auto" src=""# + href.replacingOccurrences(of: "\"", with: "&quot;") + #"" alt="" />"#
                        }
                    }
                    return block // True vector SVG is not a raster wrapper.
                }
                result = replacing(result, using: patterns.styles) { match, source in
                    source.substring(with: match.range(at: 1))
                        + rewriteCSS(source.substring(with: match.range(at: 2)), directory: directory, renamedPaths: renamedPaths, patterns: patterns)
                        + source.substring(with: match.range(at: 3))
                }
                if !result.contains(defensiveStyle),
                   let headEnd = result.range(of: "</head\\s*>", options: [.regularExpression, .caseInsensitive]) {
                    result.insert(contentsOf: defensiveStyle, at: headEnd.lowerBound)
                }
            } else if ext == "opf", let id = coverID ?? fallbackCoverID {
                var foundCover = false
                result = replacing(result, using: patterns.tags) { match, source in
                    let tag = source.substring(with: match.range)
                    guard match.range(at: 1).location != NSNotFound,
                          source.substring(with: match.range(at: 1)).split(separator: ":").last?.lowercased() == "meta",
                          attribute("name", in: tag, patterns: patterns) == "cover" else { return tag }
                    foundCover = true
                    return settingAttribute("content", to: id, in: tag, patterns: patterns)
                }
                if !foundCover, let end = result.range(of: #"</((?:\w+:)?)metadata\s*>"#, options: [.regularExpression, .caseInsensitive]) {
                    let closing = String(result[end])
                    let prefix = closing.dropFirst(2).split(separator: ":").count > 1
                        ? String(closing.dropFirst(2).prefix { $0 != ":" }) + ":" : ""
                    result.insert(contentsOf: "<\(prefix)meta name=\"cover\" content=\"\(id.replacingOccurrences(of: "\"", with: "&quot;"))\"/>", at: end.lowerBound)
                }
            }
        }
        return result == text ? data : Data(result.utf8)
    }

    private static func replacing(
        _ text: String, using regex: NSRegularExpression,
        transform: (NSTextCheckingResult, NSString) -> String
    ) -> String {
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }
        var result: NSMutableString?
        // Evaluate in document order (cover selection), apply using an offset.
        var offset = 0
        for match in matches {
            let replacement = transform(match, source)
            guard replacement != source.substring(with: match.range) else { continue }
            if result == nil { result = NSMutableString(string: text) }
            result?.replaceCharacters(in: NSRange(location: match.range.location + offset, length: match.range.length), with: replacement)
            offset += (replacement as NSString).length - match.range.length
        }
        return result.map { $0 as String } ?? text
    }

    private static func attribute(_ name: String, in tag: String, patterns: RewritePatterns) -> String? {
        let source = tag as NSString
        for match in patterns.attributes.matches(in: tag, range: NSRange(location: 0, length: source.length)) {
            if source.substring(with: match.range(at: 1)).lowercased() == name {
                return source.substring(with: match.range(at: 3))
            }
        }
        return nil
    }

    private static func replacingAttributeValue(_ match: NSTextCheckingResult, source: NSString, with value: String) -> String {
        let original = source.substring(with: match.range) as NSString
        let valueRange = NSRange(location: match.range(at: 3).location - match.range.location, length: match.range(at: 3).length)
        let quote = source.substring(with: match.range(at: 2))
        let escaped = value.replacingOccurrences(of: quote, with: quote == "\"" ? "&quot;" : "&apos;")
        return original.replacingCharacters(in: valueRange, with: escaped)
    }

    private static func settingAttribute(_ name: String, to value: String?, in tag: String, patterns: RewritePatterns) -> String {
        var found = false
        var result = replacing(tag, using: patterns.attributes) { match, source in
            guard source.substring(with: match.range(at: 1)).lowercased() == name else { return source.substring(with: match.range) }
            found = true
            return value.map { replacingAttributeValue(match, source: source, with: $0) } ?? ""
        }
        if !found, let value, let end = result.range(of: "/?>$", options: .regularExpression) {
            result.insert(contentsOf: " \(name)=\"\(value.replacingOccurrences(of: "\"", with: "&quot;"))\"", at: end.lowerBound)
        }
        return result
    }

    private static func renamedReference(_ href: String, directory: String, renamedPaths: [String: String]) -> String? {
        guard !renamedPaths.isEmpty, !href.hasPrefix("//"), !href.contains(":") else { return nil }
        let path = String(href.prefix { $0 != "#" && $0 != "?" })
        let resolved = resolve(href: path.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: directory)
        guard let renamed = renamedPaths[resolved] else { return nil }
        let basename = (renamed as NSString).lastPathComponent
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%&'\"()"))
        guard let encoded = basename.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        let prefix = path.lastIndex(of: "/").map { String(path[...$0]) } ?? ""
        return prefix + encoded + href.dropFirst(path.count)
    }

    private static func rewriteCSS(_ text: String, directory: String, renamedPaths: [String: String], patterns: RewritePatterns) -> String {
        guard !renamedPaths.isEmpty else { return text }
        return replacing(text, using: patterns.cssURLs) { match, source in
            let valueRange = match.range(at: match.range(at: 2).location == NSNotFound ? 3 : 2)
            let value = source.substring(with: valueRange)
            guard let renamed = renamedReference(value, directory: directory, renamedPaths: renamedPaths) else {
                return source.substring(with: match.range)
            }
            let original = source.substring(with: match.range) as NSString
            return original.replacingCharacters(
                in: NSRange(location: valueRange.location - match.range.location, length: valueRange.length),
                with: renamed
            )
        }
    }

    private static func packageIdentifier(in text: String) -> String? {
        guard let patterns = rewritePatterns else { return nil }
        let source = text as NSString
        let tags = patterns.tags.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard let package = tags.first(where: {
            $0.range(at: 1).location != NSNotFound
                && source.substring(with: $0.range(at: 1)).split(separator: ":").last?.lowercased() == "package"
        }), let id = attribute("unique-identifier", in: source.substring(with: package.range), patterns: patterns) else { return nil }
        for match in patterns.identifier.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            if attribute("id", in: source.substring(with: match.range(at: 1)), patterns: patterns) == id {
                let value = source.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Resolves a (possibly percent-encoded, possibly relative) manifest href
    /// against the OPF's directory into a zip entry path.
    private static func resolve(href: String, relativeTo opfDir: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        var components = opfDir.isEmpty || decoded.hasPrefix("/") ? [] : opfDir.split(separator: "/").map(String.init)
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
