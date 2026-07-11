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
}
