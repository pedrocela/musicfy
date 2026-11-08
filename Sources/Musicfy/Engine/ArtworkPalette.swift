import AppKit

/// Colors taken from the artwork: a dark background for compact mode
/// and a vivid accent for the Island.
struct ArtworkPalette: Equatable {
    var background: NSColor
    var accent: NSColor

    static let neutral = ArtworkPalette(
        background: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.21, alpha: 1),
        accent: NSColor(srgbRed: 0.92, green: 0.92, blue: 0.94, alpha: 1)
    )

    /// Average of the artwork scaled to 16 × 16, weighting colorful pixels more:
    /// a black cover with an orange face gives orange, not black.
    static func from(_ image: NSImage) -> ArtworkPalette {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .neutral }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .neutral }

        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            let weight = saturation * maxC + 0.03
            red += r * weight
            green += g * weight
            blue += b * weight
            total += weight
        }
        guard total > 0 else { return .neutral }
        let average = NSColor(srgbRed: red / total, green: green / total, blue: blue / total, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        if saturation < 0.08 {
            return .neutral
        }
        return ArtworkPalette(
            background: NSColor(hue: hue, saturation: min(saturation, 0.42), brightness: 0.25, alpha: 1),
            accent: NSColor(hue: hue, saturation: max(0.45, min(saturation, 0.78)), brightness: 0.9, alpha: 1)
        )
    }
}
