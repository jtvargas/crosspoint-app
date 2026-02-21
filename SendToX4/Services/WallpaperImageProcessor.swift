import CoreGraphics
import Foundation

/// Processes images for device wallpaper conversion using Core Graphics.
///
/// The pipeline matches the reference X4 wallpaper converter:
/// 1. Apply rotation
/// 2. Create target-sized canvas with background fill
/// 3. Draw image using the selected fit mode and alignment
/// 4. Apply grayscale conversion (BT.601 luminance)
/// 5. Apply color inversion (if enabled)
/// 6. Apply color depth quantization
nonisolated struct WallpaperImageProcessor {

    // MARK: - Public API

    /// Process a source image with the given settings for the target device.
    ///
    /// - Parameters:
    ///   - image: Original source CGImage.
    ///   - settings: User-configured wallpaper settings.
    ///   - device: Target device specification (resolution).
    /// - Returns: Processed CGImage at the device's resolution, or `nil` on failure.
    static func process(
        image: CGImage,
        settings: WallpaperSettings,
        device: DeviceSpecification
    ) -> CGImage? {
        let targetWidth = Int(device.resolution.width)
        let targetHeight = Int(device.resolution.height)

        // Create the target-sized canvas
        guard let context = createContext(width: targetWidth, height: targetHeight) else {
            DebugLogger.log(
                "Failed to create CG context (\(targetWidth)x\(targetHeight))",
                level: .error, category: .wallpaper
            )
            return nil
        }

        // Fill background (black)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        // Calculate effective source dimensions after rotation
        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        let effWidth: CGFloat
        let effHeight: CGFloat

        if settings.rotation.swapsDimensions {
            effWidth = sourceHeight
            effHeight = sourceWidth
        } else {
            effWidth = sourceWidth
            effHeight = sourceHeight
        }

        // Calculate draw rect based on fit mode
        let drawRect: CGRect
        let sourceRect: CGRect

        switch settings.fitMode {
        case .stretch:
            drawRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
            sourceRect = CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)

        case .fit:
            let (rect, srcRect) = fitCalculation(
                effectiveWidth: effWidth,
                effectiveHeight: effHeight,
                targetWidth: CGFloat(targetWidth),
                targetHeight: CGFloat(targetHeight),
                alignment: settings.alignment,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight
            )
            drawRect = rect
            sourceRect = srcRect

        case .fill:
            let (rect, srcRect) = fillCalculation(
                effectiveWidth: effWidth,
                effectiveHeight: effHeight,
                targetWidth: CGFloat(targetWidth),
                targetHeight: CGFloat(targetHeight),
                alignment: settings.alignment,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                rotation: settings.rotation
            )
            drawRect = rect
            sourceRect = srcRect
        }

        // Apply zoom & pan to the source rect (crop a smaller region of the source)
        let zoomedSourceRect = applyZoomPan(
            to: sourceRect,
            zoomScale: settings.zoomScale,
            panOffset: settings.panOffset,
            imageWidth: sourceWidth,
            imageHeight: sourceHeight
        )

        // Draw the image with rotation
        drawRotatedImage(
            context: context,
            image: image,
            rotation: settings.rotation,
            drawRect: drawRect,
            sourceRect: zoomedSourceRect
        )

        // Get the rendered image for pixel manipulation
        guard let rendered = context.makeImage() else {
            DebugLogger.log(
                "Context.makeImage() returned nil (\(targetWidth)x\(targetHeight))",
                level: .error, category: .wallpaper
            )
            return nil
        }

        // Apply pixel-level effects (grayscale, invert, depth quantization)
        return applyEffects(
            to: rendered,
            width: targetWidth,
            height: targetHeight,
            settings: settings
        )
    }

    // MARK: - Zoom & Pan

    /// Apply zoom and pan to a source rect, producing a smaller crop region.
    ///
    /// - `zoomScale` 1.0 = use the source rect as-is.
    /// - `zoomScale` 2.0 = crop to half the source area (quarter in each dimension is wrong —
    ///   we divide each dimension by zoomScale so area shrinks by zoomScale²,
    ///   but visually it's "2x zoom" which means half the width & height).
    /// - `panOffset` is normalized (−1…1). At (0,0) the crop is centred within the
    ///   source rect. At (−1,−1) the crop is anchored at the source rect's origin.
    ///
    /// The result is clamped so it never exceeds the full image bounds.
    private static func applyZoomPan(
        to sourceRect: CGRect,
        zoomScale: CGFloat,
        panOffset: CGSize,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> CGRect {
        guard zoomScale > 1.0 || panOffset != .zero else { return sourceRect }

        let clampedZoom = max(1.0, zoomScale)

        // Zoomed crop dimensions within the existing source rect
        let cropW = sourceRect.width / clampedZoom
        let cropH = sourceRect.height / clampedZoom

        // Centre of the existing source rect
        let centerX = sourceRect.midX
        let centerY = sourceRect.midY

        // Maximum offset the centre can shift before the crop exits the source rect
        let maxShiftX = (sourceRect.width - cropW) / 2
        let maxShiftY = (sourceRect.height - cropH) / 2

        // Apply normalised pan (−1…1) → pixel shift
        let shiftX = panOffset.width * maxShiftX
        let shiftY = panOffset.height * maxShiftY

        // New crop origin (centred + shifted)
        var cropX = centerX + shiftX - cropW / 2
        var cropY = centerY + shiftY - cropH / 2

        // Clamp to image bounds
        cropX = max(0, min(cropX, imageWidth - cropW))
        cropY = max(0, min(cropY, imageHeight - cropH))

        return CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
    }

    // MARK: - Context Creation

    /// Create a 32-bit RGBA CGContext.
    private static func createContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    // MARK: - Fit Mode Calculations

    /// Calculate draw rect for **fit** mode (image fully visible, letterboxed).
    private static func fitCalculation(
        effectiveWidth: CGFloat,
        effectiveHeight: CGFloat,
        targetWidth: CGFloat,
        targetHeight: CGFloat,
        alignment: WallpaperAlignment,
        sourceWidth: CGFloat,
        sourceHeight: CGFloat
    ) -> (drawRect: CGRect, sourceRect: CGRect) {
        let imgRatio = effectiveWidth / effectiveHeight
        let canvasRatio = targetWidth / targetHeight

        let drawWidth: CGFloat
        let drawHeight: CGFloat

        if imgRatio > canvasRatio {
            // Image is wider — fit to width, letterbox top/bottom
            drawWidth = targetWidth
            drawHeight = targetWidth / imgRatio
        } else {
            // Image is taller — fit to height, pillarbox left/right
            drawHeight = targetHeight
            drawWidth = targetHeight * imgRatio
        }

        let offset = alignmentOffset(
            drawWidth: drawWidth,
            drawHeight: drawHeight,
            canvasWidth: targetWidth,
            canvasHeight: targetHeight,
            alignment: alignment
        )

        let drawRect = CGRect(x: offset.x, y: offset.y, width: drawWidth, height: drawHeight)
        let sourceRect = CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)

        return (drawRect, sourceRect)
    }

    /// Calculate draw and source rects for **fill** mode (image covers canvas, excess cropped).
    private static func fillCalculation(
        effectiveWidth: CGFloat,
        effectiveHeight: CGFloat,
        targetWidth: CGFloat,
        targetHeight: CGFloat,
        alignment: WallpaperAlignment,
        sourceWidth: CGFloat,
        sourceHeight: CGFloat,
        rotation: WallpaperRotation
    ) -> (drawRect: CGRect, sourceRect: CGRect) {
        let scaleFactor = max(targetWidth / effectiveWidth, targetHeight / effectiveHeight)

        // How much of the effective (rotated) image we need
        let effCropWidth = targetWidth / scaleFactor
        let effCropHeight = targetHeight / scaleFactor

        // Determine offset within effective space based on alignment
        let excessX = effectiveWidth - effCropWidth
        let excessY = effectiveHeight - effCropHeight

        var cropX: CGFloat = 0
        var cropY: CGFloat = 0

        switch alignment.horizontal {
        case .left:   cropX = 0
        case .center: cropX = excessX / 2
        case .right:  cropX = excessX
        }

        // CG origin is bottom-left: invert vertical crop so .top crops
        // from the visual top (high-Y end in CG coordinates).
        switch alignment.vertical {
        case .top:    cropY = excessY
        case .center: cropY = excessY / 2
        case .bottom: cropY = 0
        }

        // Remap effective-space coordinates back to original image coordinates
        let srcX: CGFloat
        let srcY: CGFloat
        let srcW: CGFloat
        let srcH: CGFloat

        if rotation.swapsDimensions {
            srcX = cropY
            srcY = cropX
            srcW = effCropHeight
            srcH = effCropWidth
        } else {
            srcX = cropX
            srcY = cropY
            srcW = effCropWidth
            srcH = effCropHeight
        }

        let drawRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        let sourceRect = CGRect(x: srcX, y: srcY, width: srcW, height: srcH)

        return (drawRect, sourceRect)
    }

    /// Compute the (x, y) offset for positioning an image within the canvas.
    private static func alignmentOffset(
        drawWidth: CGFloat,
        drawHeight: CGFloat,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat,
        alignment: WallpaperAlignment
    ) -> CGPoint {
        let x: CGFloat
        let y: CGFloat

        switch alignment.horizontal {
        case .left:   x = 0
        case .center: x = (canvasWidth - drawWidth) / 2
        case .right:  x = canvasWidth - drawWidth
        }

        // CG origin is bottom-left: Y=0 is visual bottom, Y=max is visual top.
        // Invert so .top maps to the visual top of the canvas.
        switch alignment.vertical {
        case .top:    y = canvasHeight - drawHeight
        case .center: y = (canvasHeight - drawHeight) / 2
        case .bottom: y = 0
        }

        return CGPoint(x: x, y: y)
    }

    // MARK: - Rotated Drawing

    /// Draw a CGImage with rotation applied.
    ///
    /// Core Graphics uses a bottom-left origin with Y pointing up,
    /// so we translate to the draw center, rotate, and draw offset.
    private static func drawRotatedImage(
        context: CGContext,
        image: CGImage,
        rotation: WallpaperRotation,
        drawRect: CGRect,
        sourceRect: CGRect
    ) {
        guard let cropped = image.cropping(to: sourceRect) else {
            DebugLogger.log(
                "CGImage.cropping failed — rect: \(Int(sourceRect.origin.x)),\(Int(sourceRect.origin.y)) \(Int(sourceRect.width))x\(Int(sourceRect.height)), image: \(image.width)x\(image.height)",
                level: .error, category: .wallpaper
            )
            return
        }

        context.saveGState()

        // Move origin to center of the draw rect
        let centerX = drawRect.midX
        let centerY = drawRect.midY
        context.translateBy(x: centerX, y: centerY)

        // Apply rotation (negative because CG Y-axis is flipped vs. screen coords)
        context.rotate(by: -rotation.radians)

        // Calculate the rect to draw into (centered at origin)
        let drawW: CGFloat
        let drawH: CGFloat

        if rotation.swapsDimensions {
            drawW = drawRect.height
            drawH = drawRect.width
        } else {
            drawW = drawRect.width
            drawH = drawRect.height
        }

        let rect = CGRect(
            x: -drawW / 2,
            y: -drawH / 2,
            width: drawW,
            height: drawH
        )
        context.draw(cropped, in: rect)

        context.restoreGState()
    }

    // MARK: - Pixel Effects

    /// Apply grayscale, inversion, and depth quantization to the rendered image.
    private static func applyEffects(
        to image: CGImage,
        width: Int,
        height: Int,
        settings: WallpaperSettings
    ) -> CGImage? {
        let needsEffects = settings.grayscale || settings.invert || settings.colorDepth != .depth24
        guard needsEffects else { return image }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        var pixels = [UInt8](repeating: 0, count: totalBytes)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Process each pixel
        for i in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
            var r = Double(pixels[i])
            var g = Double(pixels[i + 1])
            var b = Double(pixels[i + 2])

            // Grayscale (BT.601 luminance)
            if settings.grayscale {
                let gray = r * 0.299 + g * 0.587 + b * 0.114
                r = gray
                g = gray
                b = gray
            }

            // Invert
            if settings.invert {
                r = 255 - r
                g = 255 - g
                b = 255 - b
            }

            // Color depth quantization
            switch settings.colorDepth {
            case .depth24:
                break // No quantization

            case .depth8:
                if !(r == g && g == b) {
                    // 3-3-2 quantization
                    r = (r / 255.0 * 7.0).rounded() * (255.0 / 7.0)
                    g = (g / 255.0 * 7.0).rounded() * (255.0 / 7.0)
                    b = (b / 255.0 * 3.0).rounded() * (255.0 / 3.0)
                }

            case .depth4:
                let gray = r * 0.299 + g * 0.587 + b * 0.114
                let quantized = (gray / 255.0 * 15.0).rounded() * (255.0 / 15.0)
                r = quantized
                g = quantized
                b = quantized

            case .depth1:
                let gray = r * 0.299 + g * 0.587 + b * 0.114
                let bw: Double = gray > 127 ? 255 : 0
                r = bw
                g = bw
                b = bw
            }

            pixels[i]     = UInt8(min(255, max(0, r)))
            pixels[i + 1] = UInt8(min(255, max(0, g)))
            pixels[i + 2] = UInt8(min(255, max(0, b)))
        }

        return context.makeImage()
    }
}
