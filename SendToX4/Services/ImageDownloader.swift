import Foundation

/// Hard limits for article image downloading. All caps degrade gracefully:
/// exceeding a cap marks the image as failed (alt-text fallback), never
/// fails the conversion.
struct ImageLimits: Sendable {
    var maxCount = 20
    var maxBytesPerImage = 10 * 1024 * 1024
    var maxTotalBytes = 40 * 1024 * 1024
    var perImageTimeoutSeconds: TimeInterval = 12
    var maxConcurrent = 4

    static let `default` = ImageLimits()
}

/// A downloaded, re-encoded image ready for EPUB embedding.
struct EPUBImage: Sendable {
    /// EPUB path relative to OEBPS/ (e.g. "images/img-3.jpg").
    let path: String
    let data: Data
    let mediaType: String
    let width: Int
    let height: Int
    /// Marked by the conversion pipeline on the image used as the EPUB cover.
    var isCover = false
}

/// Downloads article images concurrently with strict limits and re-encodes
/// them via `ImageProcessor`. Never throws — failures land in the `failed`
/// list so the pipeline can degrade those images to alt text.
nonisolated enum ImageDownloader {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    /// Download and re-encode the referenced images.
    ///
    /// - Returns: Successfully processed images (order matches `refs`) and
    ///   the refs that failed (download error, over caps, undecodable).
    static func download(
        _ refs: [ImageRef],
        limits: ImageLimits = .default,
        session: URLSession? = nil
    ) async -> (images: [EPUBImage], failed: [ImageRef]) {
        guard !refs.isEmpty else { return ([], []) }
        let session = session ?? Self.session

        let capped = Array(refs.prefix(limits.maxCount))
        let overflow = Array(refs.dropFirst(limits.maxCount))

        // Bounded-concurrency fan-out
        var results: [Int: EPUBImage] = [:]
        await withTaskGroup(of: (Int, EPUBImage?).self) { group in
            var iterator = capped.enumerated().makeIterator()
            var inFlight = 0

            func addNext() {
                guard let (offset, ref) = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    let image = await fetchAndProcess(ref, limits: limits, session: session)
                    return (offset, image)
                }
            }

            for _ in 0..<limits.maxConcurrent { addNext() }

            while inFlight > 0 {
                guard let (offset, image) = await group.next() else { break }
                inFlight -= 1
                if let image { results[offset] = image }
                addNext()
            }
        }

        // Enforce the aggregate byte budget in document order
        var images: [EPUBImage] = []
        var failed: [ImageRef] = overflow
        var totalBytes = 0

        for (offset, ref) in capped.enumerated() {
            if let image = results[offset], totalBytes + image.data.count <= limits.maxTotalBytes {
                totalBytes += image.data.count
                images.append(image)
            } else {
                failed.append(ref)
            }
        }

        if !failed.isEmpty {
            DebugLogger.log(
                "Image download: \(images.count) embedded, \(failed.count) degraded to alt text",
                level: .info, category: .conversion
            )
        }

        return (images, failed)
    }

    // MARK: - Single Image

    /// Fetch one image with byte/time caps and re-encode it. Returns nil on
    /// any failure.
    private static func fetchAndProcess(
        _ ref: ImageRef,
        limits: ImageLimits,
        session: URLSession
    ) async -> EPUBImage? {
        var request = URLRequest(url: ref.absoluteURL, timeoutInterval: limits.perImageTimeoutSeconds)
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        guard let raw = try? await fetchBytes(request, cap: limits.maxBytesPerImage, session: session) else {
            return nil
        }

        guard let processed = ImageProcessor.reencode(raw) else { return nil }

        return EPUBImage(
            path: ref.placeholderPath,
            data: processed.data,
            mediaType: "image/jpeg",
            width: processed.width,
            height: processed.height
        )
    }

    private enum DownloadError: Error {
        case badResponse
        case overByteCap
    }

    /// Streams the response body, aborting as soon as the byte cap is hit
    /// (large responses never fully download).
    private static func fetchBytes(
        _ request: URLRequest,
        cap: Int,
        session: URLSession
    ) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw DownloadError.badResponse
        }

        // Early reject on declared length
        if http.expectedContentLength > 0, http.expectedContentLength > Int64(cap) {
            throw DownloadError.overByteCap
        }

        var data = Data()
        data.reserveCapacity(min(cap, Int(max(0, http.expectedContentLength))))
        for try await byte in bytes {
            data.append(byte)
            if data.count > cap {
                throw DownloadError.overByteCap
            }
        }
        return data
    }
}
