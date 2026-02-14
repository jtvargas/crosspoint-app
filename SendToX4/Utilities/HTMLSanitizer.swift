import Foundation
import SwiftSoup

/// Sanitizes HTML content for safe inclusion in EPUB documents.
/// Strips scripts, styles, forms, media elements, images, and interactive content.
enum HTMLSanitizer {
    
    /// Elements to remove entirely (including their content).
    private static let removeWithContent: Set<String> = [
        "script", "style", "noscript", "iframe", "frame", "frameset",
        "object", "embed", "applet", "form", "input", "textarea",
        "select", "button", "video", "audio", "source", "canvas",
        "svg", "math", "template"
    ]
    
    /// Elements to remove but keep their children (unwrap).
    private static let unwrapElements: Set<String> = [
        "span", "font", "center", "div"
    ]
    
    /// Attributes to always remove (event handlers, styles, data attributes).
    private static let removeAttributes: [String] = [
        "style", "class", "id", "onclick", "onload", "onerror",
        "onmouseover", "onmouseout", "onfocus", "onblur",
        "data-.*", "aria-.*", "role"
    ]
    
    /// Sanitize raw HTML string for EPUB inclusion.
    /// Returns clean XHTML-compatible body content.
    static func sanitize(_ html: String) throws -> String {
        let doc = try SwiftSoup.parse(html)
        
        // Remove unwanted elements entirely
        for tag in removeWithContent {
            try doc.select(tag).remove()
        }
        
        // Remove images (text-only EPUB)
        try doc.select("img").remove()
        try doc.select("picture").remove()
        try doc.select("figure").remove()
        
        // Remove navigation and footer clutter
        try doc.select("nav").remove()
        try doc.select("footer").remove()
        try doc.select("aside").remove()
        try doc.select("header").remove()
        
        // Remove social/sharing widgets
        try doc.select("[class*=share]").remove()
        try doc.select("[class*=social]").remove()
        try doc.select("[class*=comment]").remove()
        try doc.select("[class*=related]").remove()
        try doc.select("[class*=sidebar]").remove()
        try doc.select("[class*=advertisement]").remove()
        try doc.select("[class*=ad-]").remove()
        try doc.select("[class*=popup]").remove()
        try doc.select("[id*=comment]").remove()
        try doc.select("[id*=sidebar]").remove()
        
        // Strip all attributes except href on anchors
        let allElements = try doc.select("*")
        for element in allElements {
            let attrs = element.getAttributes()
            guard let attrs = attrs else { continue }
            var keysToRemove: [String] = []
            for attr in attrs {
                let key = attr.getKey()
                if element.tagName() == "a" && key == "href" {
                    continue
                }
                keysToRemove.append(key)
            }
            for key in keysToRemove {
                try element.removeAttr(key)
            }
        }
        
        // Convert links to plain text (e-readers handle links poorly)
        let links = try doc.select("a")
        for link in links {
            try link.unwrap()
        }
        
        // Get body content
        guard let body = doc.body() else {
            return ""
        }
        
        return try body.html()
    }
    
    /// Converts HTML to valid XHTML by ensuring proper tag closure and escaping.
    static func toXHTML(_ html: String) throws -> String {
        let doc = try SwiftSoup.parse(html)
        doc.outputSettings()
            .syntax(syntax: OutputSettings.Syntax.xml)
            .escapeMode(Entities.EscapeMode.xhtml)
            .charset(String.Encoding.utf8)
        
        guard let body = doc.body() else { return "" }
        return try body.html()
    }
}
