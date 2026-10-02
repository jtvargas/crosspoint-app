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
    private static func makeEPUB(
        imageData: Data,
        imagePath: String = "OEBPS/images/pic.png",
        chapter: String? = nil,
        package: String? = nil,
        extraEntries: [String: Data] = [:]
    ) throws -> Data {
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

        let href = String(imagePath.dropFirst("OEBPS/".count))
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? imagePath
        let opf = package ?? """
        <?xml version="1.0" encoding="UTF-8"?>
        <package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="BookId">test-uuid</dc:identifier>
            <dc:title>Optimizer Fixture</dc:title>
            <dc:language>en</dc:language>
          </metadata>
          <manifest>
            <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>
            <item id="pic" href="\(href)" media-type="image/png"/>
          </manifest>
          <spine><itemref idref="content"/></spine>
        </package>
        """
        try add("OEBPS/content.opf", Data(opf.utf8), compression: .deflate)

        let xhtml = chapter ?? """
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Fixture</title></head><body>
        <p>Fixture body.</p><img src="\(href)" alt="pic"/>
        </body></html>
        """
        try add("OEBPS/content.xhtml", Data(xhtml.utf8), compression: .deflate)
        try add(imagePath, imageData, compression: .none)
        for (path, data) in extraEntries.sorted(by: { $0.key < $1.key }) {
            try add(path, data, compression: .none)
        }

        return try #require(archive.data)
    }

    private static func entry(_ path: String, in epub: Data) throws -> (entry: Entry, data: Data) {
        let archive = try #require(Archive(data: epub, accessMode: .read))
        let entry = try #require(archive[path])
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return (entry, data)
    }

    private static func textEntry(_ path: String, in epub: Data) throws -> String {
        let (_, data) = try entry(path, in: epub)
        return try #require(String(data: data, encoding: .utf8))
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

        let (_, imageData) = try Self.entry("OEBPS/images/pic.jpg", in: optimized)
        // JPEG magic bytes
        #expect(imageData.prefix(2) == Data([0xFF, 0xD8]))

        let info = try Self.imageInfo(imageData)
        #expect(info.type == UTType.jpeg.identifier)
        #expect(info.width <= 480)
        #expect(info.height <= 800)

        // Manifest media-type was rewritten
        let (_, opfData) = try Self.entry("OEBPS/content.opf", in: optimized)
        let opf = String(decoding: opfData, as: UTF8.self)
        #expect(opf.contains("href=\"images/pic.jpg\" media-type=\"image/jpeg\""))

        // mimetype still first + stored
        let archive = try #require(Archive(data: optimized, accessMode: .read))
        let first = try #require(archive.compactMap { $0 }.first)
        #expect(first.path == "mimetype")
        #expect(first.compressedSize == first.uncompressedSize)

        #expect(archive["OEBPS/images/pic.png"] == nil)
    }

    @Test func convertedReferencesResolveAcrossContainer() async throws {
        let png = try Self.makePNG(width: 2000, height: 3000)
        let tiny = try Self.makePNG(width: 50, height: 40)
        let chapter = """
        <html><head><title>Refs</title></head><body>
        <img src="./images/pic%20one.PNG#part" alt="résumé"/>
        <img src="images/tiny.png"/><img src="images/broken.gif"/>
        <img src="https://example.com/images/pic%20one.PNG"/>
        </body></html>
        """
        let css = """
        .cover { background: url('../images/pic%20one.PNG?size=1#part') }
        .other { background: url(../images/tiny.png) }
        """
        let epub = try Self.makeEPUB(
            imageData: png, imagePath: "OEBPS/images/pic one.PNG", chapter: chapter,
            extraEntries: [
                "OEBPS/styles/book.CSS": Data(css.utf8),
                "OEBPS/images/tiny.png": tiny,
                "OEBPS/images/broken.gif": Data("not an image".utf8)
            ]
        )
        let optimized = await EPUBOptimizer.optimize(epubData: epub)
        let archive = try #require(Archive(data: optimized, accessMode: .read))
        #expect(archive["OEBPS/images/pic one.PNG"] == nil)
        #expect(archive["OEBPS/images/pic one.jpg"] != nil)
        let xhtml = try Self.textEntry("OEBPS/content.xhtml", in: optimized)
        #expect(xhtml.contains(#"src="./images/pic%20one.jpg#part""#))
        #expect(xhtml.contains(#"src="images/tiny.png""#))
        #expect(xhtml.contains(#"src="images/broken.gif""#))
        #expect(xhtml.contains(#"src="https://example.com/images/pic%20one.PNG""#))
        #expect(xhtml.contains("résumé"))
        let rewrittenCSS = try Self.textEntry("OEBPS/styles/book.CSS", in: optimized)
        #expect(rewrittenCSS.contains("url('../images/pic%20one.jpg?size=1#part')"))
        #expect(rewrittenCSS.contains("url(../images/tiny.png)"))
        let opf = try Self.textEntry("OEBPS/content.opf", in: optimized)
        #expect(opf.contains(#"href="images/pic%20one.jpg" media-type="image/jpeg""#))
        let (_, untouched) = try Self.entry("OEBPS/images/tiny.png", in: optimized)
        #expect(untouched == tiny)
    }

    @Test func stripsOnlyImageDimensionsAndPreservesOtherStyleDeclarations() async throws {
        let chapter = """
        <html><head></head><body>
        <IMG src="images/pic.png" WIDTH='2000' height="3000" style="width:2000px; HEIGHT: 3000px;max-width:100%;border:0;background:url('data:image/png;base64,AAAA');" alt="cover"/>
        <img src="images/pic.png" width=2000 height=3000 style='width:100%;height:auto'/>
        <table width="400"><tr><td>Keep table sizing</td></tr></table>
        </body></html>
        """
        let epub = try Self.makeEPUB(imageData: Self.makePNG(width: 2000, height: 3000), chapter: chapter)
        let optimized = await EPUBOptimizer.optimize(epubData: epub)
        let xhtml = try Self.textEntry("OEBPS/content.xhtml", in: optimized)
        #expect(xhtml.contains(#"<IMG src="images/pic.jpg" style="max-width:100%;border:0;background:url('data:image/png;base64,AAAA');" alt="cover"/>"#))
        #expect(xhtml.contains(#"<img src="images/pic.jpg"/>"#))
        #expect(xhtml.contains(#"<table width="400">"#))
    }

    @Test(arguments: ["xhtml", "HTML", "XHT"])
    func unwrapsSVGRasterWrappers(extension ext: String) async throws {
        let chapter = """
        <html><head></head><body>
        <svg:svg xmlns:svg="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="2000">
          <svg:image xlink:href="../images/pic.png" width="2000" height="3000"/>
        </svg:svg>
        <svg><path d="M0 0L10 10"/></svg>
        </body></html>
        """
        let path = "OEBPS/text/cover.\(ext)"
        let epub = try Self.makeEPUB(
            imageData: Self.makePNG(width: 2000, height: 3000),
            extraEntries: [path: Data(chapter.utf8)]
        )
        let optimized = await EPUBOptimizer.optimize(epubData: epub)
        let xhtml = try Self.textEntry(path, in: optimized)
        #expect(xhtml.contains(#"<img style="max-width:100%;height:auto" src="../images/pic.jpg" alt="" />"#))
        #expect(xhtml.contains("<svg:svg") == false)
        #expect(xhtml.contains(#"<svg><path d="M0 0L10 10"/></svg>"#))
    }

    @Test func svgWrapperIsRewrittenEvenWhenNoImageWasConverted() async throws {
        let chapter = """
        <html><head></head><body><svg><image href="images/pic.png"/></svg></body></html>
        """
        let png = try Self.makePNG(width: 100, height: 80)
        let epub = try Self.makeEPUB(
            imageData: png, chapter: chapter,
            extraEntries: ["OEBPS/padding.txt": Data(String(repeating: "text ", count: 1000).utf8)]
        )
        let optimized = await EPUBOptimizer.optimize(epubData: epub)
        let xhtml = try Self.textEntry("OEBPS/content.xhtml", in: optimized)
        #expect(xhtml.contains(#"<img style="max-width:100%;height:auto" src="images/pic.png" alt="" />"#))
        let (_, unchanged) = try Self.entry("OEBPS/images/pic.png", in: optimized)
        #expect(unchanged == png)
    }

    @Test(arguments: [false, true])
    func defensiveStylesheetIsPresentExactlyOnce(alreadyPresent: Bool) async throws {
        let style = """
        <style type="text/css">img,svg{max-width:100%;height:auto}body{overflow-wrap:break-word}table{max-width:100%;table-layout:fixed}pre,code{white-space:pre-wrap;word-wrap:break-word}*{box-sizing:border-box}</style>
        """
        let chapter = "<html><head><title>Cover</title>\(alreadyPresent ? style : "")</head><body><img src=\"images/pic.png\"/></body></html>"
        let epub = try Self.makeEPUB(imageData: Self.makePNG(width: 2000, height: 3000), chapter: chapter)
        let optimized = await EPUBOptimizer.optimize(epubData: epub)
        let xhtml = try Self.textEntry("OEBPS/content.xhtml", in: optimized)
        #expect(xhtml.components(separatedBy: style).count == 2)
        #expect(xhtml.contains(style + "</head>"))
    }

    @Test(arguments: [false, true])
    func packageCoverAndNCXIdentifierAreRepaired(existingCoverMeta: Bool) async throws {
        let package = """
        <package unique-identifier='BookId' xmlns:dc="http://purl.org/dc/elements/1.1/">
        <metadata><dc:identifier id="Other">wrong-id</dc:identifier>
        <dc:identifier id='BookId'> urn:uuid:correct&amp;id </dc:identifier>
        \(existingCoverMeta ? "<meta content='wrong-cover' name='cover'/>" : "")
        </metadata><manifest>
        <item properties="svg scripted" id="chapter" href="content.xhtml" media-type="application/xhtml+xml"/>
        <item media-type='image/png' properties='cover-image svg' href='images/pic.png' id='cover-image-id'/>
        </manifest></package>
        """
        let ncx = """
        <ncx><head><meta content='wrong-id' name='dtb:uid'/></head>
        <navMap><navPoint><content src="images/pic.png#cover"/></navPoint></navMap></ncx>
        """
        let epub = try Self.makeEPUB(
            imageData: Self.makePNG(width: 2000, height: 3000), package: package,
            extraEntries: ["OEBPS/toc.NCX": Data(ncx.utf8)]
        )
        let optimized = await EPUBOptimizer.optimize(epubData: epub)
        let opf = try Self.textEntry("OEBPS/content.opf", in: optimized)
        #expect(opf.contains(#"properties="scripted""#))
        #expect(opf.contains("properties='cover-image'"))
        #expect(opf.contains("media-type='image/jpeg'"))
        #expect(opf.contains("href='images/pic.jpg'"))
        #expect(opf.contains("wrong-cover") == false)
        if existingCoverMeta {
            #expect(opf.contains("content='cover-image-id' name='cover'"))
        } else {
            #expect(opf.contains(#"<meta name="cover" content="cover-image-id"/>"#))
        }
        let rewrittenNCX = try Self.textEntry("OEBPS/toc.NCX", in: optimized)
        #expect(rewrittenNCX.contains("content='urn:uuid:correct&amp;id' name='dtb:uid'"))
        #expect(rewrittenNCX.contains(#"src="images/pic.jpg#cover""#))
    }

    @Test(arguments: ["garbage <img src='images/pic.png' width='2000'>", "<html><head>unfinished", "\u{FFFD}not markup"])
    func malformedXHTMLPassesThroughUnchanged(chapter: String) async throws {
        let epub = try Self.makeEPUB(imageData: Self.makePNG(width: 2000, height: 3000), chapter: chapter)
        let optimized = await EPUBOptimizer.optimize(epubData: epub)
        let (_, original) = try Self.entry("OEBPS/content.xhtml", in: epub)
        let (_, unchanged) = try Self.entry("OEBPS/content.xhtml", in: optimized)
        #expect(unchanged == original)
    }

    @Test func renamedImageDoesNotOverwriteExistingJPEG() async throws {
        let existing = Data("undecodable existing image".utf8)
        let epub = try Self.makeEPUB(
            imageData: Self.makePNG(width: 2000, height: 3000),
            extraEntries: ["OEBPS/images/pic.jpg": existing]
        )
        let optimized = await EPUBOptimizer.optimize(epubData: epub)
        let (_, unchanged) = try Self.entry("OEBPS/images/pic.jpg", in: optimized)
        #expect(unchanged == existing)
        let xhtml = try Self.textEntry("OEBPS/content.xhtml", in: optimized)
        #expect(xhtml.contains(#"src="images/pic-1.jpg""#))
        let (_, jpeg) = try Self.entry("OEBPS/images/pic-1.jpg", in: optimized)
        #expect(jpeg.prefix(2) == Data([0xFF, 0xD8]))
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
