import Foundation

/// Persistent debug logger that writes timestamped entries to a file and keeps
/// a rolling in-memory buffer for the UI. Thread-safe via a serial dispatch queue.
///
/// Usage:
///   DebugLogger.log("Sending item 1/5", level: .info, category: .queue)
///   DebugLogger.log("Connection lost: \(error)", level: .error, category: .device)
@Observable
final class DebugLogger {

    // MARK: - Singleton

    static let shared = DebugLogger()

    // MARK: - Types

    enum Level: String, CaseIterable, Sendable {
        case info
        case warning
        case error

        var icon: String {
            switch self {
            case .info:    return "circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error:   return "xmark.circle.fill"
            }
        }
    }

    enum Category: String, CaseIterable, Sendable {
        case queue
        case conversion
        case device
        case rss
        case general

        var label: String {
            switch self {
            case .queue:      return "Queue"
            case .conversion: return "Conversion"
            case .device:     return "Device"
            case .rss:        return "RSS"
            case .general:    return "General"
            }
        }
    }

    struct Entry: Identifiable, Sendable {
        let id: UUID
        let timestamp: Date
        let level: Level
        let category: Category
        let message: String

        /// Formatted line for file output.
        var fileLine: String {
            let ts = Entry.dateFormatter.string(from: timestamp)
            return "[\(ts)] [\(level.rawValue.uppercased())] [\(category.label)] \(message)"
        }

        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()
    }

    // MARK: - State

    /// In-memory buffer of recent entries (most recent first). Capped at `maxBufferSize`.
    private(set) var entries: [Entry] = []

    /// Number of entries currently in memory.
    var entryCount: Int { entries.count }

    // MARK: - Configuration

    /// Maximum entries kept in memory.
    private let maxBufferSize = 500

    /// Maximum log file size before rotation (1 MB).
    private let maxFileSize: UInt64 = 1_048_576

    /// Serial queue for thread-safe file I/O.
    private let ioQueue = DispatchQueue(label: "com.crossappjtv.debuglogger", qos: .utility)

    // MARK: - File Paths

    /// Directory for log files.
    static var logDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs")
    }

    /// Current log file.
    static var logFileURL: URL {
        logDirectoryURL.appendingPathComponent("crossx-debug.log")
    }

    /// Rotated (previous) log file.
    static var rotatedLogFileURL: URL {
        logDirectoryURL.appendingPathComponent("crossx-debug.previous.log")
    }

    // MARK: - Init

    private init() {
        ensureLogDirectory()
        loadRecentFromFile()
    }

    // MARK: - Public API

    /// Log a message. This is the primary entry point — call from anywhere.
    static func log(_ message: String, level: Level = .info, category: Category = .general) {
        shared.append(message: message, level: level, category: category)
    }

    /// Export the full log file contents as a plain text string.
    func exportAsText() -> String {
        var result = ""

        // Include rotated file first (older entries)
        if let rotated = try? String(contentsOf: Self.rotatedLogFileURL, encoding: .utf8) {
            result += rotated
        }

        // Then current file
        if let current = try? String(contentsOf: Self.logFileURL, encoding: .utf8) {
            result += current
        }

        if result.isEmpty {
            result = "No log entries."
        }

        return result
    }

    /// Delete all log files and clear the in-memory buffer.
    func clearAll() {
        entries.removeAll()
        ioQueue.async {
            try? FileManager.default.removeItem(at: Self.logFileURL)
            try? FileManager.default.removeItem(at: Self.rotatedLogFileURL)
        }
    }

    /// Total size of all log files on disk.
    var logFileSize: Int64 {
        let fm = FileManager.default
        var total: Int64 = 0

        for url in [Self.logFileURL, Self.rotatedLogFileURL] {
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    /// Formatted log file size string.
    var formattedLogSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: logFileSize)
    }

    // MARK: - Private: Append

    private func append(message: String, level: Level, category: Category) {
        let entry = Entry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )

        // Update in-memory buffer (on main actor since @Observable)
        entries.insert(entry, at: 0)
        if entries.count > maxBufferSize {
            entries.removeLast(entries.count - maxBufferSize)
        }

        // Write to file on background queue
        let line = entry.fileLine + "\n"
        ioQueue.async { [weak self] in
            self?.writeToFile(line)
        }
    }

    // MARK: - Private: File I/O

    private func ensureLogDirectory() {
        let dir = Self.logDirectoryURL
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func writeToFile(_ line: String) {
        let fileURL = Self.logFileURL
        let fm = FileManager.default

        // Create file if it doesn't exist
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }

        // Check rotation
        if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? UInt64,
           size >= maxFileSize {
            rotateFile()
        }

        // Append line
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
    }

    private func rotateFile() {
        let fm = FileManager.default
        // Remove old rotated file
        try? fm.removeItem(at: Self.rotatedLogFileURL)
        // Move current to rotated
        try? fm.moveItem(at: Self.logFileURL, to: Self.rotatedLogFileURL)
        // Create fresh current file
        fm.createFile(atPath: Self.logFileURL.path, contents: nil)
    }

    /// Load recent entries from the file into the in-memory buffer on startup.
    private func loadRecentFromFile() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            var lines: [String] = []

            // Read current file
            if let content = try? String(contentsOf: Self.logFileURL, encoding: .utf8) {
                lines.append(contentsOf: content.components(separatedBy: "\n").filter { !$0.isEmpty })
            }

            // Take last N lines
            let recentLines = Array(lines.suffix(self.maxBufferSize))
            let parsed = recentLines.compactMap { self.parseLine($0) }

            Task { @MainActor [weak self] in
                self?.entries = parsed.reversed()
            }
        }
    }

    /// Parse a log file line back into an Entry.
    /// Format: [2026-02-16 16:42:14] [ERROR] [Queue] message here
    private func parseLine(_ line: String) -> Entry? {
        // Quick regex-free parsing
        guard line.hasPrefix("[") else { return nil }

        // Extract timestamp: [2026-02-16 16:42:14]
        guard let tsEnd = line.firstIndex(of: "]") else { return nil }
        let tsString = String(line[line.index(after: line.startIndex)..<tsEnd])

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = formatter.date(from: tsString) ?? Date()

        // Remaining: " [ERROR] [Queue] message here"
        let afterTs = String(line[line.index(after: tsEnd)...]).trimmingCharacters(in: .whitespaces)

        // Extract level: [ERROR]
        guard afterTs.hasPrefix("["),
              let levelEnd = afterTs.firstIndex(of: "]") else { return nil }
        let levelStr = String(afterTs[afterTs.index(after: afterTs.startIndex)..<levelEnd]).lowercased()
        let level = Level(rawValue: levelStr) ?? .info

        // Extract category: [Queue]
        let afterLevel = String(afterTs[afterTs.index(after: levelEnd)...]).trimmingCharacters(in: .whitespaces)
        guard afterLevel.hasPrefix("["),
              let catEnd = afterLevel.firstIndex(of: "]") else { return nil }
        let catStr = String(afterLevel[afterLevel.index(after: afterLevel.startIndex)..<catEnd]).lowercased()
        let category = Category(rawValue: catStr) ?? .general

        // Message is everything after
        let message = String(afterLevel[afterLevel.index(after: catEnd)...]).trimmingCharacters(in: .whitespaces)

        return Entry(
            id: UUID(),
            timestamp: timestamp,
            level: level,
            category: category,
            message: message
        )
    }
}
