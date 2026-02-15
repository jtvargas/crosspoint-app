import CoreGraphics
import Foundation

/// Encodes a `CGImage` into Windows BMP format (BITMAPINFOHEADER, BI_RGB).
///
/// Faithfully implements the BMP specification used by the X4 wallpaper converter:
/// - 14-byte file header + 40-byte DIB header (BITMAPINFOHEADER)
/// - No compression (BI_RGB)
/// - Bottom-up scanline order
/// - 4-byte row alignment
/// - BGR channel order for 24-bit; palette-indexed for 8/4/1-bit
nonisolated struct BMPEncoder {

    // MARK: - Public API

    /// Encode a CGImage as BMP data at the specified color depth.
    ///
    /// - Parameters:
    ///   - image: The source image (must have accessible pixel data).
    ///   - depth: Target BMP bit depth (24, 8, 4, or 1).
    /// - Returns: A `Data` object containing the complete BMP file.
    static func encode(image: CGImage, depth: BMPColorDepth) -> Data {
        let width = image.width
        let height = image.height

        // Extract RGBA pixel data from the CGImage
        let pixels = extractPixels(from: image, width: width, height: height)

        // Build BMP components
        let palette = buildPalette(for: depth)
        let pixelData = encodePixelData(
            pixels: pixels,
            width: width,
            height: height,
            depth: depth
        )

        let paletteSize = palette.count
        let headerSize = 14 + 40 // File header + DIB header
        let pixelOffset = headerSize + paletteSize
        let fileSize = pixelOffset + pixelData.count

        var data = Data(capacity: fileSize)

        // File Header (14 bytes)
        data.appendBMPUInt16(0x4D42)           // "BM" magic (little-endian: 0x42='B', 0x4D='M')
        data.appendBMPUInt32(UInt32(fileSize))  // Total file size
        data.appendBMPUInt16(0)                 // Reserved
        data.appendBMPUInt16(0)                 // Reserved
        data.appendBMPUInt32(UInt32(pixelOffset)) // Offset to pixel data

        // DIB Header — BITMAPINFOHEADER (40 bytes)
        data.appendBMPUInt32(40)               // DIB header size
        data.appendBMPInt32(Int32(width))       // Width
        data.appendBMPInt32(Int32(height))      // Height (positive = bottom-up)
        data.appendBMPUInt16(1)                 // Color planes
        data.appendBMPUInt16(UInt16(depth.rawValue)) // Bits per pixel
        data.appendBMPUInt32(0)                 // Compression (BI_RGB)
        data.appendBMPUInt32(UInt32(pixelData.count)) // Pixel data size
        data.appendBMPUInt32(2835)              // Horizontal resolution (~72 DPI)
        data.appendBMPUInt32(2835)              // Vertical resolution (~72 DPI)
        let colorCount: UInt32 = depth == .depth24 ? 0 : UInt32(1 << depth.rawValue)
        data.appendBMPUInt32(colorCount)        // Colors in palette
        data.appendBMPUInt32(0)                 // Important colors (0 = all)

        // Color palette
        data.append(palette)

        // Pixel data
        data.append(pixelData)

        return data
    }

    // MARK: - Pixel Extraction

    /// Extract raw RGBA pixel data from a CGImage.
    private static func extractPixels(
        from image: CGImage,
        width: Int,
        height: Int
    ) -> [UInt8] {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        var pixelData = [UInt8](repeating: 0, count: totalBytes)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return pixelData
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelData
    }

    // MARK: - Palette Generation

    /// Build the color palette for the given depth.
    private static func buildPalette(for depth: BMPColorDepth) -> Data {
        switch depth {
        case .depth24:
            return Data() // No palette for 24-bit

        case .depth8:
            // 256-color palette: 3-3-2 RGB mapping
            var palette = Data(capacity: 256 * 4)
            for i in 0..<256 {
                let r = UInt8(Double((i >> 5) & 0x07) * 255.0 / 7.0 + 0.5)
                let g = UInt8(Double((i >> 2) & 0x07) * 255.0 / 7.0 + 0.5)
                let b = UInt8(Double(i & 0x03) * 255.0 / 3.0 + 0.5)
                palette.append(b)  // Blue
                palette.append(g)  // Green
                palette.append(r)  // Red
                palette.append(0)  // Reserved
            }
            return palette

        case .depth4:
            // 16-level uniform grayscale palette
            var palette = Data(capacity: 16 * 4)
            for i in 0..<16 {
                let gray = UInt8(Double(i) * 255.0 / 15.0 + 0.5)
                palette.append(gray) // Blue
                palette.append(gray) // Green
                palette.append(gray) // Red
                palette.append(0)    // Reserved
            }
            return palette

        case .depth1:
            // 2-color: black and white
            var palette = Data(capacity: 2 * 4)
            // Index 0: Black
            palette.append(contentsOf: [0, 0, 0, 0])
            // Index 1: White
            palette.append(contentsOf: [255, 255, 255, 0])
            return palette
        }
    }

    // MARK: - Pixel Data Encoding

    /// Encode pixel data in BMP bottom-up scanline format.
    private static func encodePixelData(
        pixels: [UInt8],
        width: Int,
        height: Int,
        depth: BMPColorDepth
    ) -> Data {
        let rowSize = Self.rowSize(width: width, depth: depth)
        var data = Data(capacity: rowSize * height)
        let srcBytesPerRow = width * 4

        // BMP stores rows bottom-up
        for y in stride(from: height - 1, through: 0, by: -1) {
            let rowStart = y * srcBytesPerRow

            switch depth {
            case .depth24:
                encode24BitRow(
                    pixels: pixels,
                    rowStart: rowStart,
                    width: width,
                    rowSize: rowSize,
                    into: &data
                )

            case .depth8:
                encode8BitRow(
                    pixels: pixels,
                    rowStart: rowStart,
                    width: width,
                    rowSize: rowSize,
                    into: &data
                )

            case .depth4:
                encode4BitRow(
                    pixels: pixels,
                    rowStart: rowStart,
                    width: width,
                    rowSize: rowSize,
                    into: &data
                )

            case .depth1:
                encode1BitRow(
                    pixels: pixels,
                    rowStart: rowStart,
                    width: width,
                    rowSize: rowSize,
                    into: &data
                )
            }
        }

        return data
    }

    /// Padded row size in bytes (4-byte aligned).
    private static func rowSize(width: Int, depth: BMPColorDepth) -> Int {
        switch depth {
        case .depth24:
            return ((width * 3 + 3) / 4) * 4
        case .depth8:
            return ((width + 3) / 4) * 4
        case .depth4:
            return (((width + 1) / 2 + 3) / 4) * 4
        case .depth1:
            return (((width + 7) / 8 + 3) / 4) * 4
        }
    }

    // MARK: - Per-Row Encoders

    /// 24-bit: 3 bytes per pixel in BGR order.
    private static func encode24BitRow(
        pixels: [UInt8],
        rowStart: Int,
        width: Int,
        rowSize: Int,
        into data: inout Data
    ) {
        var row = Data(count: rowSize)
        for x in 0..<width {
            let srcIdx = rowStart + x * 4
            let dstIdx = x * 3
            row[dstIdx]     = pixels[srcIdx + 2] // B
            row[dstIdx + 1] = pixels[srcIdx + 1] // G
            row[dstIdx + 2] = pixels[srcIdx]     // R
        }
        data.append(row)
    }

    /// 8-bit: 1 byte palette index using 3-3-2 RGB mapping.
    private static func encode8BitRow(
        pixels: [UInt8],
        rowStart: Int,
        width: Int,
        rowSize: Int,
        into data: inout Data
    ) {
        var row = Data(count: rowSize)
        for x in 0..<width {
            let srcIdx = rowStart + x * 4
            let r = pixels[srcIdx]
            let g = pixels[srcIdx + 1]
            let b = pixels[srcIdx + 2]
            let index = ((r >> 5) << 5) | ((g >> 5) << 2) | (b >> 6)
            row[x] = index
        }
        data.append(row)
    }

    /// 4-bit: 2 pixels per byte (high nibble first), grayscale palette.
    private static func encode4BitRow(
        pixels: [UInt8],
        rowStart: Int,
        width: Int,
        rowSize: Int,
        into data: inout Data
    ) {
        var row = Data(count: rowSize)
        for x in 0..<width {
            let srcIdx = rowStart + x * 4
            let r = Double(pixels[srcIdx])
            let g = Double(pixels[srcIdx + 1])
            let b = Double(pixels[srcIdx + 2])
            let gray = r * 0.299 + g * 0.587 + b * 0.114
            let index = UInt8((gray / 255.0 * 15.0).rounded())

            let byteIdx = x / 2
            if x % 2 == 0 {
                row[byteIdx] = index << 4 // High nibble
            } else {
                row[byteIdx] |= index     // Low nibble
            }
        }
        data.append(row)
    }

    /// 1-bit: 8 pixels per byte (MSB first), threshold at 127.
    private static func encode1BitRow(
        pixels: [UInt8],
        rowStart: Int,
        width: Int,
        rowSize: Int,
        into data: inout Data
    ) {
        var row = Data(count: rowSize)
        for x in 0..<width {
            let srcIdx = rowStart + x * 4
            let r = Double(pixels[srcIdx])
            let g = Double(pixels[srcIdx + 1])
            let b = Double(pixels[srcIdx + 2])
            let gray = r * 0.299 + g * 0.587 + b * 0.114
            let bit: UInt8 = gray > 127 ? 1 : 0

            let byteIdx = x / 8
            let bitPos = 7 - (x % 8) // MSB first
            row[byteIdx] |= bit << bitPos
        }
        data.append(row)
    }
}

// MARK: - Data Helpers for BMP Binary Writing

private extension Data {
    /// Append a 16-bit unsigned integer in little-endian byte order.
    mutating func appendBMPUInt16(_ value: UInt16) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }

    /// Append a 32-bit unsigned integer in little-endian byte order.
    mutating func appendBMPUInt32(_ value: UInt32) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }

    /// Append a 32-bit signed integer in little-endian byte order.
    mutating func appendBMPInt32(_ value: Int32) {
        var le = value.littleEndian
        withUnsafePointer(to: &le) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 4) { bytes in
                append(bytes, count: 4)
            }
        }
    }
}
