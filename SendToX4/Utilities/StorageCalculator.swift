import Foundation

/// Measures on-disk storage used by the app's SwiftData store, URL cache, and temp directory.
nonisolated struct StorageCalculator {

    // MARK: - Size Measurements

    /// Total size of the SwiftData store files (default.store + WAL + SHM).
    static func swiftDataStoreSize() -> Int64 {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return 0 }

        let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]
        return storeFiles.reduce(into: Int64(0)) { total, name in
            let url = appSupport.appendingPathComponent(name)
            total += fileSize(at: url)
        }
    }

    /// Current disk usage of the shared URL cache (web page fetches).
    static func urlCacheSize() -> Int64 {
        Int64(URLCache.shared.currentDiskUsage)
    }

    /// Total size of the app's temporary directory.
    static func tempDirectorySize() -> Int64 {
        directorySize(at: FileManager.default.temporaryDirectory)
    }

    /// Total size of the EPUB queue directory.
    static func queueDirectorySize() -> Int64 {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return 0 }
        return directorySize(at: appSupport.appendingPathComponent("EPUBQueue"))
    }

    // MARK: - Formatting

    /// Format a byte count to a human-readable string (e.g. "2.4 MB").
    static func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Private

    private static func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
