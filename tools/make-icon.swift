// Draws the Musicfy icon and saves it as an iconset.
// Usage: swift tools/make-icon.swift build/AppIcon.iconset
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func render(_ side: Int) -> Data? {
    let size = CGFloat(side)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon shape: rounded square with margin.
    let inset = size * 0.098
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    NSColor(srgbRed: 0.07, green: 0.05, blue: 0.04, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Warm glow, like lit artwork.
    NSGraphicsContext.current?.saveGraphicsState()
    shape.addClip()
    let glow = NSGradient(colors: [
        NSColor(srgbRed: 0.82, green: 0.39, blue: 0.18, alpha: 1),
        NSColor(srgbRed: 0.54, green: 0.21, blue: 0.09, alpha: 1),
        NSColor(srgbRed: 0.16, green: 0.08, blue: 0.06, alpha: 1),
        NSColor(srgbRed: 0.07, green: 0.05, blue: 0.04, alpha: 1),
    ], atLocations: [0, 0.38, 0.72, 1], colorSpace: .sRGB)
    glow?.draw(in: shape, relativeCenterPosition: NSPoint(x: 0, y: 0.25))

    // Glass at the bottom, as in the player.
    let glass = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.36)
    NSGradient(colors: [
        NSColor.black.withAlphaComponent(0.0),
        NSColor.black.withAlphaComponent(0.45),
    ])?.draw(in: glass, angle: -90)

    // Progress bar.
    let barY = rect.minY + rect.height * 0.17
    let barX = rect.minX + rect.width * 0.16
    let barW = rect.width * 0.68
    let barH = size * 0.022
    NSColor.white.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barW, height: barH), xRadius: barH / 2, yRadius: barH / 2).fill()
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barW * 0.38, height: barH), xRadius: barH / 2, yRadius: barH / 2).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Music note.
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.36, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let noteSize = note.size
        let origin = NSPoint(x: (size - noteSize.width) / 2, y: rect.minY + rect.height * 0.36)
        note.draw(in: NSRect(origin: origin, size: noteSize))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        if let data = render(base * scale) {
            try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
        }
    }
}
print("Icon ready at \(output)")
