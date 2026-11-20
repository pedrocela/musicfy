import SwiftUI

/// Picks the view for the mode and frames it (corners, border, permissions).
struct RootView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    var body: some View {
        ZStack {
            if let morph = panel.morph {
                MorphView(player: player, look: morph.look, progress: morph.progress)
                    .transition(.opacity)
            } else if panel.mode == .island {
                IslandView(player: player, settings: settings, panel: panel)
                    .transition(.opacity)
            } else {
                framed
                    // Dragged to the top center: it shrinks a little toward the top, hinting at the Island.
                    .scaleEffect(panel.islandHint ? 0.94 : 1, anchor: .top)
                    .opacity(panel.islandHint ? 0.85 : 1)
                    // During a live resize, drawn at its rect inside the still window.
                    .frame(width: panel.liveRect?.width, height: panel.liveRect?.height)
                    .offset(x: panel.liveRect?.minX ?? 0, y: panel.liveRect?.minY ?? 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
            }
        }
    }

    /// The player's height, read from the window itself rather than from the model: while
    /// resizing, the window changes before SwiftUI sees the new side, and a stale height
    /// made the artwork jump inside the window.
    private func baseHeight(in size: CGSize) -> CGFloat {
        guard panel.mode == .artwork else { return Theme.compactSize.height }
        // Squashed into compact with a panel open below: the panel keeps its height.
        if panel.squash > 0, panel.drawer != .none {
            return panel.artworkSide + (Theme.compactSize.height - panel.artworkSide) * panel.squash
        }
        // Square; shorter only while being squashed into compact. A panel below adds height.
        return min(size.width, size.height)
    }

    private var framed: some View {
        GeometryReader { geo in
            framedContent(baseHeight: baseHeight(in: geo.size))
        }
    }

    private func framedContent(baseHeight: CGFloat) -> some View {
        let radius = min(Theme.cornerRadius, baseHeight / 2)
        return ZStack {
            VisualEffectBackground(cornerRadius: radius)
            VStack(spacing: 0) {
                content
                    .frame(height: baseHeight)
                if panel.drawer != .none {
                    drawer
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            stretchPreview
            VStack {
                Spacer()
                PermissionBanner(player: player)
                    .padding(.bottom, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.windowStroke, lineWidth: 0.5)
        )
        .animation(Theme.smooth, value: panel.mode)
        .animation(Theme.smooth, value: panel.drawer)
        .animation(Theme.smooth, value: player.state == nil)
        .animation(Theme.smooth, value: player.problem)
    }

    /// While stretching compact into artwork (or squashing artwork into compact), the
    /// destination fades in over the window so the release lands on what was already there.
    @ViewBuilder
    private var stretchPreview: some View {
        if panel.mode == .compact, panel.grow > 0 {
            ArtworkFill(image: player.artwork)
                .opacity(Double(panel.grow))
                .padding(.bottom, panel.drawer == .none ? 0 : Theme.drawerHeight) // not over the panel below
                .allowsHitTesting(false)
        } else if panel.mode == .artwork, panel.squash > 0 {
            VStack(spacing: 0) {
                CompactModeView(player: player, settings: settings, panel: panel)
                    .frame(height: Theme.compactSize.height)
                Spacer(minLength: 0)
            }
            .opacity(Double(panel.squash))
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var content: some View {
        if player.state == nil {
            ZStack {
                WindowDragArea(onDoubleClick: panel.actions.toggleArtworkCompact)
                EmptyStateView(player: player)
            }
            .transition(.opacity)
        } else if panel.mode == .artwork {
            ArtworkModeView(player: player, settings: settings, panel: panel)
                .transition(.opacity)
        } else {
            CompactModeView(player: player, settings: settings, panel: panel)
                .transition(.opacity)
        }
    }

    /// Lyrics or queue, below the player.
    private var drawer: some View {
        ZStack {
            Theme.drawerWash
            WindowDragArea(onDoubleClick: { panel.drawer = .none })
            switch panel.drawer {
            case .lyrics: LyricsPanel(player: player).transition(.opacity)
            case .queue: QueuePanel(player: player).transition(.opacity)
            case .none: EmptyView()
            }
        }
        .frame(height: Theme.drawerHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 0.5)
        }
        .animation(Theme.fade, value: panel.drawer)
    }
}

/// The window halfway between the panel and the Island. It fills the window, whose frame
/// AppKit animates with the same curve. The cover is the background at both ends, so it
/// stays put while the corners and the veil change. At 0 it looks like the panel, at 1
/// like the closed Island.
struct MorphView: View, Animatable {
    @ObservedObject var player: PlayerController
    let look: MorphLook
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let p = max(0, min(1, progress))
            let radius = Theme.radius(for: size)
            ZStack {
                // The cover fills the panel and the Island alike, so it just stays; the
                // Island's veil, darker toward the left, fades in on the way.
                Color(nsColor: player.palette.background)
                ArtworkFill(image: player.artwork)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.84), location: 0),
                        .init(color: .black.opacity(0.5), location: 0.55),
                        .init(color: .black.opacity(0.08), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(look == .compact ? 1 : Double(p))
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.windowStroke, lineWidth: 0.5)
            )
        }
        .allowsHitTesting(false)
    }
}
