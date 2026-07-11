import Testing
@testable import SendToX4

struct ChapterSplitterTests {

    /// A paragraph of ~120 characters for building long fixtures.
    private static let para = "<p>The quick brown fox jumps over the lazy dog while the reader keeps reading this long test sentence again and again.</p>"

    @Test func shortContentStaysSingleChapter() throws {
        let body = "<p>Short article body.</p>"
        let chapters = try ChapterSplitter.split(body: body, articleTitle: "Title")
        #expect(chapters.count == 1)
        #expect(chapters[0].title == "Title")
        #expect(chapters[0].bodyHTML == body)
    }

    @Test func splitsAtH2HeadingsWithTitlesAndOrder() throws {
        // Build > 15k chars with three h2 sections
        let section = String(repeating: Self.para, count: 50) // ~6000 chars each
        let body = """
        <p>Preamble text.</p>
        <h2>First Section</h2>\(section)
        <h2>Second Section</h2>\(section)
        <h2>Third Section</h2>\(section)
        """
        let chapters = try ChapterSplitter.split(body: body, articleTitle: "Article")
        #expect(chapters.count == 4)
        #expect(chapters[0].title == "Article")          // preamble
        #expect(chapters[1].title == "First Section")
        #expect(chapters[2].title == "Second Section")
        #expect(chapters[3].title == "Third Section")
        #expect(chapters.map(\.index) == [0, 1, 2, 3])
    }

    @Test func h2TitleIsNotDuplicatedInChapterBody() throws {
        let section = String(repeating: Self.para, count: 50)
        let body = """
        <h2>Alpha</h2>\(section)
        <h2>Beta</h2>\(section)
        <h2>Gamma</h2>\(section)
        """
        let chapters = try ChapterSplitter.split(body: body, articleTitle: "Article")
        // The heading became the chapter title, so the body must not
        // re-emit the same <h2> (the template renders the title as <h1>).
        for chapter in chapters {
            #expect(!chapter.bodyHTML.contains("<h2>\(chapter.title)</h2>"))
        }
    }

    @Test func fallsBackToParagraphSplitWithoutHeadings() throws {
        // 150 paragraphs, no h2 headings, > 15k chars
        let body = String(repeating: Self.para, count: 150)
        let chapters = try ChapterSplitter.split(body: body, articleTitle: "Long Article")
        #expect(chapters.count == 3) // 150 / 50 per chapter
        #expect(chapters[0].title == "Long Article")
        #expect(chapters[1].title.contains("Part 2"))
        #expect(chapters[2].title.contains("Part 3"))
    }

    @Test func entityHeavyContentDoesNotOvercountLength() throws {
        // ~200 chars of visible text with entities; the old regex-based
        // length check operated on markup. DOM text must stay below the
        // split threshold and yield a single chapter.
        let body = String(repeating: "<p>Fish &amp; Chips &lt;3</p>", count: 20)
        let chapters = try ChapterSplitter.split(body: body, articleTitle: "T")
        #expect(chapters.count == 1)
    }
}
