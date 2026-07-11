import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SendToX4

struct ImageProcessorTests {

    private static func makePNG(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let out = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return out as Data
    }

    @Test func downscalesOversizedImageToJPEG() throws {
        let png = try Self.makePNG(width: 3000, height: 2000)
        let result = try #require(ImageProcessor.reencode(png))

        // JPEG magic bytes
        #expect(result.data.prefix(2) == Data([0xFF, 0xD8]))
        // Longest side capped at 1200, aspect preserved
        #expect(result.width <= 1200)
        #expect(result.height <= 1200)
        #expect(result.width > result.height) // landscape preserved
    }

    @Test func smallImageIsNotUpscaled() throws {
        let png = try Self.makePNG(width: 400, height: 300)
        let result = try #require(ImageProcessor.reencode(png))
        #expect(result.width <= 400)
        #expect(result.height <= 300)
    }

    @Test func garbageDataReturnsNil() {
        let garbage = Data((0..<1024).map { UInt8($0 % 255) })
        #expect(ImageProcessor.reencode(garbage) == nil)
    }

    @Test func emptyDataReturnsNil() {
        #expect(ImageProcessor.reencode(Data()) == nil)
    }
}
