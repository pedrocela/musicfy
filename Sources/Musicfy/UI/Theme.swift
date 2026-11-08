import AppKit
import SwiftUI

/// Everything visual that can change without touching the logic: sizes, colors,
/// type and motion. Direction "Glass" (A) plus the Island.
enum Theme {
    // MARK: Sizes (points)
    static let artworkSize = CGSize(width: 320, height: 320)
    /// Artwork mode resizes from its corners and sides; always square.
    static let artworkSideRange: ClosedRange<CGFloat> = 100...640
    /// From this side up, pushing the top or bottom edge in turns artwork into compact,
    /// and stretching compact never gives a smaller artwork. Below it is the mini artwork.
    static let artworkMiniBreak: CGFloat = 200
    /// Artwork mode adds controls at these sides and drops them 8 pt below (`ArtworkDensity`).
    static let artworkTierBreaks: [CGFloat] = [200, 300, 380]
    static let artworkTierHysteresis: CGFloat = 8
    /// The sides where the small, normal and large measures apply (`ArtworkMetrics`).
    static let artworkReferenceSides: (CGFloat, CGFloat, CGFloat) = (260, 320, 420)
    static let compactSize = CGSize(width: 320, height: 136)
    /// Compact stretches sideways up to 30 % wider. Pulled narrower than its minimum,
    /// it turns into artwork once the pull passes `compactShrinkToArtwork`.
    static let compactWidthRange: ClosedRange<CGFloat> = 320...416
    static let compactShrinkToArtwork: CGFloat = 90
    /// Compact's cover fills the height, 16 pt from every edge it touches.
    static let compactInset: CGFloat = 16
    static var compactArtSide: CGFloat { compactSize.height - compactInset * 2 }
    static let compactArtRadius: CGFloat = 5
    static let islandCollapsed = CGSize(width: 300, height: 44)
    /// The open Island is compact on hover at its widest: same layout, 416 × 136.
    static let islandExpanded = CGSize(width: compactWidthRange.upperBound, height: compactSize.height)
    /// One corner radius for every mode, the soft corner of an album cover (as Music
    /// rounds artwork), so artwork, compact and the Island read as one family: covers.
    static let cornerRadius: CGFloat = 6
    /// Artwork thumbnails (compact, open Island, empty cover): the same cover corner, scaled down.
    static let thumbRadius: CGFloat = 4
    /// Thumbnail in the closed Island, 6 pt from the edge.
    static let islandThumb: CGFloat = 32
    static let islandThumbInset: CGFloat = 6
    static let islandThumbRadius: CGFloat = 3
    /// The Island window leaves room for the shadow all around the open pill, more below
    /// (the shadow falls a little) and less above. The top margin reaches up behind the gap
    /// under the menu bar, so the pill stays where it was. Keep the shadow's blur + offset
    /// inside these, or it's cut off square: a SwiftUI shadow fades out about 2 × its radius
    /// from the shape.
    static let islandShadowSide: CGFloat = 56
    static let islandShadowTop: CGFloat = 36
    static let islandShadowBottom: CGFloat = 68
    /// Gap between the menu bar and the Island.
    static let islandTopGap: CGFloat = 8
    /// Dragging the player to the top: it's armed to become the Island when its center is
    /// within this distance of the screen's center and its top this close to the top edge.
    static let islandSnapWidth: CGFloat = 180
    static let islandSnapDepth: CGFloat = 80
    /// How far the Island has to be pulled down to become the artwork.
    static let islandPullThreshold: CGFloat = 64
    /// The player never goes closer than this to the screen's edges.
    static let screenMargin: CGFloat = 4
    /// Gap to the screen edge when the Island snaps to a side.
    static let islandSideGap: CGFloat = 12

    /// Height of the lyrics or queue panel that opens below.
    static let drawerHeight: CGFloat = 380

    // MARK: Type
    static let compactTitle = Font.system(size: 15, weight: .semibold)
    static let compactSubtitle = Font.system(size: 12)
    static let islandTitle = Font.system(size: 13, weight: .semibold)
    static let islandSubtitle = Font.system(size: 11)
    static let islandOpenTitle = Font.system(size: 15, weight: .semibold)
    static let lyric = Font.system(size: 21, weight: .bold)

    // MARK: Light and dark
    // Colors follow the system appearance, as Music's mini player does. Each token is one
    // NSColor that resolves per appearance, so SwiftUI picks the right one from the
    // environment's color scheme. Artwork mode keeps its text white over the artwork
    // (it sets `.dark` for its controls) and only its glass turns light.

    /// A color with one value in dark mode and another in light mode.
    static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func white(_ alpha: CGFloat) -> NSColor { NSColor(white: 1, alpha: alpha) }
    private static func black(_ alpha: CGFloat) -> NSColor { NSColor(white: 0, alpha: alpha) }

    /// The ink of text and glyphs: white in dark mode, near black in light mode.
    /// Use with `.opacity` for the quieter shades of lines, fills and rims.
    static let ink = adaptive(dark: white(1), light: black(1))
    /// The opposite of `ink`: the paper it's written on.
    static let paper = adaptive(dark: black(1), light: white(1))

    static let primary = adaptive(dark: white(1), light: black(0.86))
    static let secondary = adaptive(dark: white(0.72), light: black(0.56))
    static let tertiary = adaptive(dark: white(0.62), light: black(0.46))
    static let quaternary = adaptive(dark: white(0.55), light: black(0.42))
    static let timeColor = adaptive(dark: white(0.70), light: black(0.50))

    // MARK: Bars
    static let barTrack = adaptive(dark: white(0.22), light: black(0.12))
    static let barFill = adaptive(dark: white(0.88), light: black(0.58))
    static let barHeight: CGFloat = 4
    static let barHeightActive: CGFloat = 7

    // MARK: Glass
    /// Star and "…" over the artwork; a lighter disc in light mode, as in Music.
    static let roundButtonFill = Color.white.opacity(0.2)
    static let roundButtonFillLight = Color.white.opacity(0.32)
    /// The chip under an active toggle (shuffle, repeat).
    static let toggleChip = adaptive(dark: white(0.22), light: black(0.08))
    /// Capsules over the artwork: the blurred artwork, a veil and a rim of light.
    /// Dark mode: a dark veil and white glyphs. Light mode: milky glass and dark glyphs.
    static let glassTint = adaptive(dark: black(0.24), light: white(0.52))
    static let glassEdgeTop = adaptive(dark: white(0.32), light: white(0.85))
    static let glassEdgeBottom = adaptive(dark: white(0.06), light: white(0.30))
    /// The top capsule: system material plus this veil, a rim and a hairline between groups.
    static let capsuleVeil = adaptive(dark: black(0.42), light: white(0.46))
    static let capsuleStroke = adaptive(dark: white(0.18), light: white(0.70))
    static let capsuleDivider = adaptive(dark: white(0.16), light: black(0.12))
    static let capsuleShadow = adaptive(dark: black(0.25), light: black(0.16))
    /// Its buttons: at rest, on hover or pressed, and the pill of an active one.
    static let capsuleIcon = adaptive(dark: white(0.85), light: black(0.72))
    static let capsuleIconHover = adaptive(dark: white(1), light: black(0.9))
    static let capsuleHover = adaptive(dark: white(0.12), light: black(0.06))
    static let capsulePressed = adaptive(dark: white(0.18), light: black(0.11))
    static let capsuleActive = adaptive(dark: white(1), light: black(0.80))
    static let capsuleActiveIcon = adaptive(
        dark: NSColor(srgbRed: 0.102, green: 0.078, blue: 0.071, alpha: 1), // #1A1412
        light: white(1)
    )
    static let windowStroke = adaptive(dark: white(0.12), light: black(0.10))
    static let islandStroke = adaptive(dark: white(0.09), light: black(0.05))
    /// The open Island's shadow, soft like a macOS window's: a wide ambient haze that shows
    /// on every side, a closer one that gives it depth and a faint contact line. Lighter in
    /// light mode, as the system's own window shadows are.
    static let islandShadowAmbient = adaptive(dark: black(0.42), light: black(0.20))
    static let islandShadowNear = adaptive(dark: black(0.20), light: black(0.08))
    static let islandShadowContact = adaptive(dark: black(0.30), light: black(0.05))
    /// The sheen at the top of compact and the Island.
    static let sheen = adaptive(dark: white(0.07), light: white(0.40))
    /// The rim around covers and thumbnails.
    static let coverStroke = adaptive(dark: white(0.12), light: black(0.08))
    /// The shadow under covers in compact.
    static let coverShadow = adaptive(dark: black(0.30), light: black(0.16))
    /// Hairlines between rows and above the panel below.
    static let separator = adaptive(dark: white(0.08), light: black(0.08))
    /// A faint wash behind the lyrics and Up Next panel.
    static let drawerWash = adaptive(dark: black(0.10), light: white(0.20))

    // MARK: Each app's color (the source glyph)
    static func sourceColor(_ kind: SourceKind) -> Color {
        switch kind {
        case .music: return Color(red: 0.980, green: 0.176, blue: 0.282) // #FA2D48
        case .spotify: return Color(red: 0.118, green: 0.843, blue: 0.376) // #1ED760
        case .podcasts: return Color(red: 0.698, green: 0.345, blue: 0.937) // #B258EF
        }
    }

    // MARK: Motion
    /// Mode changes, the volume capsule, opening the Island.
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Showing and hiding controls on hover.
    static let fade = Animation.easeInOut(duration: 0.22)
    /// Artwork, title and color changes between songs.
    static let crossfade = Animation.easeInOut(duration: 0.55)
    /// Button press response.
    static let press = Animation.spring(response: 0.24, dampingFraction: 0.62)
    /// Window resize duration (AppKit), with a soft ease-out curve.
    static let resizeDuration: TimeInterval = 0.4
    /// Morph to and from the Island. The SwiftUI side uses the same curve as the window frame.
    static let morphDuration: TimeInterval = 0.52
    static let morph = Animation.timingCurve(0.22, 1, 0.36, 1, duration: morphDuration)
    /// The Island opens after the pointer rests this long, and closes this long after it leaves.
    static let islandOpenDelay: TimeInterval = 0.06
    static let islandCloseDelay: TimeInterval = 0.2
    /// Opening and closing the Island: quicker than the mode changes.
    static let islandSpring = Animation.spring(response: 0.3, dampingFraction: 0.84)
    /// The Island's content fades in just behind the shape.
    static let islandContentIn = Animation.easeOut(duration: 0.16).delay(0.04)
    /// How long the controls stay after the mouse leaves.
    static let hoverExitDelay: TimeInterval = 0.3
    /// Paused this long, the player fades to `pausedAlpha` (full again on hover).
    static let pausedFadeDelay: TimeInterval = 10
    static let pausedAlpha: CGFloat = 0.5
}

// MARK: - Artwork mode sizes

/// Which controls artwork mode shows, by size. What's hidden stays in the "…" menu.
enum ArtworkDensity: Int, Comparable {
    /// Under 200: just the artwork; on hover, only play/pause.
    case mini
    /// 200 to 299: Lyrics and Up Next up top; previous, play and next below.
    case small
    /// 300 to 379: plus Audio Output and Volume up top, shuffle and repeat below.
    case normal
    /// 380 and up: plus the Compact button.
    case large

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// The tier for a side, given the current one: it steps up at 200, 300 and 380, and
    /// back down only under 192, 292 and 372, so it doesn't flicker at a boundary.
    func next(for side: CGFloat) -> ArtworkDensity {
        let up = Theme.artworkTierBreaks
        let down = up.map { $0 - Theme.artworkTierHysteresis }
        var tier = self
        while tier < .large, side >= up[tier.rawValue] { tier = ArtworkDensity(rawValue: tier.rawValue + 1)! }
        while tier > .mini, side < down[tier.rawValue - 1] { tier = ArtworkDensity(rawValue: tier.rawValue - 1)! }
        return tier
    }

    init(side: CGFloat) {
        self = ArtworkDensity.mini.next(for: side)
    }
}

/// Sizes in artwork mode, interpolated in a straight line with the side between three
/// reference points (260, 320, 420), so nothing jumps while resizing.
struct ArtworkMetrics: Equatable {
    let side: CGFloat

    private func value(_ small: CGFloat, _ normal: CGFloat, _ large: CGFloat) -> CGFloat {
        let (a, b, c) = (Theme.artworkReferenceSides.0, Theme.artworkReferenceSides.1, Theme.artworkReferenceSides.2)
        if side <= a { return small }
        if side <= b { return small + (normal - small) * (side - a) / (b - a) }
        if side <= c { return normal + (large - normal) * (side - b) / (c - b) }
        return large
    }

    var sideMargin: CGFloat { value(14, 16, 20) }
    var bottomMargin: CGFloat { value(10, 12, 16) }
    var capsuleHeight: CGFloat { value(26, 30, 32) }
    var buttonWidth: CGFloat { value(24, 28, 30) }
    var buttonHeight: CGFloat { value(20, 24, 26) }
    var buttonIcon: CGFloat { value(12, 13, 14) }
    var glyphCircle: CGFloat { value(26, 28, 30) }
    var glyph: CGFloat { value(14, 16, 17) }
    var title: CGFloat { value(15, 18, 22) }
    var artist: CGFloat { value(12, 13, 15) }
    var moreButton: CGFloat { value(24, 28, 30) }
    var time: CGFloat { value(10, 11, 12) }
    var transportHeight: CGFloat { value(34, 40, 46) }
    var play: CGFloat { value(22, 26, 30) }
    var skip: CGFloat { value(20, 24, 28) }
    var shuffle: CGFloat { value(15, 15, 17) }
    /// Ratio to the normal size, for the few things without their own measure.
    var ratio: CGFloat { capsuleHeight / 30 }
}

// MARK: - Artwork mode scale

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private struct ArtworkMetricsKey: EnvironmentKey {
    static let defaultValue = ArtworkMetrics(side: 320)
}

private struct ArtworkSideKey: EnvironmentKey {
    static let defaultValue: CGFloat = 320
}

private struct MarqueeOnLayerKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Scrolling text runs on Core Animation (compact and the Island, which are always on
    /// screen). Off in artwork mode: its controls carry a SwiftUI shadow, which a layer
    /// wouldn't get.
    var marqueeOnLayer: Bool {
        get { self[MarqueeOnLayerKey.self] }
        set { self[MarqueeOnLayerKey.self] = newValue }
    }

    /// How much the controls grow with the artwork. 1 at the base size.
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }

    /// Artwork mode's measures for its current side.
    var artworkMetrics: ArtworkMetrics {
        get { self[ArtworkMetricsKey.self] }
        set { self[ArtworkMetricsKey.self] = newValue }
    }

    /// Artwork side in points (to line up the capsules' glass with the artwork behind them).
    var artworkSide: CGFloat {
        get { self[ArtworkSideKey.self] }
        set { self[ArtworkSideKey.self] = newValue }
    }
}
