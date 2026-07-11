import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZIPFoundation
@testable import SendToX4

struct EPUBOptimizerTests {

    // MARK: - Fixture Builders

    /// Renders a solid-color PNG of the given size.
    private static func makePNG(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Add some variation so PNG doesn't compress to nothing
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1))
        for i in stride(from: 0, to: width, by: 17) {
            context.fill(CGRect(x: i, y: (i * 7) % max(1, height - 40), width: 11, height: 37))
        }
        let image = try #require(context.makeImage())

        let out = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return out as Data
    }

    /// Builds a minimal EPUB containing one XHTML chapter and one PNG image.
    private static func makeEPUB(imageData: Data, imagePath: String = "OEBPS/images/pic.png") throws -> Data {
        let archive = try #require(Archive(accessMode: .create))

        func add(_ path: String, _ data: Data, compression: CompressionMethod) throws {
            try archive.addEntry(
                with: path, type: .file,
                uncompressedSize: UInt32(Int64(data.count)),
                compressionMethod: compression,
                provider: { position, size in data.subdata(in: position..<(position + size)) }
            )
        }

        try add("mimetype", Data("application/epub+zip".utf8), compression: .none)
        try add("META-INF/container.xml", Data(EPUBTemplates.containerXML.utf8), compression: .deflate)

        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="BookId">test-uuid</dc:identifier>
            <dc:title>Optimizer Fixture</dc:title>
            <dc:language>en</dc:language>
          </metadata>
          <manifest>
            <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>
            <item id="pic" href="images/pic.png" media-type="image/png"/>
          </manifest>
          <spine><itemref idref="content"/></spine>
        </package>
        """
        try add("OEBPS/content.opf", Data(opf.utf8), compression: .deflate)

        let xhtml = """
        <html xmlns="http://www.w3.org/1999/xhtml"><body>
        <p>Fixture body.</p><img src="images/pic.png" alt="pic"/>
        </body></html>
        """
        try add("OEBPS/content.xhtml", Data(xhtml.utf8), compression: .deflate)
        try add(imagePath, imageData, compression: .none)

        return try #require(archive.data)
    }

    private static func entry(_ path: String, in epub: Data) throws -> (entry: Entry, data: Data) {
        let archive = try #require(Archive(data: epub, accessMode: .read))
        let entry = try #require(archive[path])
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return (entry, data)
    }

    private static func imageInfo(_ data: Data) throws -> (width: Int, height: Int, type: String) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let type = try #require(CGImageSourceGetType(source) as String?)
        let width = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        return (width, height, type)
    }

    // MARK: - Tests

    @Test func oversizedPNGBecomesGrayscaleJPEGWithinPanel() async throws {
        let png = try Self.makePNG(width: 2000, height: 3000)
        let epub = try Self.makeEPUB(imageData: png)

        let optimized = await EPUBOptimizer.optimize(epubData: epub)
        #expect(optimized.count < epub.count)

        let (_, imageData) = try Self.entry("OEBPS/images/pic.png", in: optimized)
        // JPEG magic bytes
        #expect(imageData.prefix(2) == Data([0xFF, 0xD8]))

        let info = try Self.imageInfo(imageData)
        #expect(info.type == UTType.jpeg.identifier)
        #expect(info.width <= 480)
        #expect(info.height <= 800)

        // Manifest media-type was rewritten
        let (_, opfData) = try Self.entry("OEBPS/content.opf", in: optimized)
        let opf = String(decoding: opfData, as: UTF8.self)
        #expect(opf.contains("href=\"images/pic.png\" media-type=\"image/jpeg\""))

        // mimetype still first + stored
        let archive = try #require(Archive(data: optimized, accessMode: .read))
        let first = try #require(archive.compactMap { $0 }.first)
        #expect(first.path == "mimetype")
        #expect(first.compressedSize == first.uncompressedSize)

        // Non-image entries are byte-identical
        let (_, originalXHTML) = try Self.entry("OEBPS/content.xhtml", in: epub)
        let (_, optimizedXHTML) = try Self.entry("OEBPS/content.xhtml", in: optimized)
        #expect(originalXHTML == optimizedXHTML)
    }

    @Test func tinySeparatorPNGKeepsDimensions() async throws {
        let png = try Self.makePNG(width: 100, height: 80)
        let epub = try Self.makeEPUB(imageData: png)

        let optimized = await EPUBOptimizer.optimize(epubData: epub)
        let (_, imageData) = try Self.entry("OEBPS/images/pic.png", in: optimized)
        let info = try Self.imageInfo(imageData)
        // Tiny device-friendly images are copied through untouched
        #expect(info.width == 100)
        #expect(info.height == 80)
        #expect(info.type == UTType.png.identifier)
    }

    @Test func corruptZipReturnsInputUnchanged() async {
        let garbage = Data((0..<4096).map { UInt8($0 % 251) })
        let result = await EPUBOptimizer.optimize(epubData: garbage)
        #expect(result == garbage)
    }

    @Test func epubWithoutImagesIsUntouched() async throws {
        let metadata = EPUBBuilder.Metadata(
            title: "Text Only",
            author: "Author",
            language: "en",
            sourceURL: URL(string: "https://example.com")!,
            description: ""
        )
        let epub = try EPUBBuilder.build(body: "<p>Just text content in here.</p>", metadata: metadata)
        let result = await EPUBOptimizer.optimize(epubData: epub)
        #expect(result == epub)
    }

    @Test func disabledOrNonEPUBFilesPassThrough() async {
        let data = Data("not an epub".utf8)
        let untouchedDisabled = await EPUBOptimizer.optimizeIfNeeded(data, filename: "book.epub", enabled: false)
        #expect(untouchedDisabled == data)
        let untouchedOtherType = await EPUBOptimizer.optimizeIfNeeded(data, filename: "font.ttf", enabled: true)
        #expect(untouchedOtherType == data)
    }

    @Test func decompressionBombIsSkippedNotDecoded() async throws {
        // 9000x9000 = 81 MP, above the 50 MP guard: entry must be copied
        // through unmodified (and quickly, since it's never fully decoded).
        let png = try Self.makePNG(width: 9000, height: 9000)
        let epub = try Self.makeEPUB(imageData: png)

        let optimized = await EPUBOptimizer.optimize(epubData: epub)
        // Either passthrough of the whole EPUB (not smaller) or entry copy —
        // both mean the original PNG bytes survive.
        let (_, imageData) = try Self.entry("OEBPS/images/pic.png", in: optimized)
        #expect(imageData == png)
    }
}
