import SwiftUI

/// Window state (not the music's): visible mode, hover, volume open, transitions.
@MainActor
final class PanelModel: ObservableObject {
    /// The mode on screen. It can differ from the one in Settings
    /// (for example, artwork turns into compact while nothing plays).
    @Published var mode: DisplayMode = .artwork
    @Published var isHovering = false
    @Published var volumeOpen = false
    @Published var islandExpanded = false
    /// Panel that opens below the player (artwork and compact), as in Music.
    @Published var drawer: Drawer = .none
    /// Where the Island sticks along the top edge.
    @Published var islandAlignment: IslandAlignment =
        IslandAlignment(rawValue: UserDefaults.standard.string(forKey: "islandAlignment") ?? "") ?? .center {
        didSet { UserDefaults.standard.set(islandAlignment.rawValue, forKey: "islandAlignment") }
    }

    /// Artwork mode side, resized by pulling a corner or side. Remembered.
    @Published var artworkSide: CGFloat = PanelModel.savedArtworkSide {
        didSet { UserDefaults.standard.set(Double(artworkSide), forKey: "artworkSide") }
    }

    /// Compact's width, stretched from its sides (`Theme.compactWidthRange`). Remembered.
    @Published var compactWidth: CGFloat = PanelModel.savedCompactWidth {
        didSet { UserDefaults.standard.set(Double(compactWidth), forKey: "compactWidth") }
    }

    /// While the window morphs to or from the Island.
    @Published var morph: Morph?
    /// The artwork or compact view is being dragged over the Island zone (top center).
    @Published var islandHint = false
    /// The Island is being pulled down: 0 to 1, how close it is to becoming the artwork.
    @Published var islandPull: CGFloat = 0
    /// Compact being stretched into artwork: 0 to 1.
    @Published var grow: CGFloat = 0
    /// Artwork being squashed into compact from its top or bottom edge: 0 to 1.
    @Published var squash: CGFloat = 0
    /// While artwork is resized from a corner or side, the window stays still (big enough for
    /// any size) and the player is drawn at this rect inside it, in window points from the
    /// top left. Resizing the window itself made its content trail a frame behind and wobble.
    @Published var liveRect: CGRect?
    /// Which controls artwork mode shows right now (the "…" menu lists the hidden ones).
    @Published var artworkDensity: ArtworkDensity = .normal

    var actions = PanelActions()

    private static var savedCompactWidth: CGFloat {
        let saved = CGFloat(UserDefaults.standard.double(forKey: "compactWidth"))
        let range = Theme.compactWidthRange
        return min(max(saved, range.lowerBound), range.upperBound)
    }

    private static var savedArtworkSide: CGFloat {
        let saved = UserDefaults.standard.double(forKey: "artworkSide")
        let side = saved > 0 ? CGFloat(saved) : Theme.artworkSize.width
        return min(max(side, Theme.artworkSideRange.lowerBound), Theme.artworkSideRange.upperBound)
    }
}

/// What the morph starts from (or ends in) on the panel side.
enum MorphLook: Equatable {
    case artwork, compact
}

/// 0 is the panel (artwork or compact), 1 is the closed Island.
struct Morph: Equatable {
    var look: MorphLook
    var progress: CGFloat
}

enum IslandAlignment: String {
    case leading, center, trailing

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

enum Drawer: Equatable {
    case none, lyrics, queue
}

/// What the UI asks of the app; the AppDelegate handles it.
struct PanelActions {
    var setMode: (DisplayMode) -> Void = { _ in }
    var toggleArtworkCompact: () -> Void = {}
    var hide: () -> Void = {}
    var showMenu: () -> Void = {}
    var showOutputMenu: () -> Void = {}
}
