import Foundation
import ZIPFoundation

/// One entry in the EPUB's reading order.
struct SpineItem: Identifiable {
    /// Manifest item id.
    let id: String
    /// Zip path relative to the package root (e.g. "OEBPS/chapter-0.xhtml").
    let path: String
    /// Display title (from the NCX, falling back to "Part N").
    let title: String
    /// Anchor id used in the combined reader document ("chapter-N").
    let anchor: String
}

/// Read-only view over an EPUB file for the in-app reader.
///
/// Opens the archive once and serves resources lazily — nothing is unzipped
/// to disk. `combinedHTML()` concatenates the spine into a single
/// continuous-scroll document with `<section id="chapter-N">` anchors,
/// which `EPUBSchemeHandler` serves to the reader WKWebView.
final class EPUBDocument {

    enum EPUBDocumentError: Error {
        case cannotOpenArchive
        case missingOPF
    }

    private let archive: Archive

    /// Book title from the OPF metadata.
    let title: String

    /// Reading order.
    let spine: [SpineItem]

    /// Directory prefix of the OPF (e.g. "OEBPS"), used to resolve hrefs.
    private let opfDirectory: String

    // MARK: - Init

    init(fileURL: URL) throws {
        guard let archive = Archive(url: fileURL, accessMode: .read) else {
            throw EPUBDocumentError.cannotOpenArchive
        }
        self.archive = archive

        // Locate the OPF via container.xml
        guard let containerData = Self.extract(path: "META-INF/container.xml", from: archive),
              let container = String(data: containerData, encoding: .utf8),
              let opfPath = Self.firstMatch("full-path\\s*=\\s*\"([^\"]+)\"", in: container),
              let opfData = Self.extract(path: opfPath, from: archive),
              let opf = String(data: opfData, encoding: .utf8) else {
            throw EPUBDocumentError.missingOPF
        }

        let opfDir = opfPath.contains("/")
            ? String(opfPath[..<opfPath.range(of: "/", options: .backwards)!.lowerBound])
            : ""
        self.opfDirectory = opfDir

        self.title = Self.firstMatch("<dc:title[^>]*>([^<]*)</dc:title>", in: opf)?
            .xmlUnescapedForReader ?? "Untitled"

        // Manifest: id -> href
        var manifest: [String: String] = [:]
        for tag in Self.allMatches("<item\\b[^>]*>", in: opf) {
            guard let id = Self.firstMatch("id\\s*=\\s*\"([^\"]+)\"", in: tag),
                  let href = Self.firstMatch("href\\s*=\\s*\"([^\"]+)\"", in: tag) else {
                continue
            }
            manifest[id] = href
        }

        // NCX titles keyed by content src (for chapter labels)
        var ncxTitles: [String: String] = [:]
        if let ncxHref = manifest.first(where: { $0.value.hasSuffix(".ncx") })?.value,
           let ncxData = Self.extract(path: Self.join(opfDir, ncxHref), from: archive),
           let ncx = String(data: ncxData, encoding: .utf8) {
            for navPoint in Self.allMatches(
                "<navPoint[\\s\\S]*?</navPoint>", in: ncx
            ) {
                guard let label = Self.firstMatch("<text>([^<]*)</text>", in: navPoint),
                      let src = Self.firstMatch("<content\\s+src\\s*=\\s*\"([^\"#]+)", in: navPoint) else {
                    continue
                }
                ncxTitles[src] = label.xmlUnescapedForReader
            }
        }

        // Spine order
        var items: [SpineItem] = []
        for (index, itemref) in Self.allMatches("<itemref\\b[^>]*>", in: opf).enumerated() {
            guard let idref = Self.firstMatch("idref\\s*=\\s*\"([^\"]+)\"", in: itemref),
                  let href = manifest[idref] else {
                continue
            }
            let chapterTitle = ncxTitles[href] ?? "Part \(index + 1)"
            items.append(SpineItem(
                id: idref,
                path: Self.join(opfDir, href),
                title: chapterTitle,
                anchor: "chapter-\(index)"
            ))
        }
        self.spine = items
    }

    // MARK: - Resources

    /// Raw bytes of a package resource (path relative to the zip root).
    func resource(at path: String) -> Data? {
        Self.extract(path: path, from: archive)
    }

    /// Resolve a reader-relative href (e.g. "images/img-0.jpg") against the
    /// OPF directory into a zip path.
    func packagePath(forReaderHref href: String) -> String {
        Self.join(opfDirectory, href)
    }

    /// Single continuous-scroll HTML document for the reader: all spine
    /// chapters concatenated inside `<section>` anchors with the reader CSS
    /// and progress-reporting script injected.
    func combinedHTML() -> String {
        var sections = ""
        for item in spine {
            guard let data = resource(at: item.path),
                  let xhtml = String(data: data, encoding: .utf8) else {
                continue
            }
            let body = Self.bodyContent(of: xhtml)
            sections += "<section id=\"\(item.anchor)\">\n\(body)\n</section>\n"
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/>
        <style>\(ReaderStyle.css)</style>
        </head>
        <body>
        \(sections)
        <script>\(ReaderStyle.progressScript)</script>
        </body>
        </html>
        """
    }

    /// Extracts the inner body content of a chapter XHTML document.
    /// Our own builder emits plain `<body>...</body>`, so fast string
    /// slicing is sufficient; falls back to the whole document body-less.
    private static func bodyContent(of xhtml: String) -> String {
        guard let bodyOpen = xhtml.range(of: "<body", options: .caseInsensitive),
              let openEnd = xhtml[bodyOpen.upperBound...].range(of: ">"),
              let bodyClose = xhtml.range(of: "</body>", options: [.caseInsensitive, .backwards]) else {
            return xhtml
        }
        guard openEnd.upperBound <= bodyClose.lowerBound else { return xhtml }
        return String(xhtml[openEnd.upperBound..<bodyClose.lowerBound])
    }

    // MARK: - Zip / Regex Helpers

    private static func extract(path: String, from archive: Archive) -> Data? {
        guard let entry = archive[path] else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
        } catch {
            return nil
        }
        return data
    }

    private static func join(_ directory: String, _ href: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        var components = directory.isEmpty ? [] : directory.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/").map(String.init) {
            switch part {
            case "", ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(part)
            }
        }
        return components.joined(separator: "/")
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(
            in: text, range: NSRange(location: 0, length: nsText.length)
        ) else {
            return nil
        }
        let range = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        return nsText.substring(with: range)
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .map { nsText.substring(with: $0.range) }
    }
}

private extension String {
    /// Minimal XML entity decoding for display strings from OPF/NCX.
    var xmlUnescapedForReader: String {
        self.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
