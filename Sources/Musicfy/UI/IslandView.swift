import SwiftUI

/// Modo Isla: cápsula de 300 × 40 centrada debajo de la barra de menú. Al dejar
/// el mouse encima se abre hacia abajo (380 × 168) con los controles.
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
        let shape = RoundedRectangle(cornerRadius: expanded ? Theme.islandOpenRadius : Theme.islandRadius, style: .continuous)
        VStack(alignment: panel.islandAlignment.horizontal, spacing: 0) {
            ZStack(alignment: .top) {
                Theme.islandFill
                LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center)
                    .allowsHitTesting(false)
                IslandDragArea()
                if expanded {
                    expandedContent
                        .transition(.asymmetric(
                            insertion: .opacity.animation(Theme.fade.delay(0.1)),
                            removal: .opacity.animation(.easeOut(duration: 0.1))
                        ))
                } else {
                    collapsedContent
                        .transition(.asymmetric(
                            insertion: .opacity.animation(Theme.fade.delay(0.12)),
                            removal: .opacity.animation(.easeOut(duration: 0.1))
                        ))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.islandStroke, lineWidth: 0.5))
            // Al tirarla hacia abajo crece un poco y se aclara el borde: avisa que se va a volver tapa.
            .overlay(shape.strokeBorder(Color.white.opacity(0.28 * panel.islandPull), lineWidth: 1))
            .scaleEffect(1 + 0.08 * panel.islandPull, anchor: .top)
            .shadow(color: .black.opacity(expanded ? 0.32 : 0.22), radius: expanded ? 20 : 10, y: expanded ? 10 : 4)
            .animation(Theme.smooth, value: expanded)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.islandShadowMargin)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: Alignment(horizontal: panel.islandAlignment.horizontal, vertical: .top)
        )
        .environment(\.colorScheme, .dark)
    }

    // MARK: Cerrada

    private var collapsedContent: some View {
        HStack(spacing: 10) {
            thumbnail(side: 28, radius: 8)
                .saturation(playing ? 1 : 0.35)
                .opacity(playing ? 1 : 0.8)
            VStack(alignment: .leading, spacing: 0) {
                if let state = player.state {
                    MarqueeText(
                        text: state.title,
                        font: Theme.islandTitle,
                        color: playing ? Theme.primary : Color.white.opacity(0.82),
                        height: 16,
                        trailingFade: 36,
                        scrolls: false
                    )
                    if playing {
                        SubtitleLine(player: player, font: Theme.islandSubtitle, height: 14, text: islandSubtitle(state), showsLyric: true)
                    } else {
                        Text("En pausa")
                            .font(Theme.islandSubtitle)
                            .foregroundStyle(Color.white.opacity(0.55))
                            .frame(height: 14)
                    }
                } else {
                    Text("Nada sonando")
                        .font(Theme.islandTitle)
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .id(player.state?.trackKey ?? "")
            .transition(.opacity.combined(with: .offset(y: 6)))
            .animation(Theme.crossfade, value: player.state?.trackKey)
            .allowsHitTesting(false)

            if player.state != nil {
                ProgressRing(player: player, playing: playing, accent: accent)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 9)
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
                HStack(alignment: .top, spacing: 12) {
                    thumbnail(side: 56, radius: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: player.state?.title ?? "", font: Theme.islandOpenTitle, color: Theme.primary, height: 19)
                        SubtitleLine(player: player, font: Theme.compactSubtitle, height: 16, showsLyric: true)
                    }
                    .frame(height: 56)
                    .id(player.state?.trackKey ?? "")
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .animation(Theme.crossfade, value: player.state?.trackKey)
                    ToolbarIcons(
                        player: player,
                        settings: settings,
                        panel: panel,
                        iconSize: 13,
                        cell: 28,
                        tint: Color.white.opacity(0.85)
                    )
                }
                ZStack {
                    if panel.volumeOpen {
                        VolumeBar(player: player).transition(.opacity)
                    } else {
                        TimeBar(player: player).transition(.opacity)
                    }
                }
                .padding(.top, 12)
                .animation(Theme.fade, value: panel.volumeOpen)
                TransportRow(player: player, size: .large)
                    .padding(.top, 4)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(width: Theme.islandExpanded.width, height: Theme.islandExpanded.height, alignment: .top)
    }

    private func thumbnail(side: CGFloat, radius: CGFloat) -> some View {
        ZStack { CrossfadingArtwork(player: player) }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .allowsHitTesting(false)
    }
}

/// A la derecha de la Isla cerrada: un anillo con el avance del tema y,
/// adentro, tres barritas que bailan (o el ícono de play si está en pausa).
private struct ProgressRing: View {
    @ObservedObject var player: PlayerController
    let playing: Bool
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = player.state?.duration ?? 0
            let fraction = duration > 0 ? min(1, player.position(at: context.date) / duration) : 0
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(playing ? accent : Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: fraction)
                ZStack {
                    if playing {
                        Equalizer(color: accent)
                            .transition(.opacity.combined(with: .scale(scale: 0.5)))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .offset(x: 0.5)
                            .transition(.opacity.combined(with: .scale(scale: 0.5)))
                    }
                }
                .animation(Theme.smooth, value: playing)
            }
            .frame(width: 22, height: 22)
            .animation(Theme.crossfade, value: playing)
        }
        .allowsHitTesting(false)
    }
}

/// Tres barritas que suben y bajan a ritmos distintos.
private struct Equalizer: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { bar in
                    let speed = [1.05, 0.8, 1.3][bar]
                    let phase = [0.0, 0.4, 0.7][bar]
                    let wave = 0.5 + 0.5 * sin((time * speed + phase) * 2 * .pi)
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: 3 + 6 * wave)
                }
            }
            .frame(height: 10)
        }
    }
}

/// Fondo de la Isla: clic derecho abre el menú; arrastrar la mueve por el borde
/// de arriba y al soltar se pega a la izquierda, al centro o a la derecha.
private struct IslandDragArea: NSViewRepresentable {
    final class DragView: NSView {
        private var startMouse = NSPoint.zero
        private var startOrigin = NSPoint.zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            startMouse = NSEvent.mouseLocation
            startOrigin = window?.frame.origin ?? .zero
        }

        /// Hacia los costados la sigue tal cual; hacia abajo también, para volverla tapa.
        /// Hacia arriba no se mueve: ya está pegada a la barra de menú.
        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let mouse = NSEvent.mouseLocation
            let down = max(0, startMouse.y - mouse.y)
            window.setFrameOrigin(NSPoint(x: startOrigin.x + (mouse.x - startMouse.x), y: startOrigin.y - down))
            AppDelegate.shared?.islandPulled(by: down)
        }

        override func mouseUp(with event: NSEvent) {
            let mouse = NSEvent.mouseLocation
            let down = max(0, startMouse.y - mouse.y)
            if down > 2 || abs(mouse.x - startMouse.x) > 2 {
                AppDelegate.shared?.islandReleased(pulled: down)
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            AppDelegate.shared?.showMainMenu()
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}
