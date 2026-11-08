import SwiftUI

/// Modo tapa: sólo la tapa; al pasar el mouse aparecen los controles sobre un
/// vidrio hecho con la misma tapa, difuminada de a poco hacia abajo (como en Music).
/// Se agranda tirando de un borde; los controles crecen con ella, un poco más despacio.
struct ArtworkModeView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    private var showControls: Bool { panel.isHovering || panel.volumeOpen }

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            // Los controles crecen con la raíz cuadrada del tamaño: a 640 pt, un 41 % más grandes, no el doble.
            let scale = (max(side, 1) / Theme.artworkSize.width).squareRoot()
            ZStack {
                CrossfadingArtwork(player: player)
                if showControls {
                    glass
                        .transition(.opacity)
                }
                WindowDragArea(onDoubleClick: panel.actions.toggleArtworkCompact)
                if showControls {
                    controls(scale: scale)
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: ArtworkSpace.name)
            .environment(\.uiScale, scale)
            .environment(\.artworkSide, side)
        }
        .animation(Theme.fade, value: showControls)
    }

    private func controls(scale s: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                if let kind = player.state?.source {
                    SourceChip(kind: kind, player: player)
                }
                Spacer(minLength: 8)
                GlassCapsule(player: player, settings: settings, panel: panel)
            }
            .padding([.top, .horizontal], 12 * s)

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
                    if player.state?.source.supportsFavorite == true {
                        RoundButton(
                            symbol: player.state?.favorited == true ? "star.fill" : "star",
                            help: "Favorito",
                            action: { player.toggleFavorite() }
                        )
                    }
                    RoundButton(symbol: "ellipsis", help: "Más opciones", action: panel.actions.showMenu)
                }
                TimeBar(player: player, stacked: true)
                    .padding(.top, 8 * s)
                TransportRow(player: player, size: .large)
                    .padding(.top, 1 * s)
            }
            .padding(.horizontal, 18 * s)
            .padding(.bottom, 6 * s)
            // Una sombra apenas, para que el blanco no se pierda sobre tapas muy claras.
            .shadow(color: .black.opacity(0.16), radius: 5, y: 1)
        }
    }

    /// Debajo de los controles: la tapa difuminada de a poco (calculada una vez por tapa)
    /// y un velo que se oscurece hacia abajo para que el blanco se lea sobre tapas claras.
    private var glass: some View {
        ZStack {
            ZStack {
                if let glass = player.glass {
                    ArtworkFill(image: glass.progressive)
                        .transition(.opacity)
                } else {
                    // Mientras se calcula: un difuminado común.
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
