import Foundation
import ZIPFoundation

nonisolated struct PreparedImport: Sendable {
    let epubData: Data
    let title: String
    let author: String
    let filename: String
}

nonisolated enum FileImportError: Error, Equatable {
    case unsupportedType
    case unreadableFile
    case invalidEPUB
    case invalidPDF
    case lockedPDF
    case emptyPDF
    case pageFailed(Int)
    case buildFailed
}

/// Imports only a sandbox-owned copy; external file access never outlives copying.
nonisolated enum FileImportService {
    @concurrent
    static func prepare(
        url: URL,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> PreparedImport {
        try Task.checkCancellation()
        guard url.isFileURL else { throw FileImportError.unreadableFile }
        let fileExtension = url.pathExtension.lowercased()
        guard fileExtension == "epub" || fileExtension == "pdf" else {
            throw FileImportError.unsupportedType
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent(url.lastPathComponent)
        try copyToSandbox(url, destination: copy, directory: directory)
        try Task.checkCancellation()

        let title = url.deletingPathExtension().lastPathComponent
        if fileExtension == "pdf" {
            return try await PDFImportConverter.convert(
                url: copy, fallbackTitle: title, progress: progress
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: copy)
        } catch {
            throw FileImportError.unreadableFile
        }
        try Task.checkCancellation()
        try validateEPUB(data)
        return PreparedImport(epubData: data, title: title, author: "", filename: url.lastPathComponent)
    }

    private static func copyToSandbox(_ source: URL, destination: URL, directory: URL) throws {
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.stopAccessingSecurityScopedResource() }
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw FileImportError.unreadableFile
        }
    }

    private static func validateEPUB(_ data: Data) throws {
        let expected = Data(EPUBTemplates.mimetype.utf8)
        guard let archive = Archive(data: data, accessMode: .read),
              let entry = archive["mimetype"], entry.type == .file,
              entry.uncompressedSize == expected.count else {
            throw FileImportError.invalidEPUB
        }
        do {
            var content = Data()
            let checksum = try archive.extract(entry) { chunk in
                try Task.checkCancellation()
                guard content.count + chunk.count <= expected.count else {
                    throw FileImportError.invalidEPUB
                }
                content.append(chunk)
            }
            guard content == expected, checksum == entry.checksum else {
                throw FileImportError.invalidEPUB
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FileImportError.invalidEPUB
        }
    }
}
