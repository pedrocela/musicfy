import SwiftUI

// MARK: - Chip de la app

/// "● Music" / "● Spotify". En vidrio sobre la tapa, o suelto en el compacto.
struct SourceChip: View {
    enum Style { case glass, plain }
    let kind: SourceKind
    var style: Style = .glass

    var body: some View {
        HStack(spacing: style == .glass ? 6 : 5) {
            Circle()
                .fill(Theme.sourceColor(kind))
                .frame(width: style == .glass ? 7 : 6, height: style == .glass ? 7 : 6)
            Text(kind.displayName)
                .font(style == .glass ? Theme.chip : .system(size: 11, weight: .semibold))
                .foregroundStyle(style == .glass ? Theme.primary : Color.white.opacity(0.78))
                .contentTransition(.opacity)
        }
        .padding(.horizontal, style == .glass ? 10 : 0)
        .frame(height: style == .glass ? 26 : nil)
        .background {
            if style == .glass {
                Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    .overlay(Capsule().fill(Theme.chipFill))
            }
        }
        .animation(Theme.crossfade, value: kind)
    }
}

// MARK: - Tiempo y progreso en una línea

struct TimeBar: View {
    @ObservedObject var player: PlayerController
    var fill: Color = Theme.barFill
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let duration = player.state?.duration ?? 0
            let live = player.position(at: context.date)
            let shown = dragFraction.map { $0 * duration } ?? live
            HStack(spacing: 10) {
                Text(TimeText.format(shown))
                    .frame(minWidth: 30, alignment: .leading)
                ScrubBar(
                    fraction: duration > 0 ? shown / duration : 0,
                    fill: fill,
                    onChange: { dragFraction = $0 },
                    onCommit: { value in
                        player.seek(toFraction: value)
                        dragFraction = nil
                    }
                )
                Text("−" + TimeText.format(max(0, duration - shown)))
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .font(Theme.time)
            .foregroundStyle(Theme.timeColor)
        }
    }
}

/// La misma línea, pero para el volumen de la app.
struct VolumeBar: View {
    @ObservedObject var player: PlayerController
    var fill: Color = Theme.barFill

    var body: some View {
        let volume = Double(player.state?.volume ?? 0)
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .frame(minWidth: 30, alignment: .leading)
            ScrubBar(
                fraction: volume / 100,
                fill: fill,
                onChange: { player.setVolume(Int(($0 * 100).rounded())) },
                onCommit: { player.setVolume(Int(($0 * 100).rounded())) },
                smoothFill: false
            )
            Image(systemName: "speaker.wave.3.fill")
                .frame(minWidth: 34, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.timeColor)
    }
}

// MARK: - Controles de reproducción

struct TransportRow: View {
    enum Size {
        case large, medium

        var side: CGFloat { self == .large ? 17 : 16 }
        var skip: CGFloat { self == .large ? 26 : 22 }
        var play: CGFloat { self == .large ? 28 : 24 }
        var height: CGFloat { self == .large ? 44 : 36 }
    }

    @ObservedObject var player: PlayerController
    var size: Size = .large
    /// La Isla abierta sólo muestra anterior, play y siguiente, centrados.
    var showsModes = true

    var body: some View {
        let state = player.state
        let playing = state?.isPlaying ?? false
        HStack(spacing: 0) {
            if showsModes {
                IconButton(
                    symbol: "shuffle",
                    size: size.side,
                    tint: state?.shuffle == true ? Theme.primary : Theme.tertiary,
                    help: "Aleatorio",
                    action: { player.toggleShuffle() }
                )
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
            IconButton(symbol: "backward.fill", size: size.skip, help: "Anterior", action: { player.previous() })
            if showsModes { Spacer(minLength: 0) } else { Spacer().frame(width: 18) }
            IconButton(symbol: playing ? "pause.fill" : "play.fill", size: size.play, help: playing ? "Pausa" : "Reproducir", action: { player.playPause() })
            if showsModes { Spacer(minLength: 0) } else { Spacer().frame(width: 18) }
            IconButton(symbol: "forward.fill", size: size.skip, help: "Siguiente", action: { player.next() })
            Spacer(minLength: 0)
            if showsModes {
                IconButton(
                    symbol: state?.repeatMode == .one ? "repeat.1" : "repeat",
                    size: size.side,
                    tint: state?.repeatMode == .off || state == nil ? Theme.tertiary : Theme.primary,
                    help: "Repetir",
                    action: { player.cycleRepeat() }
                )
            }
        }
        .frame(height: size.height)
    }
}

// MARK: - Botones de arriba (letras, volumen, salida, modo)

struct ToolbarIcons: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel
    /// Botón para cambiar de modo, si corresponde.
    var modeSwitch: DisplayMode?
    var iconSize: CGFloat = 15
    var cell: CGFloat = 32
    var tint: Color = Theme.primary

    var body: some View {
        HStack(spacing: 0) {
            if settings.showLyricsButton {
                icon(lyricsActive ? "quote.bubble.fill" : "quote.bubble", "Letras", active: lyricsActive) {
                    if panel.mode == .island {
                        player.lyricsVisible.toggle()
                    } else {
                        panel.drawer = panel.drawer == .lyrics ? .none : .lyrics
                    }
                }
            }
            if settings.showQueueButton, panel.mode != .island {
                icon("list.bullet", "A continuación", active: panel.drawer == .queue) {
                    panel.drawer = panel.drawer == .queue ? .none : .queue
                }
            }
            if settings.showOutput {
                icon("airplayaudio", "Salida de audio") { panel.actions.showOutputMenu() }
            }
            if settings.showVolume {
                icon(volumeSymbol, "Volumen", active: panel.volumeOpen) { panel.volumeOpen.toggle() }
            }
            if let modeSwitch {
                icon(
                    modeSwitch == .compact ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    modeSwitch == .compact ? "Modo compacto" : "Modo tapa"
                ) { panel.actions.setMode(modeSwitch) }
            }
        }
    }

    private var lyricsActive: Bool {
        panel.mode == .island ? player.lyricsVisible : panel.drawer == .lyrics
    }

    private var volumeSymbol: String {
        let volume = player.state?.volume ?? 50
        switch volume {
        case 0: return "speaker.slash"
        case ..<34: return "speaker.wave.1"
        case ..<67: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }

    private func icon(_ symbol: String, _ help: String, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: cell, height: cell)
                .background(
                    Circle()
                        .fill(Color.white.opacity(active ? 0.24 : 0))
                        .padding(2)
                )
                .contentShape(Rectangle())
                .animation(Theme.fade, value: active)
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

/// La cápsula de vidrio de arriba a la derecha (modo tapa). Con el volumen
/// abierto, la cápsula se estira y muestra la barra en lugar de los íconos.
struct GlassCapsule: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    var body: some View {
        ZStack {
            if panel.volumeOpen {
                HStack(spacing: 6) {
                    Button { panel.volumeOpen = false } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    ScrubBar(
                        fraction: Double(player.state?.volume ?? 0) / 100,
                        onChange: { player.setVolume(Int(($0 * 100).rounded())) },
                        onCommit: { player.setVolume(Int(($0 * 100).rounded())) },
                        smoothFill: false
                    )
                    .frame(width: 112)
                    .padding(.trailing, 10)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            } else {
                ToolbarIcons(player: player, settings: settings, panel: panel, modeSwitch: .compact)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
        }
        .foregroundStyle(Theme.primary)
        .padding(.horizontal, 4)
        .frame(height: 32)
        .background(
            Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                .overlay(Capsule().fill(Theme.capsuleFill))
                .overlay(Capsule().strokeBorder(Theme.capsuleStroke, lineWidth: 0.5))
        )
        .animation(Theme.smooth, value: panel.volumeOpen)
    }
}

// MARK: - Subtítulo o línea de la letra

/// Debajo del título: "Artista — Álbum", o la línea de la letra que está sonando.
struct SubtitleLine: View {
    @ObservedObject var player: PlayerController
    let font: Font
    let height: CGFloat
    var text: String? = nil
    /// Sólo la Isla muestra la línea de la letra en lugar del subtítulo.
    var showsLyric = false

    var body: some View {
        if showsLyric, player.lyricsVisible, let lyrics = player.lyrics, lyrics.isSynced {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let index = lyrics.index(at: player.position(at: context.date) + 0.3)
                let line = index.map { lyrics.lines[$0].text } ?? ""
                ZStack(alignment: .leading) {
                    MarqueeText(text: line.isEmpty ? "♪" : line, font: font, color: Theme.primary, height: height)
                        .id(index ?? -1)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity.combined(with: .offset(y: -6))
                        ))
                }
                .animation(Theme.smooth, value: index)
            }
            .frame(height: height)
        } else {
            MarqueeText(text: text ?? player.state?.subtitle ?? "", font: font, color: Theme.secondary, height: height)
        }
    }
}

// MARK: - Panel de letras

struct LyricsPanel: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        Group {
            if player.lyricsLoading {
                ProgressView().controlSize(.small).tint(.white)
            } else if let lyrics = player.lyrics, lyrics.isSynced {
                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                    SyncedLyrics(lines: lyrics.lines, current: lyrics.index(at: player.position(at: context.date) + 0.3))
                }
                .allowsHitTesting(false)
            } else if let lyrics = player.lyrics, lyrics.instrumental {
                PanelMessage(title: "Instrumental", detail: "Este tema no tiene letra.")
            } else if let lyrics = player.lyrics, !lyrics.plain.isEmpty {
                ScrollView(showsIndicators: false) {
                    Text(lyrics.plain)
                        .font(.system(size: 16, weight: .semibold))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            } else {
                PanelMessage(title: "No hay letra", detail: "No encontramos la letra de este tema.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PanelMessage: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }
}

private struct SyncedLyrics: View {
    let lines: [Lyrics.Line]
    let current: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(lines.indices, id: \.self) { index in
                        let isCurrent = index == current
                        Text(lines[index].text.isEmpty ? "♪" : lines[index].text)
                            .font(Theme.lyric)
                            .foregroundStyle(Theme.primary.opacity(isCurrent ? 1 : 0.32))
                            .blur(radius: isCurrent ? 0 : 0.6)
                            .scaleEffect(isCurrent ? 1 : 0.97, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                            .animation(Theme.smooth, value: isCurrent)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 150)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onAppear { proxy.scrollTo(current ?? 0, anchor: .center) }
            .onChange(of: current) { _, value in
                withAnimation(.smooth(duration: 0.6)) { proxy.scrollTo(value ?? 0, anchor: .center) }
            }
        }
    }
}

// MARK: - Nada sonando y permisos

struct EmptyStateView: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
            Text("Nada sonando")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primary)
            HStack(spacing: 8) {
                ForEach(player.installedSources) { kind in
                    Button { player.open(kind) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.sourceColor(kind)).frame(width: 6, height: 6)
                            Text("Abrir \(kind.displayName)")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Theme.roundButtonFill))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.top, 6)
        }
    }
}

struct PermissionBanner: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        if let problem = player.problem, problem.kind == .notAuthorized {
            Button(action: { player.openAutomationSettings() }) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                    Text("Falta permiso para \(problem.source.displayName) · Abrir Ajustes")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(Color.red.opacity(0.55)))
            }
            .buttonStyle(PressableStyle())
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
