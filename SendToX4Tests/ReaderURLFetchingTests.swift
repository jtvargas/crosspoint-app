import Foundation
import Testing
@testable import SendToX4

@MainActor
struct ReaderURLFetchingTests {
    private let shell = "<html><body><div id='__next'></div><script>hydrate()</script></body></html>"
    private let article = "<html><body><article>Article content.</article></body></html>"

    @Test func fetchesCanonicalPathBeforeWrapper() async throws {
        let input = try #require(URL(string: "https://example.com/reader/story"))
        var requests: [URL] = []
        let page = try await WebPageFetcher.fetch(url: input) { url in
            requests.append(url)
            return FetchedPage(html: url == input ? shell : article, finalURL: url, language: "fr")
        }
        #expect(requests.map(\.path) == ["/story"])
        #expect(page.finalURL.path == "/story")
        #expect(page.html == article)
        #expect(page.language == "fr")
    }

    @Test(arguments: [false, true])
    func fallsBackToReadableWrapper(onFailure: Bool) async throws {
        let input = try #require(URL(string: "https://example.com/reader/story"))
        var requests: [URL] = []
        let page = try await WebPageFetcher.fetch(url: input) { url in
            requests.append(url)
            if onFailure && url != input { throw FetchError.httpError(statusCode: 404) }
            return FetchedPage(html: url == input ? article : shell, finalURL: url, language: "en")
        }
        #expect(requests.map(\.path) == ["/story", "/reader/story"])
        #expect(page.finalURL == input)
        #expect(page.html == article)
    }

    @Test(arguments: [false, true])
    func honorsDiscoveredCanonical(fromWrapper: Bool) async throws {
        let input = try #require(URL(string: "https://example.com/reader/story"))
        let canonical = try #require(URL(string: "https://publisher.example/published"))
        let linked = "<html><head><link rel='canonical' href='\(canonical)'></head><body>Less preferred content.</body></html>"
        var requests: [URL] = []
        let page = try await WebPageFetcher.fetch(url: input) { url in
            requests.append(url)
            let html = url == canonical ? article : (fromWrapper && url != input ? shell : linked)
            return FetchedPage(html: html, finalURL: url, language: "en")
        }
        #expect(requests.map(\.path) == (fromWrapper ? ["/story", "/reader/story", "/published"] : ["/story", "/published"]))
        #expect(page.finalURL == canonical)
        #expect(page.html == article)
    }

    @Test func emptyCanonicalAndWrapperRemainAvailableToRenderer() async throws {
        let input = try #require(URL(string: "https://example.com/reader/story"))
        var requests: [URL] = []
        let page = try await WebPageFetcher.fetch(url: input) { url in
            requests.append(url)
            return FetchedPage(html: shell, finalURL: url, language: "en")
        }
        #expect(requests.map(\.path) == ["/story", "/reader/story"])
        #expect(page.finalURL == input)
        #expect(page.html == shell)
    }

    @Test func failedCanonicalLinkPreservesReadableCandidate() async throws {
        let input = try #require(URL(string: "https://example.com/reader/story"))
        let linked = "<link rel='canonical' href='https://example.com/missing'><article>Readable article.</article>"
        let page = try await WebPageFetcher.fetch(url: input) { url in
            if url.path == "/missing" { throw FetchError.httpError(statusCode: 404) }
            return FetchedPage(html: linked, finalURL: url, language: "en")
        }
        #expect(page.finalURL.path == "/story")
        #expect(page.html == linked)
    }

    @Test func doesNotRetryCanonicalCycles() async throws {
        let input = try #require(URL(string: "https://example.com/reader/story"))
        var requests: [URL] = []
        let page = try await WebPageFetcher.fetch(url: input) { url in
            requests.append(url)
            let html = "<link rel='canonical' href='https://example.com/story'>\(shell)"
            return FetchedPage(html: html, finalURL: url, language: "en")
        }
        #expect(requests.map(\.path) == ["/story", "/reader/story"])
        #expect(page.finalURL == input)
    }

    @Test func cancellationDoesNotFetchWrapper() async throws {
        let input = try #require(URL(string: "https://example.com/reader/story"))
        var requests: [URL] = []
        await #expect(throws: CancellationError.self) {
            try await WebPageFetcher.fetch(url: input) { url in
                requests.append(url)
                throw CancellationError()
            }
        }
        #expect(requests.map(\.path) == ["/story"])
    }

    @Test func nonReaderStillFetchesOnlyInput() async throws {
        let input = try #require(URL(string: "https://example.com/story"))
        var requests: [URL] = []
        let page = try await WebPageFetcher.fetch(url: input) { url in
            requests.append(url)
            return FetchedPage(html: shell, finalURL: url, language: "en")
        }
        #expect(requests == [input])
        #expect(page.finalURL == input)
        #expect(page.html == shell)
    }
}
