import CoreGraphics
import CoreImage

struct SendableImage: @unchecked Sendable {
    let image: CGImage
}

/// High-pass view that makes faint color patches visible: subtracts a Gaussian blur and
/// amplifies what's left around mid-gray. Flat areas come out solid gray, mottling shows up
/// as colored blobs, and lines and edges as bright or dark outlines.
///
/// Works on the stored (gamma-encoded) 8-bit values, without color management.
enum NoiseFilter {
    private static let context = CIContext(options: [
        .workingColorSpace: NSNull(),
        .outputColorSpace: NSNull(),
        .cacheIntermediates: false,
    ])

    static func render(_ image: CGImage, sigma: CGFloat, gain: CGFloat) -> CGImage? {
        let width = image.width, height = image.height
        let rowBytes = width * 4
        let count = rowBytes * height
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

        var original = [UInt8](repeating: 0, count: count)
        let drawn = original.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: bitmapInfo
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let input = CIImage(
            bitmapData: Data(original), bytesPerRow: rowBytes,
            size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: nil
        )
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        // The blur stays in floating point; rounding it to 8 bits would be amplified along with the noise.
        var blur = [Float](repeating: 0, count: count)
        context.render(
            blurred, toBitmap: &blur, rowBytes: rowBytes * MemoryLayout<Float>.size,
            bounds: input.extent, format: .RGBAf, colorSpace: nil
        )

        var output = [UInt8](repeating: 255, count: count)
        let g = Float(gain), scaledGain = Float(gain) * 255
        output.withUnsafeMutableBufferPointer { out in
            original.withUnsafeBufferPointer { a in
                blur.withUnsafeBufferPointer { b in
                    for pixel in stride(from: 0, to: count, by: 4) {
                        for channel in pixel..<(pixel + 3) {
                            let value = Float(a[channel]) * g - b[channel] * scaledGain + 128
                            out[channel] = UInt8(min(max(value, 0), 255))
                        }
                    }
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(output) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
