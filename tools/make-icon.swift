// Draws the Musicfy icon and saves it as an iconset.
// Usage: swift tools/make-icon.swift build/AppIcon.iconset
//
// The tile is tinted edge to edge with a diagonal blend of Music's pink, Podcasts' violet
// and Spotify's green. On it floats a cover of frosted glass (the same colors, blurred
// through it) with the white note: the menu bar glyph, made of the player's glass.
import AppKit
import CoreImage

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let pink: UInt32 = 0xFA2D48
let violet: UInt32 = 0x872EC4
let green: UInt32 = 0x1ED760

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

/// A context with the origin at the top left and y going down, so the numbers read like the layout.
func makeContext(_ side: Int) -> CGContext? {
    guard let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.translateBy(x: 0, y: CGFloat(side))
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

/// The colors, edge to edge: pink to violet to green from corner to corner, a little more
/// pink at the top right and violet at the bottom left so no corner is flat, and a sheen
/// that lights the top and settles the bottom.
func drawColors(_ ctx: CGContext, _ s: CGFloat) {
    ctx.drawLinearGradient(
        gradient([(rgba(pink), 0), (rgba(violet), 0.5), (rgba(green), 1)]),
        start: CGPoint(x: s * 0.117, y: s * 0.117), end: CGPoint(x: s * 0.883, y: s * 0.883),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    for (x, y, color, alpha) in [(0.85, 0.15, pink, 0.35), (0.15, 0.85, violet, 0.5)] {
        let center = CGPoint(x: s * CGFloat(x), y: s * CGFloat(y))
        ctx.drawRadialGradient(
            gradient([(rgba(color, CGFloat(alpha)), 0), (rgba(color, 0), 1)]),
            startCenter: center, startRadius: 0, endCenter: center, endRadius: s * 0.5, options: []
        )
    }
    ctx.drawLinearGradient(
        gradient([(rgba(0xFFFFFF, 0.10), 0), (rgba(0xFFFFFF, 0), 0.5), (rgba(0x000000, 0.15), 1)]),
        start: CGPoint(x: 0, y: s * 0.078), end: CGPoint(x: 0, y: s * 0.918), options: []
    )
}

/// Draws a full-size image made in a top-left context back into one.
func drawFull(_ image: CGImage, in ctx: CGContext, _ s: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: s, height: s))
    ctx.restoreGState()
}

func render(_ side: Int) -> Data? {
    let s = CGFloat(side)
    guard let ctx = makeContext(side), let colorsCtx = makeContext(side) else { return nil }

    // The colors once, and blurred for the glass.
    drawColors(colorsCtx, s)
    guard let colors = colorsCtx.makeImage() else { return nil }
    let blurred: CGImage = {
        let input = CIImage(cgImage: colors)
        let out = input.clampedToExtent().applyingGaussianBlur(sigma: Double(s * 0.035)).cropped(to: input.extent)
        return CIContext(options: [.workingColorSpace: sRGB]).createCGImage(out, from: input.extent) ?? colors
    }()

    // macOS icon grid: an 824 pt rounded square inside 1024.
    let inset = s * 0.098
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = rounded(tile, tile.width * 0.225)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgba(0x000000, 0.3))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgba(0x000000))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    drawFull(colors, in: ctx, s)

    // The glass cover.
    let coverSide = s * 0.5
    let cover = CGRect(x: (s - coverSide) / 2, y: (s - coverSide) / 2, width: coverSide, height: coverSide)
    let coverPath = rounded(cover, coverSide * 0.2)

    ctx.saveGState() // lift
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.055, color: rgba(0x000000, 0.4))
    ctx.addPath(coverPath)
    ctx.setFillColor(rgba(0x141418, 0.35))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState() // frost
    ctx.addPath(coverPath)
    ctx.clip()
    drawFull(blurred, in: ctx, s)
    ctx.setFillColor(rgba(0xFFFFFF, 0.10))
    ctx.fill(cover)
    ctx.drawLinearGradient(
        gradient([(rgba(0xFFFFFF, 0.16), 0), (rgba(0xFFFFFF, 0), 0.45)]),
        start: CGPoint(x: 0, y: cover.minY), end: CGPoint(x: 0, y: cover.maxY), options: []
    )
    ctx.restoreGState()

    ctx.saveGState() // rim of light, brighter on top
    ctx.addPath(rounded(cover.insetBy(dx: s * 0.0025, dy: s * 0.0025), coverSide * 0.2))
    ctx.setLineWidth(max(1, s * 0.005))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([(rgba(0xFFFFFF, 0.55), 0), (rgba(0xFFFFFF, 0.08), 1)]),
        start: CGPoint(x: 0, y: cover.minY), end: CGPoint(x: 0, y: cover.maxY), options: []
    )
    ctx.restoreGState()

    // The note: SF Symbols' own, white, with a soft shadow that stays under it.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    let config = NSImage.SymbolConfiguration(pointSize: coverSide * 0.5, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let size = note.size
        let rect = NSRect(x: cover.midX - size.width / 2, y: cover.midY - size.height / 2, width: size.width, height: size.height)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: s * 0.02, color: rgba(0x000000, 0.18))
        note.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        ctx.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState() // tile clip

    // Hairline around the tile.
    ctx.addPath(rounded(tile.insetBy(dx: s * 0.001, dy: s * 0.001), tile.width * 0.225))
    ctx.setStrokeColor(rgba(0xFFFFFF, 0.12))
    ctx.setLineWidth(max(1, s * 0.002))
    ctx.strokePath()

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
