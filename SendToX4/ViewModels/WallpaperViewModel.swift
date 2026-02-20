import CoreGraphics
import Foundation
import PhotosUI
import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Orchestrates the WallpaperX workflow: image loading, processing, preview, and export.
@MainActor
@Observable
final class WallpaperViewModel {

    // MARK: - Image State

    /// The original source image loaded from the user's selection.
    var sourceImage: CGImage?

    /// The processed preview image reflecting current settings.
    var processedPreview: CGImage?

    /// The filename of the imported image (without extension).
    var sourceFilename: String?

    /// PhotosPicker selection binding.
    var selectedPhotoItem: PhotosPickerItem? {
        didSet {
            if let item = selectedPhotoItem {
                Task { await loadImage(from: item) }
            }
        }
    }

    // MARK: - Settings

    /// User-configurable conversion settings.
    var settings = WallpaperSettings() {
        didSet {
            if !isGestureActive { schedulePreviewUpdate() }
        }
    }

    /// When `true`, settings mutations are suppressed from triggering preview
    /// regeneration.  The View sets this during continuous gestures (pinch/drag)
    /// so that only GPU-composited transforms provide visual feedback.  On
    /// gesture end, the View sets this back to `false` and calls
    /// `updatePreview()` once.
    var isGestureActive = false

    /// Target device specification.
    var device = DeviceSpecification.x4

    // MARK: - UI State

    var isProcessing = false
    var errorMessage: String?
    var statusMessage: String?
    var showFileImporter = false
    var showShareSheet = false

    /// The last generated BMP data (for sharing/saving).
    var lastBMPData: Data?
    var lastBMPFilename: String?

    /// Set to `true` when a review prompt should be shown. The View observes this.
    var shouldRequestReview = false

    // MARK: - Preview Debounce

    private var previewTask: Task<Void, Never>?

    // MARK: - Image Loading

    /// Load an image from a PhotosPicker item.
    func loadImage(from item: PhotosPickerItem) async {
        errorMessage = nil
        statusMessage = nil

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                DebugLogger.log("Failed to load image from Photos: nil data", level: .error, category: .wallpaper)
                errorMessage = loc(.couldNotLoadImage)
                return
            }
            loadImageFromData(data, filename: "photo")
        } catch {
            DebugLogger.log("Failed to load image from Photos: \(error.localizedDescription)", level: .error, category: .wallpaper)
            errorMessage = loc(.failedToLoadImage, error.localizedDescription)
        }
    }

    /// Load an image from a file URL (Files app importer).
    func loadImage(from url: URL) {
        errorMessage = nil
        statusMessage = nil

        guard url.startAccessingSecurityScopedResource() else {
            DebugLogger.log("Cannot access security-scoped file: \(url.lastPathComponent)", level: .error, category: .wallpaper)
            errorMessage = loc(.cannotAccessFile)
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let stem = url.deletingPathExtension().lastPathComponent
            loadImageFromData(data, filename: stem)
        } catch {
            DebugLogger.log("Failed to read image file: \(error.localizedDescription)", level: .error, category: .wallpaper)
            errorMessage = loc(.failedToReadFile, error.localizedDescription)
        }
    }

    /// Common image loading from raw data.
    private func loadImageFromData(_ data: Data, filename: String) {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            DebugLogger.log("Unsupported image format (\(data.count) bytes)", level: .error, category: .wallpaper)
            errorMessage = loc(.unsupportedImageFormat)
            return
        }
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
              ) else {
            DebugLogger.log("Unsupported image format (\(data.count) bytes)", level: .error, category: .wallpaper)
            errorMessage = loc(.unsupportedImageFormat)
            return
        }
        #endif

        sourceImage = cgImage
        sourceFilename = filename
        lastBMPData = nil
        lastBMPFilename = nil
        statusMessage = nil

        DebugLogger.log(
            "Loaded image: \(filename) (\(cgImage.width)x\(cgImage.height))",
            level: .info, category: .wallpaper
        )

        // Reset settings for new image
        settings = WallpaperSettings()

        updatePreview()
    }

    // MARK: - Preview Generation

    /// Schedule a debounced preview update (50ms delay to batch rapid changes).
    private func schedulePreviewUpdate() {
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            updatePreview()
        }
    }

    /// Regenerate the preview image from the source using current settings.
    func updatePreview() {
        guard let source = sourceImage else {
            processedPreview = nil
            return
        }

        let currentSettings = settings
        let currentDevice = device

        // Run processing off the main actor for large images
        Task.detached(priority: .userInitiated) {
            let result = WallpaperImageProcessor.process(
                image: source,
                settings: currentSettings,
                device: currentDevice
            )
            if result == nil {
                DebugLogger.log(
                    "Preview generation returned nil (zoom: \(String(format: "%.1f", currentSettings.zoomScale))x, mode: \(currentSettings.fitMode.rawValue))",
                    level: .warning, category: .wallpaper
                )
            }
            await MainActor.run {
                self.processedPreview = result
            }
        }
    }

    // MARK: - Conversion & Upload

    /// Convert the image and upload to the connected device.
    func convertAndSend(
        deviceVM: DeviceViewModel,
        settings deviceSettings: DeviceSettings,
        modelContext: ModelContext,
        toast: ToastManager? = nil
    ) async {
        guard let source = sourceImage else {
            errorMessage = loc(.noImageLoaded)
            return
        }

        guard !deviceVM.isUploading else {
            errorMessage = loc(.uploadAlreadyInProgress)
            return
        }

        isProcessing = true
        errorMessage = nil
        statusMessage = loc(.processing)

        do {
            // Process the image
            guard let processed = WallpaperImageProcessor.process(
                image: source,
                settings: settings,
                device: device
            ) else {
                DebugLogger.log(
                    "Image processing failed for \(sourceFilename ?? "unknown")",
                    level: .error, category: .wallpaper
                )
                throw WallpaperError.processingFailed
            }

            // Encode to BMP
            statusMessage = loc(.encodingBMP)
            let bmpData = BMPEncoder.encode(image: processed, depth: settings.colorDepth)
            let filename = generateFilename()

            lastBMPData = bmpData
            lastBMPFilename = filename

            // Upload to device if connected and not busy deleting
            if deviceVM.isConnected && !deviceVM.isBatchDeleting {
                statusMessage = loc(.phaseSending)
                try await deviceVM.upload(
                    data: bmpData,
                    filename: filename,
                    toFolder: deviceSettings.wallpaperFolder
                )

                // Log activity event
                let event = ActivityEvent(
                    category: .wallpaper,
                    action: .wallpaperUpload,
                    status: .success,
                    detail: filename
                )
                modelContext.insert(event)

                DebugLogger.log(
                    "Sent wallpaper \(filename) (\(bmpData.count) bytes) to /\(deviceSettings.wallpaperFolder)/",
                    level: .info, category: .wallpaper
                )

                statusMessage = loc(.sentImageToFolder, filename, deviceSettings.wallpaperFolder)
                toast?.showSuccess(loc(.toastImageSent), subtitle: filename)

                if ReviewPromptManager.shouldPromptAfterSuccess() {
                    shouldRequestReview = true
                }

                // Auto-reset after delay so the user sees the success message
                try? await Task.sleep(for: .seconds(1.5))
                clearImage()
            } else {
                DebugLogger.log(
                    "Wallpaper converted: \(filename) (\(bmpData.count) bytes) — device not connected",
                    level: .info, category: .wallpaper
                )
                statusMessage = loc(.convertedImageSaveOrConnect, filename)
                toast?.showQueued(loc(.toastImageConverted), subtitle: filename)
            }
        } catch {
            DebugLogger.log(
                "Wallpaper convert/send failed: \(error.localizedDescription)",
                level: .error, category: .wallpaper
            )
            errorMessage = error.localizedDescription
            toast?.showError(loc(.phaseFailed), subtitle: error.localizedDescription)

            // Log failed activity if it was a device upload failure
            if deviceVM.isConnected {
                let event = ActivityEvent(
                    category: .wallpaper,
                    action: .wallpaperUpload,
                    status: .failed,
                    detail: generateFilename(),
                    errorMessage: error.localizedDescription
                )
                modelContext.insert(event)
            }
        }

        isProcessing = false
    }

    /// Generate BMP data for local export (without device upload).
    func exportBMPData() -> Data? {
        guard let source = sourceImage else { return nil }

        guard let processed = WallpaperImageProcessor.process(
            image: source,
            settings: settings,
            device: device
        ) else { return nil }

        let bmpData = BMPEncoder.encode(image: processed, depth: settings.colorDepth)
        let filename = generateFilename()

        lastBMPData = bmpData
        lastBMPFilename = filename

        return bmpData
    }

    // MARK: - Clear

    /// Remove the current image and reset state.
    func clearImage() {
        sourceImage = nil
        processedPreview = nil
        sourceFilename = nil
        lastBMPData = nil
        lastBMPFilename = nil
        errorMessage = nil
        statusMessage = nil
        selectedPhotoItem = nil
        settings = WallpaperSettings()
    }

    // MARK: - Helpers

    /// Generate a unique BMP filename from the source filename + timestamp.
    /// Prevents overwriting when sending multiple wallpapers.
    private func generateFilename() -> String {
        let stem = sourceFilename ?? "wallpaper"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        return "\(stem)-\(timestamp).bmp"
    }
}

// MARK: - Errors

enum WallpaperError: LocalizedError {
    case processingFailed
    case noImage

    var errorDescription: String? {
        switch self {
        case .processingFailed: return loc(.imageProcessingFailed)
        case .noImage: return loc(.noImageLoaded)
        }
    }
}
