import Foundation

/// Static EPUB 2.0 template strings for building EPUB documents.
/// All templates use string interpolation for maximum performance.
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
    
    /// OEBPS/content.opf — OPF 2.0 package document.
    static func contentOPF(
        uuid: String,
        title: String,
        author: String,
        language: String,
        date: String,
        publisher: String,
        description: String
    ) -> String {
"""
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:identifier id="BookId" opf:scheme="uuid">\(uuid)</dc:identifier>
    <dc:title>\(title)</dc:title>
    <dc:creator opf:role="aut">\(author)</dc:creator>
    <dc:language>\(language)</dc:language>
    <dc:date>\(date)</dc:date>
    <dc:publisher>\(publisher)</dc:publisher>
    <dc:description>\(description)</dc:description>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="content"/>
  </spine>
</package>
"""
    }
    
    /// OEBPS/toc.ncx — NCX table of contents.
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
    <text>\(title)</text>
  </docTitle>
  <navMap>
    <navPoint id="navpoint-1" playOrder="1">
      <navLabel>
        <text>\(title)</text>
      </navLabel>
      <content src="content.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
"""
    }
    
    /// OEBPS/content.xhtml — the article content wrapped in XHTML 1.1.
    static func contentXHTML(title: String, body: String, language: String) -> String {
"""
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="\(language)">
  <head>
    <meta http-equiv="Content-Type" content="application/xhtml+xml; charset=utf-8"/>
    <title>\(title)</title>
    <style type="text/css">
      body { margin: 1em; font-family: serif; line-height: 1.6; }
      h1 { font-size: 1.4em; margin-bottom: 0.5em; }
      h2 { font-size: 1.2em; margin-top: 1em; }
      p { margin: 0.5em 0; text-indent: 0; }
      blockquote { margin: 1em 2em; font-style: italic; }
      pre, code { font-family: monospace; font-size: 0.9em; }
    </style>
  </head>
  <body>
    <h1>\(title)</h1>
    \(body)
  </body>
</html>
"""
    }
}
