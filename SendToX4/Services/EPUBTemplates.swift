import Foundation

/// Static EPUB 2.0 template strings for building EPUB documents.
/// All templates use string interpolation for maximum performance.
///
/// Escaping contract: every template escapes its own text parameters
/// (title, author, publisher, description, chapter titles). Callers pass
/// RAW strings — never pre-escaped — so values can't be double-escaped.
/// `body` parameters are already-valid XHTML and are interpolated verbatim.
enum EPUBTemplates {

    /// The mimetype file content (must be exactly this, uncompressed, first entry in ZIP).
    static let mimetype = "application/epub+zip"

    /// META-INF/container.xml — points to the OPF file.
    static let containerXML = """
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

    // MARK: - Image Manifest Fragments

    /// Manifest `<item>` lines for embedded images. The cover image gets the
    /// conventional `cover-image` id.
    static func imageManifestItems(for images: [EPUBImage]) -> String {
        guard !images.isEmpty else { return "" }
        return "\n" + images.enumerated().map { index, image in
            let id = image.isCover ? "cover-image" : "img-\(index)"
            return "    <item id=\"\(id)\" href=\"\(image.path)\" media-type=\"\(image.mediaType)\"/>"
        }.joined(separator: "\n")
    }

    /// EPUB 2.0 cover declaration (`<meta name="cover">`), or empty when no
    /// image is marked as cover.
    static func coverMeta(for images: [EPUBImage]) -> String {
        guard images.contains(where: { $0.isCover }) else { return "" }
        return "\n    <meta name=\"cover\" content=\"cover-image\"/>"
    }

    // MARK: - Single-Chapter Templates (backward compatible)

    /// OEBPS/content.opf — OPF 2.0 package document (single chapter).
    static func contentOPF(
        uuid: String,
        title: String,
        author: String,
        language: String,
        date: String,
        publisher: String,
        description: String,
        imageItems: String = "",
        coverMeta: String = ""
    ) -> String {
"""
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier id="BookId" opf:scheme="uuid">\(uuid)</dc:identifier>
    <dc:title>\(title.xmlEscaped)</dc:title>
    <dc:creator opf:role="aut">\(author.xmlEscaped)</dc:creator>
    <dc:language>\(language)</dc:language>
    <dc:date>\(date)</dc:date>
    <dc:publisher>\(publisher.xmlEscaped)</dc:publisher>
    <dc:description>\(description.xmlEscaped)</dc:description>\(coverMeta)
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>\(imageItems)
  </manifest>
  <spine toc="ncx">
    <itemref idref="content"/>
  </spine>
</package>
"""
    }

    /// OEBPS/toc.ncx — NCX table of contents (single chapter).
    static func tocNCX(uuid: String, title: String) -> String {
"""
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
  <head>
    <meta name="dtb:uid" content="\(uuid)"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>\(title.xmlEscaped)</text>
  </docTitle>
  <navMap>
    <navPoint id="navpoint-1" playOrder="1">
      <navLabel>
        <text>\(title.xmlEscaped)</text>
      </navLabel>
      <content src="content.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
"""
    }

    /// OEBPS/content.xhtml — the article content wrapped in XHTML 1.1 (single chapter).
    static func contentXHTML(title: String, body: String, language: String) -> String {
"""
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="\(language)">
  <head>
    <meta http-equiv="Content-Type" content="application/xhtml+xml; charset=utf-8"/>
    <title>\(title.xmlEscaped)</title>
    <style type="text/css">
      body { margin: 1em; font-family: serif; line-height: 1.6; }
      h1 { font-size: 1.4em; margin-bottom: 0.5em; }
      h2 { font-size: 1.2em; margin-top: 1em; }
      p { margin: 0.5em 0; text-indent: 0; }
      blockquote { margin: 1em 2em; font-style: italic; }
      pre, code { font-family: monospace; font-size: 0.9em; }
      img { max-width: 100%; height: auto; }
      figure { margin: 1em 0; text-align: center; }
      figcaption { font-size: 0.85em; font-style: italic; }
    </style>
  </head>
  <body>
    <h1>\(title.xmlEscaped)</h1>
    \(body)
  </body>
</html>
"""
    }

    // MARK: - Multi-Chapter Templates

    /// OEBPS/content.opf — OPF 2.0 package document with multiple chapters.
    static func contentOPF(
        uuid: String,
        title: String,
        author: String,
        language: String,
        date: String,
        publisher: String,
        description: String,
        chapterCount: Int,
        imageItems: String = "",
        coverMeta: String = ""
    ) -> String {
        let manifestItems = (0..<chapterCount).map { i in
            "    <item id=\"chapter-\(i)\" href=\"chapter-\(i).xhtml\" media-type=\"application/xhtml+xml\"/>"
        }.joined(separator: "\n")

        let spineItems = (0..<chapterCount).map { i in
            "    <itemref idref=\"chapter-\(i)\"/>"
        }.joined(separator: "\n")

        return """
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier id="BookId" opf:scheme="uuid">\(uuid)</dc:identifier>
    <dc:title>\(title.xmlEscaped)</dc:title>
    <dc:creator opf:role="aut">\(author.xmlEscaped)</dc:creator>
    <dc:language>\(language)</dc:language>
    <dc:date>\(date)</dc:date>
    <dc:publisher>\(publisher.xmlEscaped)</dc:publisher>
    <dc:description>\(description.xmlEscaped)</dc:description>\(coverMeta)
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
\(manifestItems)\(imageItems)
  </manifest>
  <spine toc="ncx">
\(spineItems)
  </spine>
</package>
"""
    }

    /// OEBPS/toc.ncx — NCX table of contents with multiple chapters.
    static func tocNCX(uuid: String, title: String, chapters: [Chapter]) -> String {
        let navPoints = chapters.enumerated().map { (i, chapter) in
            let playOrder = i + 1
            return """
    <navPoint id="navpoint-\(playOrder)" playOrder="\(playOrder)">
      <navLabel>
        <text>\(chapter.title.xmlEscaped)</text>
      </navLabel>
      <content src="chapter-\(chapter.index).xhtml"/>
    </navPoint>
"""
        }.joined(separator: "\n")

        return """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
  <head>
    <meta name="dtb:uid" content="\(uuid)"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>\(title.xmlEscaped)</text>
  </docTitle>
  <navMap>
\(navPoints)
  </navMap>
</ncx>
"""
    }

    /// OEBPS/chapter-N.xhtml — a single chapter wrapped in XHTML 1.1.
    static func chapterXHTML(title: String, body: String, language: String) -> String {
"""
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="\(language)">
  <head>
    <meta http-equiv="Content-Type" content="application/xhtml+xml; charset=utf-8"/>
    <title>\(title.xmlEscaped)</title>
    <style type="text/css">
      body { margin: 1em; font-family: serif; line-height: 1.6; }
      h1 { font-size: 1.4em; margin-bottom: 0.5em; }
      h2 { font-size: 1.2em; margin-top: 1em; }
      p { margin: 0.5em 0; text-indent: 0; }
      blockquote { margin: 1em 2em; font-style: italic; }
      pre, code { font-family: monospace; font-size: 0.9em; }
      img { max-width: 100%; height: auto; }
      figure { margin: 1em 0; text-align: center; }
      figcaption { font-size: 0.85em; font-style: italic; }
    </style>
  </head>
  <body>
    <h1>\(title.xmlEscaped)</h1>
    \(body)
  </body>
</html>
"""
    }
}
