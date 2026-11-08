import SwiftUI

// MARK: - Source glyph

/// Which app is playing, as a glyph: Music's pink note or Spotify's green disc.
/// Over the artwork it sits in a 28 pt glass circle; in compact it stands alone.
/// Clicking it brings the app to the front.
struct SourceChip: View {
    enum Style { case glass, plain }
    let kind: SourceKind
    var style: Style = .glass
    @ObservedObject var player: PlayerController
    @Environment(\.uiScale) private var scale
    @State private var hovering = false

    var body: some View {
        Button { player.open(kind) } label: {
            Group {
                if style == .glass {
                    SourceGlyph(kind: kind, size: 16 * scale)
                        .frame(width: 28 * scale, height: 28 * scale)
                        .background(
                            GlassBackdrop(player: player, shape: Circle())
                                .overlay(Circle().fill(Color.white.opacity(hovering ? 0.08 : 0)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                        )
                        .contentShape(Circle())
                } else {
                    SourceGlyph(kind: kind, size: 16)
                        .frame(width: 20, height: 20)
                        .opacity(hovering ? 1 : 0.92)
                        .contentShape(Rectangle())
                }
            }
            .id(kind)
            .transition(.opacity)
        }
        .buttonStyle(PressableStyle())
        .help("Playing in \(kind.displayName)")
        .onHover { hovering = $0 }
        .animation(Theme.fade, value: hovering)
        .animation(Theme.crossfade, value: kind)
    }
}

/// The glyph itself. Music: a note in its pink. Spotify: a green disc with three dark waves.
struct SourceGlyph: View {
    let kind: SourceKind
    let size: CGFloat

    var body: some View {
        switch kind {
        case .music:
            Image(systemName: "music.note")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Theme.sourceColor(.music))
        case .spotify:
            let side = size * 17 / 16
            ZStack {
                Circle().fill(Theme.sourceColor(.spotify))
                SpotifyWaves()
                    .stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: side * 0.09, lineCap: .round))
            }
            .frame(width: side, height: side)
        }
    }
}

/// Three arcs, widest on top, slightly tilted, as in Spotify's mark.
private struct SpotifyWaves: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        // (vertical position, half width, how much the arc bows, tilt)
        let waves: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.34, 0.30, 0.10, 0.03),
            (0.52, 0.25, 0.08, 0.025),
            (0.69, 0.20, 0.06, 0.02),
        ]
        for (y, half, bow, tilt) in waves {
            let start = CGPoint(x: (0.5 - half) * w, y: (y + tilt) * h)
            let end = CGPoint(x: (0.5 + half) * w, y: (y + tilt * 0.4) * h)
            let control = CGPoint(x: 0.5 * w, y: (y - bow) * h)
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
        }
        return path
    }
}

// MARK: - Time and progress

/// Like a `TimelineView`, but on the player's clock: it stays still while nothing plays
/// or the player is hidden, instead of redrawing the same frame several times a second.
struct PlaybackTimeline<Content: View>: View {
    @ObservedObject var clock: PlaybackClock
    @ViewBuilder let content: (Date) -> Content

    var body: some View { content(clock.now) }
}

struct TimeBar: View {
    @ObservedObject var player: PlayerController
    var fill: Color = Theme.barFill
    /// Times below the bar, at each end (artwork mode, as in Music).
    var stacked = false
    /// Small artwork: the times stay hidden until the pointer is over the bar.
    var timesOnHover = false
    @State private var dragFraction: Double?
    @State private var hovering = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        PlaybackTimeline(clock: player.clock) { now in
            let duration = player.state?.duration ?? 0
            let live = player.position(at: now)
            let shown = dragFraction.map { $0 * duration } ?? live
            let bar = ScrubBar(
                // The bar is placed for this very moment and then moves on its own.
                fraction: dragFraction ?? player.progressFraction(),
                rate: dragFraction == nil ? player.progressRate : 0,
                fill: fill,
                onChange: { dragFraction = $0 },
                onCommit: { value in
                    player.seek(toFraction: value)
                    dragFraction = nil
                }
            )
            let elapsed = Text(TimeText.format(shown))
            let remaining = Text("−" + TimeText.format(max(0, duration - shown)))
            Group {
                if stacked {
                    VStack(spacing: 1 * scale) {
                        bar
                        HStack {
                            elapsed
                            Spacer(minLength: 8)
                            remaining
                        }
                        .opacity(!timesOnHover || hovering || dragFraction != nil ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering = $0 }
                    .animation(Theme.fade, value: hovering)
                } else {
                    HStack(spacing: 10) {
                        elapsed.frame(minWidth: 30, alignment: .leading)
                        bar
                        remaining.frame(minWidth: 34, alignment: .trailing)
                    }
                }
            }
            .font(.system(size: 11 * scale, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.timeColor)
        }
    }
}

/// The same line, for the app's volume.
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

// MARK: - Playback controls

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
    /// The open Island only shows previous, play and next, centered.
    var showsModes = true
    @Environment(\.uiScale) private var scale

    var body: some View {
        let state = player.state
        let playing = state?.isPlaying ?? false
        HStack(spacing: 0) {
            if showsModes {
                IconButton(
                    symbol: "shuffle",
                    size: size.side,
                    tint: state?.shuffle == true ? Theme.primary : Color.white.opacity(0.5),
                    help: "Shuffle",
                    active: state?.shuffle == true,
                    action: { player.toggleShuffle() }
                )
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
            IconButton(symbol: "backward.fill", size: size.skip, help: "Previous", action: { player.previous() })
            if showsModes { Spacer(minLength: 0) } else { Spacer().frame(width: 18) }
            IconButton(symbol: playing ? "pause.fill" : "play.fill", size: size.play, help: "Play/Pause", action: { player.playPause() })
            if showsModes { Spacer(minLength: 0) } else { Spacer().frame(width: 18) }
            IconButton(symbol: "forward.fill", size: size.skip, help: "Next", action: { player.next() })
            Spacer(minLength: 0)
            if showsModes {
                IconButton(
                    symbol: state?.repeatMode == .one ? "repeat.1" : "repeat",
                    size: size.side,
                    tint: state?.repeatMode == .off || state == nil ? Color.white.opacity(0.5) : Theme.primary,
                    help: "Repeat",
                    active: state.map { $0.repeatMode != .off } ?? false,
                    action: { player.cycleRepeat() }
                )
            }
        }
        .frame(height: size.height * scale)
    }
}

// MARK: - Top buttons (lyrics, volume, output, mode)

struct ToolbarIcons: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel
    /// Mode switch button, if any.
    var modeSwitch: DisplayMode?
    var iconSize: CGFloat = 15
    var cell: CGFloat = 32
    var tint: Color = Theme.primary
    /// Compact can't fit everything: audio output stays in the menu.
    var includesOutput = true
    /// Small artwork drops Up Next too.
    var includesQueue = true
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            if settings.showLyricsButton {
                icon(lyricsActive ? "quote.bubble.fill" : "quote.bubble", "Lyrics", active: lyricsActive) {
                    if panel.mode == .island {
                        player.lyricsVisible.toggle()
                    } else {
                        panel.drawer = panel.drawer == .lyrics ? .none : .lyrics
                    }
                }
            }
            if settings.showQueueButton, includesQueue, panel.mode != .island {
                icon("list.bullet", "Up Next", active: panel.drawer == .queue) {
                    panel.drawer = panel.drawer == .queue ? .none : .queue
                }
            }
            if settings.showOutput, includesOutput {
                icon("airplayaudio", "Audio Output") { panel.actions.showOutputMenu() }
            }
            if settings.showVolume {
                icon(volumeSymbol, "Volume", active: panel.volumeOpen) { panel.volumeOpen.toggle() }
            }
            if let modeSwitch {
                icon(
                    modeSwitch == .compact ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    "Change Mode"
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
                .font(.system(size: iconSize * scale, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: cell * scale, height: cell * scale)
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

/// The glass capsule at the top right (artwork mode). With the volume open,
/// the capsule stretches and shows the slider instead of the icons.
struct GlassCapsule: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel
    var density: ArtworkDensity = .full
    @Environment(\.uiScale) private var scale

    var body: some View {
        ZStack {
            if panel.volumeOpen {
                HStack(spacing: 6 * scale) {
                    Button { panel.volumeOpen = false } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 13 * scale, weight: .semibold))
                            .frame(width: 28 * scale, height: 32 * scale)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    ScrubBar(
                        fraction: Double(player.state?.volume ?? 0) / 100,
                        onChange: { player.setVolume(Int(($0 * 100).rounded())) },
                        onCommit: { player.setVolume(Int(($0 * 100).rounded())) },
                        smoothFill: false
                    )
                    .frame(width: (density == .minimal ? 88 : 112) * scale)
                    .padding(.trailing, 10 * scale)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            } else {
                ToolbarIcons(
                    player: player,
                    settings: settings,
                    panel: panel,
                    modeSwitch: density == .full ? .compact : nil,
                    includesOutput: density == .full,
                    includesQueue: density != .minimal
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
        }
        .foregroundStyle(Theme.primary)
        .padding(.horizontal, 4 * scale)
        .frame(height: 32 * scale)
        .background(GlassBackdrop(player: player, shape: Capsule()))
        .animation(Theme.smooth, value: panel.volumeOpen)
    }
}

// MARK: - Subtitle or lyric line

/// Under the title: "Artist — Album", or the lyric line being sung.
struct SubtitleLine: View {
    @ObservedObject var player: PlayerController
    let font: Font
    let height: CGFloat
    var text: String? = nil
    /// Only the Island shows the lyric line instead of the subtitle.
    var showsLyric = false

    var body: some View {
        if showsLyric, player.lyricsVisible, let lyrics = player.lyrics, lyrics.isSynced {
            PlaybackTimeline(clock: player.clock) { now in
                let index = lyrics.index(at: player.position(at: now) + 0.3)
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

// MARK: - Lyrics panel

struct LyricsPanel: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        Group {
            if player.lyricsLoading {
                ProgressView().controlSize(.small).tint(.white)
            } else if let lyrics = player.lyrics, lyrics.isSynced {
                PlaybackTimeline(clock: player.clock) { now in
                    SyncedLyrics(lines: lyrics.lines, current: lyrics.index(at: player.position(at: now) + 0.3))
                        .equatable()
                }
                .allowsHitTesting(false)
            } else if let lyrics = player.lyrics, lyrics.instrumental {
                PanelMessage(title: "Instrumental", detail: "This song has no lyrics.")
            } else if let lyrics = player.lyrics, !lyrics.plain.isEmpty {
                ScrollView(showsIndicators: false) {
                    Text(lyrics.plain)
                        .font(.system(size: 16, weight: .semibold))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.primary.opacity(0.85))
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            } else {
                PanelMessage(title: "No Lyrics", detail: "No lyrics for this song.")
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

/// Equatable: the clock ticks four times a second, but the list only needs a new look
/// when the line changes.
private struct SyncedLyrics: View, Equatable {
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
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
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

// MARK: - Nothing playing and permissions

struct EmptyStateView: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
            Text("Nothing Playing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.primary)
            Text(SourceKind.allCases.contains(where: \.isRunning) ? "Play something in Music or Spotify." : "Music and Spotify are closed.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 8) {
                ForEach(player.installedSources) { kind in
                    Button { player.open(kind) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.sourceColor(kind)).frame(width: 6, height: 6)
                            Text("Open \(kind.displayName)")
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
                    Text("\(problem.source.displayName) needs permission · Open Settings")
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
