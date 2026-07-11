import Foundation
import Testing
@testable import SendToX4

struct EPUBDocumentTests {

    private func makeMetadata(title: String = "Reader Fixture") -> EPUBBuilder.Metadata {
        EPUBBuilder.Metadata(
            title: title,
            author: "Reader Author",
            language: "en",
            sourceURL: URL(string: "https://example.com/reader")!,
            description: "For reader tests"
        )
    }

    private func writeTempEPUB(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-test-\(UUID().uuidString).epub")
        try data.write(to: url)
        return url
    }

    @Test func opensSingleChapterEPUB() throws {
        let epub = try EPUBBuilder.build(
            body: "<p>Single chapter content for the reader.</p>",
            metadata: makeMetadata()
        )
        let url = try writeTempEPUB(epub)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try EPUBDocument(fileURL: url)
        #expect(document.title == "Reader Fixture")
        #expect(document.spine.count == 1)
        #expect(document.spine[0].path == "OEBPS/content.xhtml")
        #expect(document.spine[0].anchor == "chapter-0")
    }

    @Test func spineFollowsChapterOrderWithNCXTitles() throws {
        let chapters = (0..<3).map {
            Chapter(index: $0, title: "Section \($0 + 1)", bodyHTML: "<p>Chapter body \($0).</p>")
        }
        let epub = try EPUBBuilder.build(chapters: chapters, metadata: makeMetadata())
        let url = try writeTempEPUB(epub)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try EPUBDocument(fileURL: url)
        #expect(document.spine.count == 3)
        #expect(document.spine.map(\.title) == ["Section 1", "Section 2", "Section 3"])
        #expect(document.spine.map(\.path) == [
            "OEBPS/chapter-0.xhtml", "OEBPS/chapter-1.xhtml", "OEBPS/chapter-2.xhtml"
        ])
    }

    @Test func combinedHTMLContainsAllChaptersWithAnchors() throws {
        let chapters = (0..<3).map {
            Chapter(index: $0, title: "Part \($0 + 1)", bodyHTML: "<p>Unique-content-\($0).</p>")
        }
        let epub = try EPUBBuilder.build(chapters: chapters, metadata: makeMetadata())
        let url = try writeTempEPUB(epub)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try EPUBDocument(fileURL: url)
        let html = document.combinedHTML()

        for i in 0..<3 {
            #expect(html.contains("<section id=\"chapter-\(i)\">"))
            #expect(html.contains("Unique-content-\(i)"))
        }
        // Reader chrome injected
        #expect(html.contains("--font-scale"))
        #expect(html.contains("crossxRestoreProgress"))
        // Chapter <head>/<style> boilerplate must not leak into sections
        #expect(!html.contains("XHTML 1.1//EN"))
    }

    @Test func servesEmbeddedImageResources() throws {
        let jpegStub = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(count: 32)
        let image = EPUBImage(
            path: "images/img-0.jpg", data: jpegStub,
            mediaType: "image/jpeg", width: 500, height: 400
        )
        let epub = try EPUBBuilder.build(
            body: "<p>Body.</p><img src=\"images/img-0.jpg\" alt=\"pic\"/>",
            metadata: makeMetadata(),
            images: [image]
        )
        let url = try writeTempEPUB(epub)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try EPUBDocument(fileURL: url)
        // The scheme handler resolves reader hrefs against the OPF directory
        let packagePath = document.packagePath(forReaderHref: "images/img-0.jpg")
        #expect(packagePath == "OEBPS/images/img-0.jpg")
        #expect(document.resource(at: packagePath) == jpegStub)
    }

    @Test func missingFileThrows() {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).epub")
        #expect(throws: (any Error).self) {
            _ = try EPUBDocument(fileURL: bogus)
        }
    }

    @Test func escapedTitleRoundTripsForDisplay() throws {
        let epub = try EPUBBuilder.build(
            body: "<p>Body content for escaping test.</p>",
            metadata: makeMetadata(title: "Fish & Chips")
        )
        let url = try writeTempEPUB(epub)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try EPUBDocument(fileURL: url)
        #expect(document.title == "Fish & Chips")
    }
}
