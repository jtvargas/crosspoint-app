import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import SwiftSoup
import Testing
import ZIPFoundation
@testable import SendToX4

struct FileImportServiceTests {
    @Test func textPDFPreservesMetadataPageOrderAndEscapesFlowingText() async throws {
        let pdf = try makePDF(pages: [
            ["First <page> & friends", "continues on this line."],
            ["Second page's final paragraph."]
        ], title: "Book & <Title>", author: "Writer & Co")
        let fixture = try temporaryFile(pdf, named: "Original.pdf")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let updates = ProgressLog()
        let result = try await FileImportService.prepare(url: fixture.url) { completed, total in
            await updates.append(completed, total)
        }

        #expect(result.title == "Book & <Title>")
        #expect(result.author == "Writer & Co")
        #expect(result.filename == "Original.epub")
        let first = try chapter("OEBPS/chapter-0.xhtml", in: result.epubData)
        let second = try chapter("OEBPS/chapter-1.xhtml", in: result.epubData)
        #expect(try first.select("p").array().map { try $0.text() } == [
            "First <page> & friends continues on this line."
        ])
        #expect(try second.select("p").text() == "Second page's final paragraph.")
        let opfData = try extract("OEBPS/content.opf", from: result.epubData)
        #expect(XMLParser(data: opfData).parse())
        let opf = try SwiftSoup.parse(String(decoding: opfData, as: UTF8.self))
        #expect(try opf.select("spine itemref").array().map { try $0.attr("idref") } == ["chapter-0", "chapter-1"])
        let metadata = String(decoding: opfData, as: UTF8.self)
        #expect(metadata.contains("Book &amp; &lt;Title&gt;"))
        #expect(metadata.contains("Writer &amp; Co"))
        #expect(await updates.values == [
            ProgressUpdate(completed: 0, total: 2),
            ProgressUpdate(completed: 1, total: 2),
            ProgressUpdate(completed: 2, total: 2)
        ])
        #expect(try Data(contentsOf: fixture.url) == pdf)
    }

    @Test func mixedPDFRendersCroppedRotatedPageAtDoubleX4Width() async throws {
        let document = try #require(PDFDocument(data: makePDF(pages: [["Before scan"], nil, ["After scan"]])))
        let scan = try #require(document.page(at: 1))
        scan.setBounds(CGRect(x: 50, y: 100, width: 200, height: 400), for: .cropBox)
        scan.rotation = 90
        let fixture = try temporaryFile(try #require(document.dataRepresentation()), named: "Mixed.PDF")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let result = try await FileImportService.prepare(url: fixture.url) { _, _ in }

        #expect(result.title == "Mixed")
        #expect(result.author == "")
        #expect(try chapter("OEBPS/chapter-0.xhtml", in: result.epubData).select("p").text() == "Before scan")
        #expect(try chapter("OEBPS/chapter-2.xhtml", in: result.epubData).select("p").text() == "After scan")
        let middle = try chapter("OEBPS/chapter-1.xhtml", in: result.epubData)
        let imagePath = try #require(middle.select("img").first()).attr("src")
        let imageData = try extract("OEBPS/" + imagePath, from: result.epubData)
        let source = try #require(CGImageSourceCreateWithData(imageData as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == Int(DeviceSpecification.x4.resolution.width * 2))
        #expect(image.height == 480)
        let colors = try pixelCounts(image)
        #expect(colors.red > 1_000, "The scanned-page content must survive rendering")
        #expect(colors.white > 100_000, "Transparent page regions must flatten to white")
        #expect(colors.blue == 0, "Content outside the crop box must not appear")
    }

    @Test func blankPDFPageIsRetainedAsWhiteImage() async throws {
        let fixture = try temporaryFile(makePDF(pages: [[]]), named: "Blank.pdf")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let result = try await FileImportService.prepare(url: fixture.url) { _, _ in }
        let body = try chapter("OEBPS/content.xhtml", in: result.epubData)
        let path = try #require(body.select("img").first()).attr("src")
        let source = try #require(CGImageSourceCreateWithData(try extract("OEBPS/" + path, from: result.epubData) as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let colors = try pixelCounts(image)
        #expect(colors.white == image.width * image.height)
    }

    @Test func excessivelyTallPDFPageFailsWithoutAllocatingUnboundedBitmap() async throws {
        let document = try #require(PDFDocument(data: makePDF(pages: [[]])))
        let page = try #require(document.page(at: 0))
        page.setBounds(CGRect(x: 0, y: 0, width: 1, height: 10_000), for: .mediaBox)
        page.setBounds(CGRect(x: 0, y: 0, width: 1, height: 10_000), for: .cropBox)
        let fixture = try temporaryFile(try #require(document.dataRepresentation()), named: "Tall.pdf")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await #expect(throws: FileImportError.pageFailed(1)) {
            try await FileImportService.prepare(url: fixture.url) { _, _ in }
        }
    }

    @Test func lockedPDFHasSpecificError() async throws {
        let document = try #require(PDFDocument(data: makePDF(pages: [["Secret"]])))
        let encrypted = try #require(document.dataRepresentation(options: [
            PDFDocumentWriteOption.ownerPasswordOption: "owner-secret",
            PDFDocumentWriteOption.userPasswordOption: "reader-secret"
        ]))
        let fixture = try temporaryFile(encrypted, named: "Locked.pdf")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await #expect(throws: FileImportError.lockedPDF) {
            try await FileImportService.prepare(url: fixture.url) { _, _ in }
        }
    }

    @Test(arguments: ["pdf", "epub"])
    func garbageFilesHaveTypedErrors(fileExtension: String) async throws {
        let fixture = try temporaryFile(Data("not a document".utf8), named: "Bad." + fileExtension)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let expected: FileImportError = fileExtension == "pdf" ? .invalidPDF : .invalidEPUB
        await #expect(throws: expected) {
            try await FileImportService.prepare(url: fixture.url) { _, _ in }
        }
    }

    @Test(arguments: ["application/epub+xml", "application/epub+zip\n", ""])
    func rejectsZIPWithIncorrectMimetype(mimetype: String) async throws {
        let fixture = try temporaryFile(makeZIP(mimetype: mimetype), named: "Bad.epub")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await #expect(throws: FileImportError.invalidEPUB) {
            try await FileImportService.prepare(url: fixture.url) { _, _ in }
        }
    }

    @Test func rejectsZIPWithoutMimetype() async throws {
        let fixture = try temporaryFile(makeZIP(mimetype: nil), named: "Bad.epub")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        await #expect(throws: FileImportError.invalidEPUB) {
            try await FileImportService.prepare(url: fixture.url) { _, _ in }
        }
    }

    @Test func acceptedEPUBIsReturnedByteForByteWithoutRewriting() async throws {
        let epub = try EPUBBuilder.build(
            body: "<p>Original body</p>",
            metadata: EPUBBuilder.Metadata(title: "Embedded title", author: "Author", language: "en",
                                           sourceURL: URL(fileURLWithPath: "/book"), description: "")
        )
        let fixture = try temporaryFile(epub, named: "Selected & Book.EPUB")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let result = try await FileImportService.prepare(url: fixture.url) { _, _ in }
        #expect(result.epubData == epub)
        #expect(result.title == "Selected & Book")
        #expect(result.filename == "Selected & Book.EPUB")
        #expect(result.author == "")
        #expect(try Data(contentsOf: fixture.url) == epub)
    }

    @Test func cancellationBetweenPagesIsNotReportedAsImportFailure() async throws {
        let fixture = try temporaryFile(makePDF(pages: [["First"], ["Second"]]), named: "Cancel.pdf")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let task = Task {
            try await FileImportService.prepare(url: fixture.url) { completed, _ in
                if completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func temporaryFile(_ data: Data, named name: String) throws -> (url: URL, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return (url, directory)
    }

    /// nil pages draw a scan-like graphic; empty arrays create genuinely blank pages.
    private func makePDF(pages: [[String]?], title: String? = nil, author: String? = nil) throws -> Data {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
        var metadata: [CFString: Any] = [:]
        if let title { metadata[kCGPDFContextTitle] = title }
        if let author { metadata[kCGPDFContextAuthor] = author }
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, metadata as CFDictionary))
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        for lines in pages {
            context.beginPDFPage(nil)
            if let lines {
                for (index, text) in lines.enumerated() {
                    let string = NSAttributedString(string: text, attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font
                    ])
                    context.textPosition = CGPoint(x: 40, y: 700 - index * 24)
                    CTLineDraw(CTLineCreateWithAttributedString(string), context)
                }
            } else {
                context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                context.fill(CGRect(x: 70, y: 140, width: 80, height: 100))
                context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
                context.fill(CGRect(x: 350, y: 550, width: 150, height: 150))
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private func makeZIP(mimetype: String?) throws -> Data {
        let archive = try #require(Archive(accessMode: .create))
        let bytes = Data((mimetype ?? "other entry").utf8)
        try archive.addEntry(with: mimetype == nil ? "other" : "mimetype", type: .file,
                             uncompressedSize: UInt32(bytes.count), compressionMethod: .none) { position, size in
            bytes.subdata(in: position..<(position + size))
        }
        return try #require(archive.data)
    }

    private func extract(_ path: String, from data: Data) throws -> Data {
        let archive = try #require(Archive(data: data, accessMode: .read))
        let entry = try #require(archive[path])
        var result = Data()
        _ = try archive.extract(entry) { result.append($0) }
        return result
    }

    private func chapter(_ path: String, in data: Data) throws -> Document {
        let bytes = try extract(path, from: data)
        #expect(XMLParser(data: bytes).parse(), "Imported chapter must be well-formed XHTML")
        return try SwiftSoup.parse(String(decoding: bytes, as: UTF8.self))
    }

    private func pixelCounts(_ image: CGImage) throws -> (red: Int, white: Int, blue: Int) {
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var red = 0, white = 0, blue = 0
        for offset in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            let r = bytes[offset], g = bytes[offset + 1], b = bytes[offset + 2]
            if r > 200 && g < 50 && b < 50 { red += 1 }
            if r > 245 && g > 245 && b > 245 { white += 1 }
            if b > 200 && r < 50 && g < 50 { blue += 1 }
        }
        return (red, white, blue)
    }
}

private nonisolated struct ProgressUpdate: Sendable, Equatable {
    let completed: Int
    let total: Int
}

private actor ProgressLog {
    var values: [ProgressUpdate] = []

    func append(_ completed: Int, _ total: Int) {
        values.append(ProgressUpdate(completed: completed, total: total))
    }
}
