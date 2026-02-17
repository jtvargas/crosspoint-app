import Foundation

/// Tracks device transfer performance using exponential moving averages (EMA)
/// to produce increasingly accurate time estimates for queue batch sends.
///
/// Two metrics are tracked separately:
/// - **Transfer rate** (bytes/sec): raw upload speed to the ESP32.
/// - **Per-item overhead** (seconds): HTTP connection setup, multipart encoding,
///   and ESP32 processing time that is independent of file size.
///
/// Separating these ensures accurate estimates for both small (1-2 KB) and large
/// (200+ KB) files. The overhead dominates for tiny files; the rate dominates for
/// large ones. Together they reconstruct per-item time as `overhead + fileSize / rate`.
///
/// After each successful upload in `QueueViewModel.sendAll()`, the wall-clock
/// duration and file size are recorded here. The EMA blends new measurements
/// with the historical average so the estimate naturally adapts to the device's
/// real-world throughput (which varies by WiFi signal, file size, firmware, etc.).
///
/// Data is persisted in UserDefaults (following the `ReviewPromptManager` pattern).
nonisolated struct TransferStatsTracker {

    // MARK: - UserDefaults Keys

    private static let rateKey = "transferRateAverage"
    private static let overheadKey = "transferOverheadAverage"
    private static let countKey = "transferSampleCount"

    // MARK: - Constants

    /// EMA smoothing factor. 0.3 = 30% weight on the newest sample, 70% on history.
    /// After ~5 transfers the estimate is mostly data-driven; after ~10 it is stable.
    private static let alpha: Double = 0.3

    /// Fallback transfer rate when no history exists (~150 KB/s).
    /// Represents raw upload speed only (overhead is accounted for separately).
    static let fallbackRate: Double = 150_000

    /// Fallback per-item overhead (seconds) used when no history exists.
    /// Covers HTTP connection setup, multipart encoding, and ESP32 processing.
    /// Set conservatively — folders are pre-ensured at batch start so this
    /// does NOT include ensureFolder round-trips.
    static let fallbackOverhead: Double = 1.5

    /// Minimum plausible effective rate (10 KB/s) to prevent absurd estimates
    /// from outlier samples (e.g., ESP32 under heavy load).
    private static let minRate: Double = 10_000

    /// Maximum plausible effective rate (500 KB/s) to cap optimistic outliers
    /// (e.g., tiny files where overhead dominates and inflates apparent speed).
    private static let maxRate: Double = 500_000

    /// Minimum plausible per-item overhead (seconds).
    private static let minOverhead: Double = 0.1

    /// Maximum plausible per-item overhead (seconds).
    private static let maxOverhead: Double = 10.0

    // MARK: - Public API

    /// Record a successful transfer sample.
    ///
    /// Call this once per item after `DeviceViewModel.upload()` succeeds.
    /// The `duration` covers the upload call only (not inter-item cooldown).
    ///
    /// The method decomposes the duration into two components:
    /// - **Raw transfer time**: `bytes / rate` — scales with file size.
    /// - **Overhead**: `duration - rawTransferTime` — fixed per-item cost.
    ///
    /// Both are tracked via separate EMAs for accurate estimation across
    /// varying file sizes.
    ///
    /// - Parameters:
    ///   - bytes: File size in bytes (`QueueItem.fileSize`).
    ///   - duration: Wall-clock seconds for the upload call.
    static func recordTransfer(bytes: Int64, duration: Double) {
        guard duration > 0, bytes > 0 else { return }

        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: countKey)

        // --- Transfer Rate ---

        // Compute measured effective rate and clamp to plausible range
        let measuredRate = Double(bytes) / duration
        let clampedRate = min(max(measuredRate, minRate), maxRate)

        let currentRate = defaults.double(forKey: rateKey)
        let newRate: Double
        if count == 0 || currentRate <= 0 {
            newRate = clampedRate
        } else {
            newRate = alpha * clampedRate + (1 - alpha) * currentRate
        }

        // --- Per-Item Overhead ---

        // Derive overhead by subtracting the pure data-transfer component.
        // Use the *new* rate (not the measured one) to smooth out noise.
        let rawTransferTime = Double(bytes) / newRate
        let measuredOverhead = max(duration - rawTransferTime, 0)
        let clampedOverhead = min(max(measuredOverhead, minOverhead), maxOverhead)

        let currentOverhead = defaults.double(forKey: overheadKey)
        let newOverhead: Double
        if count == 0 || currentOverhead <= 0 {
            newOverhead = clampedOverhead
        } else {
            newOverhead = alpha * clampedOverhead + (1 - alpha) * currentOverhead
        }

        // --- Persist ---

        defaults.set(newRate, forKey: rateKey)
        defaults.set(newOverhead, forKey: overheadKey)
        defaults.set(count + 1, forKey: countKey)
    }

    /// The current transfer rate (bytes/sec) — raw upload speed only.
    /// Returns the learned EMA rate if available, otherwise the hardcoded fallback.
    static var effectiveTransferRate: Double {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: countKey)
        let rate = defaults.double(forKey: rateKey)
        if count > 0, rate > 0 {
            return rate
        }
        return fallbackRate
    }

    /// The current per-item overhead (seconds) — fixed cost independent of file size.
    /// Returns the learned EMA overhead if available, otherwise the hardcoded fallback.
    static var effectiveOverhead: Double {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: countKey)
        let overhead = defaults.double(forKey: overheadKey)
        if count > 0, overhead > 0 {
            return overhead
        }
        return fallbackOverhead
    }

    /// Whether any historical transfer data has been recorded.
    static var hasHistory: Bool {
        UserDefaults.standard.integer(forKey: countKey) > 0
    }

    /// Number of transfer samples recorded so far.
    static var sampleCount: Int {
        UserDefaults.standard.integer(forKey: countKey)
    }

    /// Clear all transfer statistics (e.g., when the user resets from Settings).
    /// The next estimation will fall back to the defaults until new
    /// transfers are recorded.
    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: rateKey)
        defaults.removeObject(forKey: overheadKey)
        defaults.removeObject(forKey: countKey)
    }
}
