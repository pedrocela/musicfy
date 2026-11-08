import SwiftUI

/// Modo tapa (320 × 320): sólo la tapa; al pasar el mouse aparecen los controles
/// sobre un vidrio que difumina la mitad de abajo.
struct ArtworkModeView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    private var showControls: Bool { panel.isHovering || panel.volumeOpen }

    var body: some View {
        ZStack {
            CrossfadingArtwork(player: player)
            if player.lyricsVisible {
                LyricsOverlay(player: player, topInset: 52, bottomInset: showControls ? 150 : 16)
                    .transition(.opacity)
            }
            WindowDragArea(onDoubleClick: panel.actions.toggleArtworkCompact)
            if showControls {
                controls
                    .transition(.opacity)
            }
        }
        .animation(Theme.fade, value: showControls)
        .animation(Theme.smooth, value: player.lyricsVisible)
    }

    private var controls: some View {
        ZStack {
            scrims
            VStack(spacing: 0) {
                HStack {
                    if let kind = player.state?.source {
                        SourceChip(kind: kind)
                    }
                    Spacer(minLength: 8)
                    GlassCapsule(player: player, settings: settings, panel: panel)
                }
                .padding([.top, .horizontal], 12)

                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 1) {
                                MarqueeText(text: player.state?.title ?? "", font: Theme.artworkTitle, color: Theme.primary, height: 23)
                                SubtitleLine(player: player, font: Theme.artworkSubtitle, height: 17)
                            }
                            .id(player.state?.trackKey ?? "")
                            .transition(.opacity)
                        }
                        .animation(Theme.crossfade, value: player.state?.trackKey)
                        if player.state?.source.supportsFavorite == true {
                            RoundButton(
                                symbol: player.state?.favorited == true ? "star.fill" : "star",
                                help: "Favorito",
                                action: { player.toggleFavorite() }
                            )
                        }
                        RoundButton(symbol: "ellipsis", help: "Más opciones", action: panel.actions.showMenu)
                    }
                    TimeBar(player: player)
                        .padding(.top, 10)
                    TransportRow(player: player, size: .large)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    /// Vidrio abajo (tapa difuminada que se funde hacia arriba) y una sombra suave arriba
    /// para que el chip y la cápsula se lean sobre cualquier tapa.
    private var scrims: some View {
        ZStack {
            ArtworkFill(image: player.artwork)
                .blur(radius: 22, opaque: true)
                .saturation(1.4)
                .mask(bottomMask)
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.07, green: 0.047, blue: 0.04).opacity(0), location: 0.38),
                    .init(color: Color(red: 0.07, green: 0.047, blue: 0.04).opacity(0.74), location: 0.82),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [Color.black.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.22)
            )
        }
        .allowsHitTesting(false)
    }

    private var bottomMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.38),
                .init(color: .black, location: 0.66),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
