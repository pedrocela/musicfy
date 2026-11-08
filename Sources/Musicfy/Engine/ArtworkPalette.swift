import AppKit

/// Colors taken from the artwork: a background for compact mode and the Island, and a
/// vivid accent for the Island. Each comes in a dark and a light version; `backdrop` and
/// `tint` pick the one for the system appearance.
struct ArtworkPalette: Equatable {
    var background: NSColor
    var accent: NSColor
    var lightBackground: NSColor
    var lightAccent: NSColor

    static let neutral = ArtworkPalette(
        background: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.21, alpha: 1),
        accent: NSColor(srgbRed: 0.92, green: 0.92, blue: 0.94, alpha: 1),
        lightBackground: NSColor(srgbRed: 0.94, green: 0.94, blue: 0.95, alpha: 1),
        lightAccent: NSColor(srgbRed: 0.30, green: 0.30, blue: 0.33, alpha: 1)
    )

    /// The background for the current appearance: deep in dark mode, a pale wash of the
    /// same hue in light mode.
    var backdrop: NSColor { Self.adaptive(dark: background, light: lightBackground) }
    /// The accent for the current appearance: bright on dark, deeper on light so it holds
    /// up on the pale background.
    var tint: NSColor { Self.adaptive(dark: accent, light: lightAccent) }

    private static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

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
            accent: NSColor(hue: hue, saturation: max(0.45, min(saturation, 0.78)), brightness: 0.9, alpha: 1),
            lightBackground: NSColor(hue: hue, saturation: min(saturation, 0.42) * 0.28, brightness: 0.95, alpha: 1),
            lightAccent: NSColor(hue: hue, saturation: max(0.55, min(saturation, 0.85)), brightness: 0.62, alpha: 1)
        )
    }
}
