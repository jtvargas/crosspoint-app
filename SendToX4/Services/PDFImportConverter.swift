import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Keeps PDFKit objects local to one background conversion, never crossing actors.
nonisolated enum PDFImportConverter {
    @concurrent
    static func convert(
        url: URL,
        fallbackTitle: String,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> PreparedImport {
        try Task.checkCancellation()
        guard let document = PDFDocument(url: url) else { throw FileImportError.invalidPDF }
        guard !document.isLocked else { throw FileImportError.lockedPDF }
        let count = document.pageCount
        guard count > 0 else { throw FileImportError.emptyPDF }

        let attributes = document.documentAttributes
        let title = metadataString(attributes?[PDFDocumentAttribute.titleAttribute]) ?? fallbackTitle
        let author = metadataString(attributes?[PDFDocumentAttribute.authorAttribute]) ?? ""
        var chapters: [Chapter] = []
        chapters.reserveCapacity(count)
        var images: [EPUBImage] = []
        await progress(0, count)

        for index in 0..<count {
            try Task.checkCancellation()
            let chapter = try autoreleasepool {
                guard let page = document.page(at: index) else {
                    throw FileImportError.pageFailed(index + 1)
                }
                let chapterTitle = "\(title) — \(index + 1)"
                let text = xmlCompatible(page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let body: String
                if text.isEmpty {
                    let image = try render(page, index: index)
                    body = "<p><img src=\"\(image.path)\" alt=\"\(chapterTitle.xmlEscaped)\"/></p>"
                    images.append(image)
                } else {
                    body = flowingBody(text)
                }
                return Chapter(index: index, title: chapterTitle, bodyHTML: body)
            }
            chapters.append(chapter)
            await progress(index + 1, count)
        }

        try Task.checkCancellation()
        let data: Data
        do {
            data = try EPUBBuilder.build(
                chapters: chapters,
                metadata: EPUBBuilder.Metadata(
                    title: title,
                    author: author,
                    language: "und",
                    sourceURL: url,
                    description: ""
                ),
                images: images
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FileImportError.buildFailed
        }
        try Task.checkCancellation()
        return PreparedImport(
            epubData: data, title: title, author: author, filename: fallbackTitle + ".epub"
        )
    }

    private static func metadataString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = xmlCompatible(string).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// PDFKit's single newlines are usually visual line wraps, not paragraphs.
    /// Retain explicit blank-line/paragraph breaks while allowing text to reflow.
    private static func flowingBody(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
        var paragraphs: [String] = []
        var lines: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !lines.isEmpty {
                    paragraphs.append("<p>\(lines.joined(separator: " ").xmlEscaped)</p>")
                    lines.removeAll(keepingCapacity: true)
                }
            } else {
                lines.append(trimmed)
            }
        }
        if !lines.isEmpty {
            paragraphs.append("<p>\(lines.joined(separator: " ").xmlEscaped)</p>")
        }
        return paragraphs.joined(separator: "\n")
    }

    /// XML escaping handles markup; PDF strings can additionally contain controls
    /// that XML 1.0 cannot represent, even as numeric character references.
    private static func xmlCompatible(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x9, 0xA, 0xD, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                return true
            default:
                return false
            }
        })
    }

    private static func render(_ page: PDFPage, index: Int) throws -> EPUBImage {
        guard let reference = page.pageRef else { throw FileImportError.pageFailed(index + 1) }
        let crop = reference.getBoxRect(.cropBox)
        let media = reference.getBoxRect(.mediaBox)
        guard validBounds(crop), validBounds(media) else {
            throw FileImportError.pageFailed(index + 1)
        }
        let bounds = crop.intersection(media)
        guard validBounds(bounds), reference.rotationAngle % 90 == 0 else {
            throw FileImportError.pageFailed(index + 1)
        }
        let rotated = reference.rotationAngle % 180 != 0
        let displayWidth = rotated ? bounds.height : bounds.width
        let displayHeight = rotated ? bounds.width : bounds.height
        let width = Int(DeviceSpecification.x4.resolution.width * 2)
        let scaledHeight = ceil(CGFloat(width) * displayHeight / displayWidth)
        // Bound bitmap allocation before converting potentially hostile geometry to Int.
        guard scaledHeight.isFinite, scaledHeight >= 1, scaledHeight <= 16_384 else {
            throw FileImportError.pageFailed(index + 1)
        }
        let height = Int(scaledHeight)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw FileImportError.pageFailed(index + 1) }

        let target = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(target)
        context.interpolationQuality = .high
        context.concatenate(reference.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
        context.clip(to: bounds)
        context.drawPDFPage(reference)
        guard let image = context.makeImage() else { throw FileImportError.pageFailed(index + 1) }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw FileImportError.pageFailed(index + 1)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FileImportError.pageFailed(index + 1) }
        return EPUBImage(
            path: "images/page-\(index + 1).jpg", data: encoded as Data,
            mediaType: "image/jpeg", width: width, height: height
        )
    }

    private static func validBounds(_ bounds: CGRect) -> Bool {
        !bounds.isNull && !bounds.isInfinite
            && bounds.origin.x.isFinite && bounds.origin.y.isFinite
            && bounds.width.isFinite && bounds.height.isFinite
            && bounds.width > 0 && bounds.height > 0
            && abs(bounds.origin.x) <= 1_000_000 && abs(bounds.origin.y) <= 1_000_000
            && bounds.width <= 1_000_000 && bounds.height <= 1_000_000
    }
}
