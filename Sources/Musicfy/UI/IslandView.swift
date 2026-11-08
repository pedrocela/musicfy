import SwiftUI

/// Modo Isla: cápsula de 300 × 44 arriba al centro de la pantalla. Al pasar
/// el mouse se abre hacia abajo (380 × 176) con los controles.
///
/// La ventana tiene siempre el tamaño de la Isla abierta (más el margen de la
/// sombra); lo que se anima es la cápsula adentro. La app deja pasar los clics
/// por la parte transparente.
struct IslandView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    private var expanded: Bool { panel.islandExpanded }
    private var accent: Color { Color(nsColor: player.palette.accent) }
    private var playing: Bool { player.state?.isPlaying ?? false }

    var body: some View {
        let size = expanded ? Theme.islandExpanded : Theme.islandCollapsed
        let radius: CGFloat = expanded ? 28 : 22
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if expanded {
                    expandedContent
                        .transition(.asymmetric(
                            insertion: .opacity.animation(Theme.fade.delay(0.08)),
                            removal: .opacity.animation(.easeOut(duration: 0.12))
                        ))
                } else {
                    collapsedContent
                        .transition(.asymmetric(
                            insertion: .opacity.animation(Theme.fade.delay(0.1)),
                            removal: .opacity.animation(.easeOut(duration: 0.1))
                        ))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(expanded ? Theme.islandOpenFill : Theme.islandFill)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(accent.opacity(playing ? 0.28 : 0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(expanded ? 0.38 : 0.3), radius: expanded ? 22 : 14, y: 10)
            .animation(Theme.smooth, value: expanded)
            .animation(Theme.crossfade, value: player.palette)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Cerrada

    private var collapsedContent: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 10) {
                thumbnail(side: 32, radius: 10)
                    .saturation(playing ? 1 : 0.3)
                    .brightness(playing ? 0 : -0.08)
                VStack(alignment: .leading, spacing: 1) {
                    if let state = player.state {
                        MarqueeText(
                            text: state.title,
                            font: Theme.islandTitle,
                            color: playing ? Theme.primary : Color.white.opacity(0.8),
                            height: 16
                        )
                        if playing {
                            SubtitleLine(player: player, font: Theme.islandSubtitle, height: 14, text: islandSubtitle(state), showsLyric: true)
                        } else {
                            Text("En pausa")
                                .font(Theme.islandSubtitle)
                                .foregroundStyle(Color.white.opacity(0.6))
                                .frame(height: 14)
                        }
                    } else {
                        Text("Nada sonando")
                            .font(Theme.islandTitle)
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }
                .id(player.state?.trackKey ?? "")
                .transition(.opacity)
                .animation(Theme.crossfade, value: player.state?.trackKey)
                Spacer(minLength: 0)
                if playing {
                    Equalizer(color: accent)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                } else if player.state != nil {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .animation(Theme.smooth, value: playing)
            .padding(.leading, 6)
            .padding(.trailing, 16)
            .frame(maxHeight: .infinity)

            if player.state != nil {
                ProgressThread(player: player, color: playing ? accent : Color.white.opacity(0.45))
                    .padding(.horizontal, 22)
            }
        }
        .frame(width: Theme.islandCollapsed.width, height: Theme.islandCollapsed.height)
    }

    private func islandSubtitle(_ state: PlayerState) -> String {
        let artist = state.artist.isEmpty ? state.album : state.artist
        return settings.forcedSource == nil && SourceKind.allCases.filter(\.isRunning).count > 1
            ? "\(artist) · \(state.source.displayName)"
            : artist
    }

    // MARK: Abierta

    private var expandedContent: some View {
        VStack(spacing: 0) {
            if player.state == nil {
                EmptyStateView(player: player)
                    .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 12) {
                    thumbnail(side: 60, radius: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: player.state?.title ?? "", font: Theme.islandOpenTitle, color: Theme.primary, height: 19)
                        SubtitleLine(player: player, font: Theme.compactSubtitle, height: 16, showsLyric: true)
                    }
                    .id(player.state?.trackKey ?? "")
                    .transition(.opacity)
                    .animation(Theme.crossfade, value: player.state?.trackKey)
                    Spacer(minLength: 0)
                    ToolbarIcons(
                        player: player,
                        settings: settings,
                        panel: panel,
                        iconSize: 14,
                        cell: 30,
                        tint: Color.white.opacity(0.82)
                    )
                }
                ZStack {
                    if panel.volumeOpen {
                        VolumeBar(player: player, fill: accent).transition(.opacity)
                    } else {
                        TimeBar(player: player, fill: accent).transition(.opacity)
                    }
                }
                .padding(.top, 12)
                .animation(Theme.fade, value: panel.volumeOpen)
                TransportRow(player: player, size: .medium, showsModes: false)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .frame(width: Theme.islandExpanded.width, height: Theme.islandExpanded.height, alignment: .top)
    }

    private func thumbnail(side: CGFloat, radius: CGFloat) -> some View {
        ZStack { CrossfadingArtwork(player: player) }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Cuatro barritas que suben y bajan mientras suena algo.
private struct Equalizer: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { bar in
                    let phase = [0.0, 0.33, 0.66, 0.17][bar]
                    let wave = 0.5 + 0.5 * sin((time / 0.9 + phase) * 2 * .pi)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: 3, height: 14 * (0.35 + 0.65 * wave))
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
    }
}

/// El hilo de progreso en el borde de abajo de la cápsula.
private struct ProgressThread: View {
    @ObservedObject var player: PlayerController
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = player.state?.duration ?? 0
            let fraction = duration > 0 ? min(1, player.position(at: context.date) / duration) : 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.12))
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * fraction)
                        .animation(.linear(duration: 0.5), value: fraction)
                }
            }
            .frame(height: 2)
        }
    }
}
