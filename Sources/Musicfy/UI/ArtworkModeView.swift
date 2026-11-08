import SwiftUI

/// Artwork mode: just the artwork; on hover the controls appear over glass made from
/// the artwork itself, progressively blurred toward the bottom (as in Music).
/// Resizes from its corners and sides; its measures follow the side (`ArtworkMetrics`) and
/// it shows more controls as it grows (`ArtworkDensity`).
struct ArtworkModeView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    private var showControls: Bool { panel.isHovering || panel.volumeOpen }
    /// Which controls show; steps with the size, with a little hysteresis.
    @State private var density = ArtworkDensity.normal

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let metrics = ArtworkMetrics(side: side)
            ZStack {
                CrossfadingArtwork(player: player)
                if showControls {
                    glass
                        .transition(.opacity)
                }
                WindowDragArea(onDoubleClick: panel.actions.toggleArtworkCompact)
                if showControls {
                    controls(metrics)
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: ArtworkSpace.name)
            // Every measure comes from the metrics; nothing else scales on top.
            .environment(\.uiScale, 1)
            .environment(\.artworkMetrics, metrics)
            .environment(\.artworkSide, side)
            .onAppear { updateDensity(for: side, animated: false) }
            .onChange(of: side) { _, value in updateDensity(for: value, animated: true) }
        }
        .animation(Theme.fade, value: showControls)
    }

    private func updateDensity(for side: CGFloat, animated: Bool) {
        let next = density.next(for: side)
        guard next != density || panel.artworkDensity != next else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) { density = next }
        } else {
            density = next
        }
        panel.artworkDensity = next
    }

    private func controls(_ m: ArtworkMetrics) -> some View {
        VStack(spacing: 0) {
            // The glyph sits 12 from the edges, the capsule 10 from the top and right.
            HStack(alignment: .top) {
                if let kind = player.state?.source {
                    SourceChip(kind: kind, player: player)
                        .padding(.top, 2)
                }
                Spacer(minLength: 8)
                if hasTopButtons {
                    GlassCapsule(player: player, settings: settings, panel: panel, density: density)
                }
            }
            .padding(.top, 10)
            .padding(.leading, 12)
            .padding(.trailing, 10)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 1) {
                            MarqueeText(
                                text: player.state?.title ?? "",
                                font: .system(size: m.title, weight: .semibold),
                                color: Theme.primary,
                                height: (m.title * 1.25).rounded()
                            )
                            SubtitleLine(player: player, font: .system(size: m.artist), height: (m.artist * 1.3).rounded())
                        }
                        .id(player.state?.trackKey ?? "")
                        .transition(.opacity)
                    }
                    .animation(Theme.crossfade, value: player.state?.trackKey)
                    if density == .large, player.state?.source.supportsFavorite == true {
                        RoundButton(
                            symbol: player.state?.favorited == true ? "star.fill" : "star",
                            diameter: m.moreButton,
                            help: "Favorite",
                            action: { player.toggleFavorite() }
                        )
                        .transition(.opacity)
                    }
                    RoundButton(symbol: "ellipsis", diameter: m.moreButton, help: "More Options", action: panel.actions.showMenu)
                }
                TimeBar(player: player, stacked: true, timeSize: m.time)
                    .padding(.top, 8 * m.ratio)
                // Small: previous, play and next, centered. Shuffle and repeat from normal up.
                TransportRow(player: player, showsModes: density >= .normal, metrics: m)
                    .padding(.top, 1)
            }
            .padding(.horizontal, m.sideMargin)
            .padding(.bottom, m.bottomMargin)
            // A whisper of shadow so white text holds up on very light artwork.
            .shadow(color: .black.opacity(0.16), radius: 5, y: 1)
        }
    }

    /// Whether the capsule at the top right would hold anything at this size.
    private var hasTopButtons: Bool {
        if density == .large || panel.volumeOpen { return true }
        if settings.showLyricsButton || settings.showQueueButton { return true }
        return density >= .normal && (settings.showOutput || settings.showVolume)
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
                // The veil covers the bottom 64 % of the side.
                stops: [
                    .init(color: .black.opacity(0), location: 0.36),
                    .init(color: .black.opacity(0.14), location: 0.64),
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
