// Draws the Musicfy icon and saves it as an iconset.
// Usage: swift tools/make-icon.swift build/AppIcon.iconset
//
// The idea: a piece of artwork floating over a dark tile, tilted a little and lifted by its
// shadow, with the player's glass strip and progress bar at its foot. Musicfy is the
// artwork that stays on top of everything.
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgba(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func render(_ side: Int) -> Data? {
    let s = CGFloat(side)
    guard let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    // Top-left origin, y down, so the numbers read like the layout.
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)
    let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns

    // macOS icon grid: an 824 pt rounded square inside 1024.
    let inset = s * 0.098
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let w = tile.width
    let tilePath = rounded(tile, w * 0.225)

    // Tile and its drop shadow (shadow offsets are in device space: negative y is down).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgba(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgba(0x0B0B10))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    // Graphite, a touch cooler at the top.
    ctx.drawLinearGradient(
        gradient([(rgba(0x2A2A33), 0), (rgba(0x0C0C10), 1)]),
        start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: []
    )
    // The artwork's color spilling onto the tile.
    let glowCenter = CGPoint(x: s / 2, y: s * 0.62)
    ctx.drawRadialGradient(
        gradient([(rgba(0xFA2D48, 0.38), 0), (rgba(0xFA2D48, 0), 1)]),
        startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: w * 0.6, options: []
    )

    // The floating artwork.
    let cw = w * 0.66
    let card = CGRect(x: (s - cw) / 2, y: tile.minY + w * 0.14, width: cw, height: cw)
    // The cover corner, as Music rounds artwork (and as the player does).
    let cardPath = rounded(card, cw * 0.035)
    ctx.saveGState()
    ctx.translateBy(x: card.midX, y: card.midY)
    ctx.rotate(by: -7 * .pi / 180)
    ctx.translateBy(x: -card.midX, y: -card.midY)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.045), blur: s * 0.08, color: rgba(0x000000, 0.6))
    ctx.addPath(cardPath)
    ctx.setFillColor(rgba(0x000000))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()
    // Sunset: amber, Music's pink, violet.
    ctx.drawLinearGradient(
        gradient([(rgba(0xFF9A3C), 0), (rgba(0xFA2D48), 0.45), (rgba(0x6B2BD9), 1)]),
        start: CGPoint(x: card.minX, y: card.minY), end: CGPoint(x: card.maxX, y: card.maxY), options: []
    )
    let sun = CGPoint(x: card.minX + cw * 0.25, y: card.minY + cw * 0.2)
    ctx.drawRadialGradient(
        gradient([(rgba(0xFFD678, 0.75), 0), (rgba(0xFFD678, 0), 1)]),
        startCenter: sun, startRadius: 0, endCenter: sun, endRadius: cw * 0.6, options: []
    )

    // The note.
    let config = NSImage.SymbolConfiguration(pointSize: cw * 0.42, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let size = note.size
        let center = CGPoint(x: card.midX, y: card.minY + cw * 0.40)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.02, color: rgba(0x500028, 0.35))
        note.draw(
            in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
        )
        ctx.restoreGState()
    }

    // The player's glass strip, with its progress bar.
    let strip = CGRect(x: card.minX, y: card.maxY - cw * 0.24, width: cw, height: cw * 0.24)
    ctx.drawLinearGradient(
        gradient([(rgba(0x140A28, 0.22), 0), (rgba(0x140A28, 0.45), 1)]),
        start: CGPoint(x: 0, y: strip.minY), end: CGPoint(x: 0, y: strip.maxY), options: []
    )
    ctx.setFillColor(rgba(0xFFFFFF, 0.22))
    ctx.fill(CGRect(x: strip.minX, y: strip.minY, width: cw, height: max(1, s * 0.003)))
    let barH = cw * 0.045
    let bar = CGRect(x: card.minX + cw * 0.15, y: strip.midY - barH / 2, width: cw * 0.70, height: barH)
    ctx.addPath(rounded(bar, barH / 2))
    ctx.setFillColor(rgba(0xFFFFFF, 0.32))
    ctx.fillPath()
    ctx.addPath(rounded(CGRect(x: bar.minX, y: bar.minY, width: bar.width * 0.42, height: barH), barH / 2))
    ctx.setFillColor(rgba(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // A rim of light on the artwork, brighter on top.
    ctx.saveGState()
    ctx.addPath(rounded(card.insetBy(dx: s * 0.002, dy: s * 0.002), cw * 0.035))
    ctx.setLineWidth(s * 0.004)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(rgba(0xFFFFFF, 0.5), 0), (rgba(0xFFFFFF, 0.06), 1)]),
        start: CGPoint(x: 0, y: card.minY), end: CGPoint(x: 0, y: card.maxY), options: []
    )
    ctx.restoreGState()
    ctx.restoreGState() // tilt
    ctx.restoreGState() // tile clip

    // Hairline around the tile.
    ctx.addPath(rounded(tile.insetBy(dx: s * 0.001, dy: s * 0.001), w * 0.225))
    ctx.setStrokeColor(rgba(0xFFFFFF, 0.1))
    ctx.setLineWidth(max(1, s * 0.002))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    guard let image = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
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
