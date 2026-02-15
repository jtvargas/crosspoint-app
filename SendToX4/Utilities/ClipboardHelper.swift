import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform clipboard utility.
///
/// Uses `UIPasteboard` on iOS/iPadOS and `NSPasteboard` on macOS.
enum ClipboardHelper {

    /// Copy a string to the system clipboard.
    static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
