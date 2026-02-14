import Foundation

extension String {
    /// Escapes special XML characters for safe inclusion in XHTML content.
    var xmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    /// Extracts the domain from a URL string, stripping "www." prefix.
    var extractedDomain: String {
        guard let url = URL(string: self),
              let host = url.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    
    /// Trims whitespace and collapses multiple spaces/newlines into single spaces.
    var condensed: String {
        self.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    /// Truncates the string to a maximum length, appending "..." if truncated.
    func truncated(to maxLength: Int) -> String {
        if self.count <= maxLength { return self }
        return String(self.prefix(maxLength - 3)) + "..."
    }
}
