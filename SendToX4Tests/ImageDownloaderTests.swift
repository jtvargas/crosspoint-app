import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SendToX4

/// URLProtocol stub serving canned responses keyed by URL.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [URL: Result<(Data, Int), Error>] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let stub = Self.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch stub {
        case .success(let (data, status)):
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": String(data.count)]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

struct ImageDownloaderTests {

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func makeJPEG(width: Int = 600, height: Int = 400) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.5, green: 0.7, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    @Test func downloadsAndProcessesImages() async throws {
        let goodURL = URL(string: "https://img.example.com/a.jpg")!
        StubURLProtocol.responses = [goodURL: .success((Self.makeJPEG(), 200))]

        let refs = [ImageRef(index: 0, absoluteURL: goodURL, alt: "A")]
        let (images, failed) = await ImageDownloader.download(
            refs, session: Self.makeSession()
        )

        #expect(images.count == 1)
        #expect(failed.isEmpty)
        #expect(images[0].path == "images/img-0.jpg")
        #expect(images[0].mediaType == "image/jpeg")
        #expect(images[0].data.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func failuresLandInFailedListNotErrors() async {
        let good = URL(string: "https://img.example.com/good.jpg")!
        let broken = URL(string: "https://img.example.com/broken.jpg")!
        let notImage = URL(string: "https://img.example.com/page.html")!
        StubURLProtocol.responses = [
            good: .success((Self.makeJPEG(), 200)),
            broken: .failure(URLError(.timedOut)),
            notImage: .success((Data("<html></html>".utf8), 200)),
        ]

        let refs = [
            ImageRef(index: 0, absoluteURL: good, alt: "ok"),
            ImageRef(index: 1, absoluteURL: broken, alt: "timeout"),
            ImageRef(index: 2, absoluteURL: notImage, alt: "not an image"),
        ]
        let (images, failed) = await ImageDownloader.download(
            refs, session: Self.makeSession()
        )

        #expect(images.count == 1)
        #expect(images[0].path == "images/img-0.jpg")
        #expect(failed.count == 2)
        #expect(failed.contains(refs[1]))
        #expect(failed.contains(refs[2]))
    }

    @Test func perImageByteCapRejectsOversizedResponses() async {
        let url = URL(string: "https://img.example.com/huge.jpg")!
        StubURLProtocol.responses = [url: .success((Data(count: 200_000), 200))]

        var limits = ImageLimits.default
        limits.maxBytesPerImage = 100_000

        let refs = [ImageRef(index: 0, absoluteURL: url, alt: "huge")]
        let (images, failed) = await ImageDownloader.download(
            refs, limits: limits, session: Self.makeSession()
        )
        #expect(images.isEmpty)
        #expect(failed.count == 1)
    }

    @Test func countCapMarksOverflowAsFailed() async {
        let url = URL(string: "https://img.example.com/only.jpg")!
        StubURLProtocol.responses = [url: .success((Self.makeJPEG(), 200))]

        var limits = ImageLimits.default
        limits.maxCount = 1

        let refs = [
            ImageRef(index: 0, absoluteURL: url, alt: "kept"),
            ImageRef(index: 1, absoluteURL: url, alt: "over cap"),
        ]
        let (images, failed) = await ImageDownloader.download(
            refs, limits: limits, session: Self.makeSession()
        )
        #expect(images.count == 1)
        #expect(failed.count == 1)
        #expect(failed[0].index == 1)
    }

    @Test func httpErrorStatusFails() async {
        let url = URL(string: "https://img.example.com/404.jpg")!
        StubURLProtocol.responses = [url: .success((Data(), 404))]

        let refs = [ImageRef(index: 0, absoluteURL: url, alt: "missing")]
        let (images, failed) = await ImageDownloader.download(
            refs, session: Self.makeSession()
        )
        #expect(images.isEmpty)
        #expect(failed.count == 1)
    }
}
