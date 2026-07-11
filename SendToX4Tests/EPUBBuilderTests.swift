import Foundation
import Testing
import ZIPFoundation
@testable import SendToX4

struct EPUBBuilderTests {

    private func makeMetadata(title: String = "Test Title") -> EPUBBuilder.Metadata {
        EPUBBuilder.Metadata(
            title: title,
            author: "Test Author",
            language: "en",
            sourceURL: URL(string: "https://example.com/article")!,
            description: "A test description"
        )
    }

    private func entries(of data: Data) throws -> [Entry] {
        let archive = try #require(Archive(data: data, accessMode: .read))
        return archive.compactMap { $0 }
    }

    private func extract(_ path: String, from data: Data) throws -> Data {
        let archive = try #require(Archive(data: data, accessMode: .read))
        let entry = try #require(archive[path])
        var out = Data()
        _ = try archive.extract(entry) { out.append($0) }
        return out
    }

    @Test func mimetypeIsFirstEntryAndStored() throws {
        let epub = try EPUBBuilder.build(body: "<p>Hello world content.</p>", metadata: makeMetadata())
        let all = try entries(of: epub)
        let first = try #require(all.first)
        #expect(first.path == "mimetype")
        // STORE means no compression: sizes match
        #expect(first.compressedSize == first.uncompressedSize)

        let content = try extract("mimetype", from: epub)
        #expect(String(data: content, encoding: .utf8) == "application/epub+zip")
    }

    @Test func containerOPFAndNCXAreWellFormedXML() throws {
        let epub = try EPUBBuilder.build(body: "<p>Body text.</p>", metadata: makeMetadata())
        for path in ["META-INF/container.xml", "OEBPS/content.opf", "OEBPS/toc.ncx"] {
            let data = try extract(path, from: epub)
            let parser = XMLParser(data: data)
            #expect(parser.parse(), "\(path) must be well-formed XML")
        }
    }

    @Test func ampersandInTitleEscapesExactlyOnce() throws {
        let epub = try EPUBBuilder.build(
            body: "<p>Some body content here.</p>",
            metadata: makeMetadata(title: "Fish & Chips <Deluxe>")
        )
        let opf = String(decoding: try extract("OEBPS/content.opf", from: epub), as: UTF8.self)
        #expect(opf.contains("Fish &amp; Chips &lt;Deluxe&gt;"))
        #expect(!opf.contains("&amp;amp;")) // no double escaping

        let ncx = String(decoding: try extract("OEBPS/toc.ncx", from: epub), as: UTF8.self)
        #expect(ncx.contains("Fish &amp; Chips &lt;Deluxe&gt;"))
        #expect(!ncx.contains("&amp;amp;"))

        let xhtml = String(decoding: try extract("OEBPS/content.xhtml", from: epub), as: UTF8.self)
        #expect(xhtml.contains("Fish &amp; Chips"))
        #expect(!xhtml.contains("&amp;amp;"))
    }

    @Test func multiChapterSpineIsInOrder() throws {
        let chapters = (0..<3).map {
            Chapter(index: $0, title: "Chapter \($0 + 1)", bodyHTML: "<p>Content \($0).</p>")
        }
        let epub = try EPUBBuilder.build(chapters: chapters, metadata: makeMetadata())

        let opf = String(decoding: try extract("OEBPS/content.opf", from: epub), as: UTF8.self)
        let idx0 = try #require(opf.range(of: "idref=\"chapter-0\""))
        let idx1 = try #require(opf.range(of: "idref=\"chapter-1\""))
        let idx2 = try #require(opf.range(of: "idref=\"chapter-2\""))
        #expect(idx0.lowerBound < idx1.lowerBound)
        #expect(idx1.lowerBound < idx2.lowerBound)

        // Each chapter file exists
        let paths = try entries(of: epub).map(\.path)
        #expect(paths.contains("OEBPS/chapter-0.xhtml"))
        #expect(paths.contains("OEBPS/chapter-1.xhtml"))
        #expect(paths.contains("OEBPS/chapter-2.xhtml"))
    }

    @Test func emptyChaptersThrow() {
        #expect(throws: EPUBError.self) {
            _ = try EPUBBuilder.build(chapters: [], metadata: makeMetadata())
        }
    }

    @Test func embeddedImagesAppearInManifestWithCover() throws {
        let jpegStub = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(count: 64)
        var cover = EPUBImage(
            path: "images/img-0.jpg", data: jpegStub,
            mediaType: "image/jpeg", width: 800, height: 600
        )
        cover.isCover = true
        let second = EPUBImage(
            path: "images/img-1.jpg", data: jpegStub,
            mediaType: "image/jpeg", width: 200, height: 150
        )

        let epub = try EPUBBuilder.build(
            body: "<p>Body with images.</p><img src=\"images/img-0.jpg\" alt=\"a\"/>",
            metadata: makeMetadata(),
            images: [cover, second]
        )

        // Image bytes are embedded at OEBPS/<path>
        let img0 = try extract("OEBPS/images/img-0.jpg", from: epub)
        #expect(img0 == jpegStub)
        let img1 = try extract("OEBPS/images/img-1.jpg", from: epub)
        #expect(img1 == jpegStub)

        // Manifest declares both, cover uses the conventional id + meta
        let opf = String(decoding: try extract("OEBPS/content.opf", from: epub), as: UTF8.self)
        #expect(opf.contains("<item id=\"cover-image\" href=\"images/img-0.jpg\" media-type=\"image/jpeg\"/>"))
        #expect(opf.contains("href=\"images/img-1.jpg\""))
        #expect(opf.contains("<meta name=\"cover\" content=\"cover-image\"/>"))

        // Still well-formed XML
        #expect(XMLParser(data: Data(opf.utf8)).parse())
    }

    @Test func noImagesMeansNoImageManifestEntries() throws {
        let epub = try EPUBBuilder.build(body: "<p>Plain text body.</p>", metadata: makeMetadata())
        let opf = String(decoding: try extract("OEBPS/content.opf", from: epub), as: UTF8.self)
        #expect(!opf.contains("media-type=\"image/jpeg\""))
        #expect(!opf.contains("name=\"cover\""))
    }
}
