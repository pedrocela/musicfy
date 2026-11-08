import SwiftUI

/// Artwork mode: just the artwork; on hover the controls appear over glass made from
/// the artwork itself, progressively blurred toward the bottom (as in Music).
/// Resizes from its corners and sides; the controls grow with it, a little slower.
struct ArtworkModeView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    private var showControls: Bool { panel.isHovering || panel.volumeOpen }

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            // Controls grow with the square root of the size: at 640 pt they are 41 % larger, not twice.
            let scale = (max(side, 1) / Theme.artworkSize.width).squareRoot()
            let density = ArtworkDensity(side: side)
            ZStack {
                CrossfadingArtwork(player: player)
                if showControls {
                    glass
                        .transition(.opacity)
                }
                WindowDragArea(onDoubleClick: panel.actions.toggleArtworkCompact)
                if showControls {
                    controls(scale: scale, density: density)
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: ArtworkSpace.name)
            .environment(\.uiScale, scale)
            .environment(\.artworkSide, side)
        }
        .animation(Theme.fade, value: showControls)
    }

    private func controls(scale s: CGFloat, density: ArtworkDensity) -> some View {
        VStack(spacing: 0) {
            HStack {
                if let kind = player.state?.source {
                    SourceChip(kind: kind, player: player)
                }
                Spacer(minLength: 8)
                if hasTopButtons(density) {
                    GlassCapsule(player: player, settings: settings, panel: panel, density: density)
                }
            }
            .padding([.top, .horizontal], (density == .minimal ? 10 : 12) * s)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                HStack(spacing: 8 * s) {
                    ZStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 1 * s) {
                            MarqueeText(
                                text: player.state?.title ?? "",
                                font: .system(size: 17 * s, weight: .semibold),
                                color: Theme.primary,
                                height: 22 * s
                            )
                            SubtitleLine(player: player, font: .system(size: 13 * s), height: 17 * s)
                        }
                        .id(player.state?.trackKey ?? "")
                        .transition(.opacity)
                    }
                    .animation(Theme.crossfade, value: player.state?.trackKey)
                    if density == .full, player.state?.source.supportsFavorite == true {
                        RoundButton(
                            symbol: player.state?.favorited == true ? "star.fill" : "star",
                            help: "Favorite",
                            action: { player.toggleFavorite() }
                        )
                    }
                    RoundButton(symbol: "ellipsis", help: "More Options", action: panel.actions.showMenu)
                }
                TimeBar(player: player, stacked: true, timesOnHover: density == .minimal)
                    .padding(.top, 8 * s)
                TransportRow(player: player, size: .large)
                    .padding(.top, 1 * s)
            }
            .padding(.horizontal, (density == .minimal ? 14 : 18) * s)
            .padding(.bottom, 6 * s)
            // A whisper of shadow so white text holds up on very light artwork.
            .shadow(color: .black.opacity(0.16), radius: 5, y: 1)
        }
    }

    /// Whether the capsule at the top right would hold anything at this size.
    private func hasTopButtons(_ density: ArtworkDensity) -> Bool {
        if density == .full || panel.volumeOpen { return true }
        return settings.showLyricsButton || settings.showVolume
            || (density == .reduced && settings.showQueueButton)
    }

    /// Under the controls: the progressively blurred artwork (computed once per artwork)
    /// and a veil that darkens toward the bottom so white reads on light artwork.
    private var glass: some View {
        ZStack {
            ZStack {
                if let glass = player.glass {
                    ArtworkFill(image: glass.progressive)
                        .transition(.opacity)
                } else {
                    // While it computes: a plain blur.
                    ArtworkFill(image: player.artwork)
                        .blur(radius: 24, opaque: true)
                        .mask(fallbackMask)
                        .transition(.opacity)
                }
            }
            .id(player.artworkToken)
            .animation(Theme.fade, value: player.glass == nil)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.48),
                    .init(color: .black.opacity(0.14), location: 0.70),
                    .init(color: .black.opacity(0.34), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    private var fallbackMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.56),
                .init(color: .black, location: 0.76),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
