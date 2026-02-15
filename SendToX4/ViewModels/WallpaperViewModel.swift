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
        didSet { schedulePreviewUpdate() }
    }

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
                errorMessage = "Could not load the selected image."
                return
            }
            loadImageFromData(data, filename: "photo")
        } catch {
            errorMessage = "Failed to load image: \(error.localizedDescription)"
        }
    }

    /// Load an image from a file URL (Files app importer).
    func loadImage(from url: URL) {
        errorMessage = nil
        statusMessage = nil

        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let stem = url.deletingPathExtension().lastPathComponent
            loadImageFromData(data, filename: stem)
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
    }

    /// Common image loading from raw data.
    private func loadImageFromData(_ data: Data, filename: String) {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            errorMessage = "Unsupported image format."
            return
        }
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
              ) else {
            errorMessage = "Unsupported image format."
            return
        }
        #endif

        sourceImage = cgImage
        sourceFilename = filename
        lastBMPData = nil
        lastBMPFilename = nil
        statusMessage = nil

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
        modelContext: ModelContext
    ) async {
        guard let source = sourceImage else {
            errorMessage = "No image loaded."
            return
        }

        guard !deviceVM.isUploading else {
            errorMessage = "An upload is already in progress."
            return
        }

        isProcessing = true
        errorMessage = nil
        statusMessage = "Processing..."

        do {
            // Process the image
            guard let processed = WallpaperImageProcessor.process(
                image: source,
                settings: settings,
                device: device
            ) else {
                throw WallpaperError.processingFailed
            }

            // Encode to BMP
            statusMessage = "Encoding BMP..."
            let bmpData = BMPEncoder.encode(image: processed, depth: settings.colorDepth)
            let filename = generateFilename()

            lastBMPData = bmpData
            lastBMPFilename = filename

            // Upload to device if connected
            if deviceVM.isConnected {
                statusMessage = "Sending to X4..."
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

                statusMessage = "Sent \(filename) to /\(deviceSettings.wallpaperFolder)/"

                if ReviewPromptManager.shouldPromptAfterSuccess() {
                    shouldRequestReview = true
                }

                // Auto-reset after delay so the user sees the success message
                try? await Task.sleep(for: .seconds(1.5))
                clearImage()
            } else {
                statusMessage = "Converted \(filename) — save or connect to send."
            }
        } catch {
            errorMessage = error.localizedDescription

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
        case .processingFailed: return "Image processing failed."
        case .noImage: return "No image loaded."
        }
    }
}
