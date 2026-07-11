import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscales and re-encodes article images for EPUB embedding.
///
/// Output is color JPEG capped at 1200 px — large enough for the in-app
/// reader on Retina screens; the pre-upload `EPUBOptimizer` takes care of
/// panel-sized grayscale for the e-ink device.
nonisolated enum ImageProcessor {

    /// Maximum output dimension (longest side).
    static let maxDimension: CGFloat = 1200

    /// JPEG encode quality.
    static let jpegQuality: CGFloat = 0.7

    /// Decompression-bomb guard (same policy as EPUBOptimizer).
    private static let maxDecodedMegapixels: Double = 50

    /// Re-encode arbitrary image bytes as a bounded JPEG.
    ///
    /// - Returns: JPEG data plus output pixel size, or nil when the data is
    ///   not a decodable/safe image.
    static func reencode(
        _ data: Data,
        maxDimension: CGFloat = ImageProcessor.maxDimension,
        quality: CGFloat = ImageProcessor.jpegQuality
    ) -> (data: Data, width: Int, height: Int)? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }

        // Never fully decode enormous images
        let megapixels = Double(width) * Double(height) / 1_000_000
        guard megapixels <= maxDecodedMegapixels else { return nil }

        // Memory-bounded downsampled decode
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
        ] as CFDictionary
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        // Encode JPEG (flatten any alpha onto white for e-ink friendliness)
        let outWidth = decoded.width
        let outHeight = decoded.height
        guard let context = CGContext(
            data: nil,
            width: outWidth,
            height: outHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: outWidth, height: outHeight))
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))
        guard let flattened = context.makeImage() else { return nil }

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        let encodeOptions = [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary
        CGImageDestinationAddImage(destination, flattened, encodeOptions)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return (encoded as Data, outWidth, outHeight)
    }
}
