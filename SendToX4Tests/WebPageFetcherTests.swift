import Foundation
import Testing
@testable import SendToX4

struct WebPageFetcherTests {

    // MARK: - Decoding

    @Test func decodesUTF8WithoutHeader() {
        let html = "<html><body>héllo wörld</body></html>"
        let data = Data(html.utf8)
        let decoded = WebPageFetcher.decode(data: data, headerCharset: nil)
        #expect(decoded == html)
    }

    @Test func honorsHeaderCharset() throws {
        let html = "<html><body>caf\u{E9}</body></html>"
        let data = try #require(html.data(using: .isoLatin1))
        let decoded = WebPageFetcher.decode(data: data, headerCharset: "iso-8859-1")
        #expect(decoded?.contains("café") == true)
    }

    @Test func sniffsMetaCharsetWhenHeaderMissing() throws {
        // Shift-JIS Japanese is not valid UTF-8, so decoding must rely on
        // the <meta charset> declaration inside the document itself.
        let html = "<html><head><meta charset=\"shift_jis\"></head><body>こんにちは世界</body></html>"
        let data = try #require(html.data(using: .shiftJIS))
        let decoded = WebPageFetcher.decode(data: data, headerCharset: nil)
        #expect(decoded?.contains("こんにちは世界") == true)
    }

    @Test func sniffsHTTPEquivCharset() throws {
        let html = "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=shift_jis\"></head><body>日本語のテキスト</body></html>"
        let data = try #require(html.data(using: .shiftJIS))
        let decoded = WebPageFetcher.decode(data: data, headerCharset: nil)
        #expect(decoded?.contains("日本語のテキスト") == true)
    }

    @Test func metaCharsetSniffFindsDeclaration() {
        let html = "<html><head><meta charset='GBK'></head></html>"
        let sniffed = WebPageFetcher.sniffMetaCharset(in: Data(html.utf8))
        #expect(sniffed == "gbk")
    }

    // MARK: - Language Extraction

    @Test func extractsLanguageFromHTMLTag() {
        let html = "<html lang=\"fr-CA\"><body>Bonjour</body></html>"
        #expect(WebPageFetcher.extractLanguage(fromHTMLTag: html) == "fr")
    }

    @Test func ignoresLangAttributesInBody() {
        // The old scan matched the FIRST lang=" anywhere; the html tag here
        // has no lang, so the result must be nil despite the body attribute.
        let html = "<html><body><div lang=\"de\">Hallo</div></body></html>"
        #expect(WebPageFetcher.extractLanguage(fromHTMLTag: html) == nil)
    }

    @Test func handlesSingleQuotedAndUnspacedAttributes() {
        let html = "<html class='x' lang='ja'><body></body></html>"
        #expect(WebPageFetcher.extractLanguage(fromHTMLTag: html) == "ja")
    }
}
