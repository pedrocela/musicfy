import SwiftUI

/// Everything visual that can change without touching the logic: sizes, colors,
/// type and motion. Direction "Glass" (A) plus the Island.
enum Theme {
    // MARK: Sizes (points)
    static let artworkSize = CGSize(width: 320, height: 320)
    /// Artwork mode resizes from its corners and sides; always square.
    static let artworkSideRange: ClosedRange<CGFloat> = 200...640
    static let compactSize = CGSize(width: 320, height: 136)
    static let islandCollapsed = CGSize(width: 300, height: 44)
    static let islandExpanded = CGSize(width: 380, height: 160)
    /// One corner radius for every mode, so artwork, compact and the Island read as one family.
    static let cornerRadius: CGFloat = 16
    /// Thumbnail in the closed Island: 6 pt from the edge, so a concentric 10 pt radius.
    static let islandThumb: CGFloat = 32
    static let islandThumbInset: CGFloat = 6
    static let islandThumbRadius: CGFloat = cornerRadius - islandThumbInset
    /// The Island window leaves room for the shadow around the open pill.
    static let islandShadowMargin: CGFloat = 24
    /// Gap between the menu bar and the Island.
    static let islandTopGap: CGFloat = 8
    /// How far the Island has to be pulled down to become the artwork.
    static let islandPullThreshold: CGFloat = 64
    /// Gap to the screen edge when the Island snaps to a side.
    static let islandSideGap: CGFloat = 12

    /// Height of the lyrics or queue panel that opens below.
    static let drawerHeight: CGFloat = 380

    // MARK: Type
    static let compactTitle = Font.system(size: 14, weight: .semibold)
    static let compactSubtitle = Font.system(size: 12)
    static let islandTitle = Font.system(size: 13, weight: .semibold)
    static let islandSubtitle = Font.system(size: 11)
    static let islandOpenTitle = Font.system(size: 15, weight: .semibold)
    static let lyric = Font.system(size: 21, weight: .bold)

    static let primary = Color.white
    static let secondary = Color.white.opacity(0.72)
    static let tertiary = Color.white.opacity(0.62)
    static let timeColor = Color.white.opacity(0.70)

    // MARK: Bars
    static let barTrack = Color.white.opacity(0.22)
    static let barFill = Color.white.opacity(0.88)
    static let barHeight: CGFloat = 4
    static let barHeightActive: CGFloat = 7

    // MARK: Glass
    static let roundButtonFill = Color.white.opacity(0.2)
    /// Capsules over the artwork: the blurred artwork, a dark veil and a rim of light.
    static let glassTint = Color.black.opacity(0.24)
    static let glassEdgeTop = Color.white.opacity(0.32)
    static let glassEdgeBottom = Color.white.opacity(0.06)
    static let windowStroke = Color.white.opacity(0.12)
    /// Island background: almost black, slightly translucent.
    static let islandFill = Color(red: 0.055, green: 0.047, blue: 0.043).opacity(0.96)
    static let islandStroke = Color.white.opacity(0.09)

    // MARK: Each app's color (the chip's dot)
    static func sourceColor(_ kind: SourceKind) -> Color {
        switch kind {
        case .music: return Color(red: 1.0, green: 0.353, blue: 0.447)
        case .spotify: return Color(red: 0.118, green: 0.843, blue: 0.376)
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
    /// How long the controls stay after the mouse leaves.
    static let hoverExitDelay: TimeInterval = 0.3
}

// MARK: - Artwork mode scale

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private struct ArtworkSideKey: EnvironmentKey {
    static let defaultValue: CGFloat = 320
}

extension EnvironmentValues {
    /// How much the controls grow with the artwork. 1 at the base size.
    var uiScale: CGFloat {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }

    /// Artwork side in points (to line up the capsules' glass with the artwork behind them).
    var artworkSide: CGFloat {
        get { self[ArtworkSideKey.self] }
        set { self[ArtworkSideKey.self] = newValue }
    }
}
