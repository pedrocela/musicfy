import SwiftUI

// MARK: - Source glyph

/// Which app is playing, as a glyph: Music's pink note, Spotify's green disc or Podcasts'
/// purple waves.
/// Over the artwork it sits in a 28 pt glass circle; in compact it stands alone.
/// Clicking it brings the app to the front.
struct SourceChip: View {
    enum Style { case glass, plain }
    let kind: SourceKind
    var style: Style = .glass
    @ObservedObject var player: PlayerController
    @Environment(\.artworkMetrics) private var metrics
    @State private var hovering = false

    var body: some View {
        Button { player.open(kind) } label: {
            Group {
                if style == .glass {
                    SourceGlyph(kind: kind, size: metrics.glyph)
                        .frame(width: metrics.glyphCircle, height: metrics.glyphCircle)
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
        case .podcasts:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: size * 0.92, weight: .semibold))
                .foregroundStyle(Theme.sourceColor(.podcasts))
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
    /// Artwork mode passes its own size for the times.
    var timeSize: CGFloat? = nil
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
            .font(.system(size: timeSize ?? 11 * scale, weight: .medium).monospacedDigit())
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
        case large, medium, small

        var side: CGFloat { switch self { case .large: 17; case .medium: 16; case .small: 12 } }
        var skip: CGFloat { switch self { case .large: 26; case .medium: 22; case .small: 17 } }
        var play: CGFloat { switch self { case .large: 28; case .medium: 24; case .small: 20 } }
        var height: CGFloat { switch self { case .large: 44; case .medium: 36; case .small: 32 } }
    }

    @ObservedObject var player: PlayerController
    var size: Size = .large
    /// The open Island only shows previous, play and next, centered.
    var showsModes = true
    /// Artwork mode's measures, which replace `size`.
    var metrics: ArtworkMetrics? = nil
    @Environment(\.uiScale) private var scale

    private var sideSize: CGFloat { metrics?.shuffle ?? size.side }
    private var skipSize: CGFloat { metrics?.skip ?? size.skip }
    private var playSize: CGFloat { metrics?.play ?? size.play }
    private var rowHeight: CGFloat { metrics?.transportHeight ?? size.height * scale }
    /// Shuffle and repeat when off.
    private var modeOff: Color { Color.white.opacity(metrics == nil ? 0.5 : 0.6) }

    var body: some View {
        let state = player.state
        let playing = state?.isPlaying ?? false
        let kind = state?.source ?? .music
        if kind.isSpokenWord {
            spokenWord(kind: kind, playing: playing)
        } else {
            music(state: state, kind: kind, playing: playing)
        }
    }

    /// Podcasts: back 15, play, ahead 30, as one centered group (no shuffle or repeat to
    /// spread out). The jump glyphs carry numbers, so they're drawn a little larger and the
    /// group stays tight around play, as in Podcasts' own player.
    private func spokenWord(kind: SourceKind, playing: Bool) -> some View {
        let jump = (skipSize * 1.12).rounded()
        let gap = (playSize * (showsModes ? 0.9 : 0.6)).rounded()
        return HStack(spacing: gap) {
            IconButton(symbol: kind.previousSymbol, size: jump, help: kind.previousHelp, action: { player.previous() })
            IconButton(symbol: playing ? "pause.fill" : "play.fill", size: playSize, help: "Play/Pause", action: { player.playPause() })
            IconButton(symbol: kind.nextSymbol, size: jump, help: kind.nextHelp, action: { player.next() })
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
    }

    private func music(state: PlayerState?, kind: SourceKind, playing: Bool) -> some View {
        let modes = kind.hasPlayModes
        return HStack(spacing: 0) {
            if showsModes {
                IconButton(
                    symbol: "shuffle",
                    size: sideSize,
                    tint: state?.shuffle == true ? Theme.primary : modeOff,
                    help: "Shuffle",
                    active: state?.shuffle == true,
                    action: { player.toggleShuffle() }
                )
                .opacity(modes ? 1 : 0)
                .allowsHitTesting(modes)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
            IconButton(symbol: kind.previousSymbol, size: skipSize, help: kind.previousHelp, action: { player.previous() })
            if showsModes { Spacer(minLength: 0) } else { Spacer().frame(width: 18) }
            IconButton(symbol: playing ? "pause.fill" : "play.fill", size: playSize, help: "Play/Pause", action: { player.playPause() })
            if showsModes { Spacer(minLength: 0) } else { Spacer().frame(width: 18) }
            IconButton(symbol: kind.nextSymbol, size: skipSize, help: kind.nextHelp, action: { player.next() })
            Spacer(minLength: 0)
            if showsModes {
                IconButton(
                    symbol: state?.repeatMode == .one ? "repeat.1" : "repeat",
                    size: sideSize,
                    tint: state?.repeatMode == .off || state == nil ? modeOff : Theme.primary,
                    help: "Repeat",
                    active: state.map { $0.repeatMode != .off } ?? false,
                    action: { player.cycleRepeat() }
                )
                .opacity(modes ? 1 : 0)
                .allowsHitTesting(modes)
            }
        }
        .frame(height: rowHeight)
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
        let kind = player.state?.source
        HStack(spacing: 0) {
            if settings.showLyricsButton, kind?.hasLyrics != false {
                icon(lyricsActive ? "quote.bubble.fill" : "quote.bubble", "Lyrics", active: lyricsActive) {
                    if panel.mode == .island {
                        player.lyricsVisible.toggle()
                    } else {
                        panel.drawer = panel.drawer == .lyrics ? .none : .lyrics
                    }
                }
            }
            if settings.showQueueButton, includesQueue, panel.mode != .island, kind?.hasQueue != false {
                icon("list.bullet", "Up Next", active: panel.drawer == .queue) {
                    panel.drawer = panel.drawer == .queue ? .none : .queue
                }
            }
            if settings.showOutput, includesOutput {
                icon("airplayaudio", "Audio Output") { panel.actions.showOutputMenu() }
            }
            if settings.showVolume, kind?.hasAppVolume != false {
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

/// The glass capsule at the top right (artwork mode): [Lyrics, Up Next] | [Audio Output,
/// Volume] | [Compact]. With the volume open, the capsule stretches and shows the slider.
struct GlassCapsule: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel
    var density: ArtworkDensity = .normal
    @Environment(\.artworkMetrics) private var m
    @State private var shown = false

    var body: some View {
        let shape = Capsule()
        ZStack {
            if panel.volumeOpen {
                HStack(spacing: 6 * m.ratio) {
                    Button { panel.volumeOpen = false } label: {
                        TopBarIcon(symbol: "speaker.wave.2", nudge: 1)
                            .foregroundStyle(Theme.primary)
                            .frame(width: m.buttonWidth, height: m.capsuleHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    ScrubBar(
                        fraction: Double(player.state?.volume ?? 0) / 100,
                        onChange: { player.setVolume(Int(($0 * 100).rounded())) },
                        onCommit: { player.setVolume(Int(($0 * 100).rounded())) },
                        smoothFill: false
                    )
                    .frame(width: (density == .small ? 88 : 112) * m.ratio)
                    .padding(.trailing, 10 * m.ratio)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            } else {
                buttons
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
        }
        .padding(.horizontal, 3)
        .frame(height: m.capsuleHeight)
        .background(
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.42))
            }
            .environment(\.colorScheme, .dark)
        )
        .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2) // 0 2 8: blur 8 is radius 4
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : -2)
        .onAppear { withAnimation(.easeOut(duration: 0.22)) { shown = true } }
        .animation(Theme.smooth, value: panel.volumeOpen)
        // Buttons come and go at the size breaks with a short fade.
        .animation(.easeInOut(duration: 0.2), value: density)
    }

    private var buttons: some View {
        let kind = player.state?.source
        let reading = [
            settings.showLyricsButton && kind?.hasLyrics != false ? Item.lyrics : nil,
            settings.showQueueButton && kind?.hasQueue != false ? Item.queue : nil,
        ].compactMap { $0 }
        let sound = density >= .normal ? [
            settings.showOutput ? Item.output : nil,
            settings.showVolume && kind?.hasAppVolume != false ? Item.volume : nil,
        ].compactMap { $0 } : []
        let mode = density == .large ? [Item.compact] : []
        let groups = [reading, sound, mode].filter { !$0.isEmpty }
        return HStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 1, height: 14 * m.ratio)
                        .padding(.horizontal, 4)
                }
                HStack(spacing: 2) {
                    ForEach(group, id: \.self) { item in button(item) }
                }
            }
        }
    }

    private enum Item: Hashable { case lyrics, queue, output, volume, compact }

    @ViewBuilder
    private func button(_ item: Item) -> some View {
        switch item {
        case .lyrics:
            TopBarButton(symbol: "quote.bubble", help: "Lyrics", active: panel.drawer == .lyrics) {
                panel.drawer = panel.drawer == .lyrics ? .none : .lyrics
            }
        case .queue:
            TopBarButton(symbol: "list.bullet", help: "Up Next", active: panel.drawer == .queue) {
                panel.drawer = panel.drawer == .queue ? .none : .queue
            }
        case .output:
            TopBarButton(symbol: "airplayaudio", help: "Audio Output") { panel.actions.showOutputMenu() }
        case .volume:
            TopBarButton(symbol: "speaker.wave.2", nudge: 1, help: "Volume", active: panel.volumeOpen) {
                panel.volumeOpen.toggle()
            }
        case .compact:
            TopBarButton(symbol: "arrow.down.right.and.arrow.up.left", help: "Change Mode") {
                panel.actions.setMode(.compact)
            }
        }
    }
}

/// An outline symbol (13 pt at the normal size) centered in a box 3 pt larger.
/// `nudge` is an optical shift to the right.
private struct TopBarIcon: View {
    let symbol: String
    var nudge: CGFloat = 0
    @Environment(\.artworkMetrics) private var m

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: m.buttonIcon, weight: .medium))
            .imageScale(.small)
            .frame(width: m.buttonIcon + 3, height: m.buttonIcon + 3)
            .offset(x: nudge)
    }
}

/// One button in the top capsule: 28 × 24 with a 28 × 30 click area. At rest white 85 %;
/// on hover a 12 % fill; pressed 18 % and 0.92 scale; active a white pill with a dark icon.
private struct TopBarButton: View {
    let symbol: String
    var nudge: CGFloat = 0
    let help: String
    var active = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.artworkMetrics) private var m

    var body: some View {
        Button(action: action) {
            EmptyView()
        }
        .buttonStyle(Style(symbol: symbol, nudge: nudge, active: active, hovering: hovering, m: m))
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: active)
        .animation(Theme.fade, value: hovering)
    }

    private struct Style: ButtonStyle {
        let symbol: String
        let nudge: CGFloat
        let active: Bool
        let hovering: Bool
        let m: ArtworkMetrics

        func makeBody(configuration: Configuration) -> some View {
            let pressed = configuration.isPressed
            let pill = RoundedRectangle(cornerRadius: m.buttonHeight / 2, style: .continuous)
            TopBarIcon(symbol: symbol, nudge: nudge)
                .foregroundStyle(
                    active ? Color(red: 0.102, green: 0.078, blue: 0.071) // #1A1412
                        : Color.white.opacity(hovering || pressed ? 1 : 0.85)
                )
                .frame(width: m.buttonWidth, height: m.buttonHeight)
                .background(
                    pill.fill(
                        active ? Color.white
                            : Color.white.opacity(pressed ? 0.18 : hovering ? 0.12 : 0)
                    )
                )
                .scaleEffect(pressed ? 0.92 : 1)
                .animation(.easeOut(duration: 0.12), value: pressed)
                .frame(width: m.buttonWidth, height: m.capsuleHeight)
                .contentShape(Rectangle())
        }
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

/// What the player shows when no app has anything loaded. It keeps the player's own
/// layout so it reads as the same object, just empty:
/// - Artwork: an empty cover fills the window; the title sits where the song's would and
///   the app buttons where the transport goes.
/// - Compact: the empty cover as the thumbnail, text and buttons beside it.
/// - Island (open): like the open Island while playing, with the buttons in place of the
///   transport. The closed Island draws its own (`EmptyIslandRow`).
/// - Mini artwork: the cover and the app glyphs only.
/// Nothing in it animates while it sits there, so an idle player costs nothing.
struct EmptyStateView: View {
    enum Placement { case panel, island }

    @ObservedObject var player: PlayerController
    var placement: Placement = .panel
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Group {
                if placement == .island {
                    island
                } else if size.width < Theme.artworkMiniBreak {
                    mini(side: min(size.width, size.height))
                } else if size.height >= 200 {
                    artwork(side: size.width)
                } else {
                    compact
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(Theme.fade) { appeared = true }
        }
    }

    // MARK: Layouts

    private func artwork(side: CGFloat) -> some View {
        let m = ArtworkMetrics(side: side)
        return ZStack {
            EmptyCover(sources: player.installedSources, noteScale: 0.30, noteOpacity: 0.16, noteLift: 0.08)
            // The same veil the controls sit on.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.40),
                    .init(color: .black.opacity(0.18), location: 0.66),
                    .init(color: .black.opacity(0.42), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Text("Nothing Playing")
                    .font(.system(size: m.title, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text(detail)
                    .font(.system(size: m.artist))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 1)
                buttons(height: m.capsuleHeight, fill: true)
                    .padding(.top, 14 * m.ratio)
            }
            .padding(.horizontal, m.sideMargin)
            .padding(.bottom, m.bottomMargin + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .shadow(color: .black.opacity(0.16), radius: 5, y: 1)
        }
    }

    private var compact: some View {
        HStack(spacing: 14) {
            EmptyCover(sources: player.installedSources)
                .frame(width: Theme.compactArtSide, height: Theme.compactArtSide)
                .clipShape(RoundedRectangle(cornerRadius: Theme.compactArtRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.compactArtRadius, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text("Nothing Playing")
                    .font(Theme.compactTitle)
                    .foregroundStyle(Theme.primary)
                Text(detail)
                    .font(Theme.compactSubtitle)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 2)
                // Three labeled buttons don't fit beside the cover: glyphs instead.
                Group {
                    if player.installedSources.count > 2 {
                        HStack(spacing: 6) {
                            ForEach(player.installedSources) { kind in
                                SourceButton(kind: kind, style: .glyph) { player.open(kind) }
                            }
                        }
                    } else {
                        buttons(height: 28, fill: false)
                    }
                }
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.compactInset)
    }

    /// Same frame as the open Island while playing: thumbnail and text up top, then one
    /// row where the progress bar and transport would be.
    private var island: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                EmptyCover(sources: player.installedSources)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.thumbRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.thumbRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing Playing")
                        .font(Theme.islandOpenTitle)
                        .foregroundStyle(Theme.primary)
                    Text(detail)
                        .font(Theme.compactSubtitle)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            buttons(height: 34, fill: true)
                .padding(.bottom, 6)
        }
    }

    private func mini(side: CGFloat) -> some View {
        ZStack {
            EmptyCover(sources: player.installedSources, noteScale: 0.34, noteOpacity: 0.3, noteLift: 0.12)
            VStack {
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ForEach(player.installedSources) { kind in
                        SourceButton(kind: kind, style: .glyph) { player.open(kind) }
                    }
                }
                .padding(.bottom, max(8, side * 0.08))
            }
        }
    }

    /// One glass button per installed app. `fill`: they share the row's width.
    private func buttons(height: CGFloat, fill: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(player.installedSources) { kind in
                SourceButton(kind: kind, style: .label(height: height, fill: fill)) { player.open(kind) }
            }
        }
    }

    private var detail: String { EmptyStateView.detail(for: player.installedSources) }

    static func detail(for sources: [SourceKind]) -> String {
        let names = sources.map(\.displayName)
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " or " + names.last! : names.first ?? "Music"
        if sources.contains(where: \.isRunning) { return "Play something in \(list)." }
        return names.count > 1 ? "\(names.joined(separator: " and ")) are closed." : "\(list) is closed."
    }
}

/// The closed Island with nothing loaded: the empty cover, the title and why, and the
/// glyphs of the apps it can open where the progress ring goes.
struct EmptyIslandRow: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        HStack(spacing: 10) {
            EmptyCover(sources: player.installedSources)
                .frame(width: Theme.islandThumb, height: Theme.islandThumb)
                .clipShape(RoundedRectangle(cornerRadius: Theme.islandThumbRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.islandThumbRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 0) {
                Text("Nothing Playing")
                    .font(Theme.islandTitle)
                    .foregroundStyle(Theme.primary)
                    .frame(height: 16)
                Text(EmptyStateView.detail(for: player.installedSources))
                    .font(Theme.islandSubtitle)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(height: 14)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(player.installedSources) { kind in
                    SourceGlyph(kind: kind, size: 11)
                        .opacity(kind.isRunning ? 1 : 0.55)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The cover of nothing: graphite, lit faintly from opposite corners by each installed
/// app's color (Music's pink from the top left, Spotify's green from the bottom right),
/// with a note in the middle. Fills whatever frame it gets; static.
struct EmptyCover: View {
    let sources: [SourceKind]
    /// Note size relative to the shorter side, and how strongly it shows.
    var noteScale: CGFloat = 0.42
    var noteOpacity: Double = 0.55
    /// How far above center the note sits, relative to the height (room for text below).
    var noteLift: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let reach = max(geo.size.width, geo.size.height) * 0.95
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.20, green: 0.20, blue: 0.23), Color(red: 0.08, green: 0.08, blue: 0.09)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if sources.contains(.music) {
                    RadialGradient(
                        colors: [Theme.sourceColor(.music).opacity(0.30), .clear],
                        center: .topLeading, startRadius: 0, endRadius: reach
                    )
                }
                if sources.contains(.spotify) {
                    RadialGradient(
                        colors: [Theme.sourceColor(.spotify).opacity(0.18), .clear],
                        center: .bottomTrailing, startRadius: 0, endRadius: reach
                    )
                }
                if sources.contains(.podcasts) {
                    RadialGradient(
                        colors: [Theme.sourceColor(.podcasts).opacity(0.20), .clear],
                        center: .bottomLeading, startRadius: 0, endRadius: reach * 0.8
                    )
                }
                LinearGradient(colors: [Color.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center)
                Image(systemName: "music.note")
                    .font(.system(size: side * noteScale, weight: .medium))
                    .foregroundStyle(Color.white.opacity(noteOpacity))
                    .offset(y: -geo.size.height * noteLift)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

/// A glass button with the app's own glyph. `.label`: glyph and name in a capsule (full
/// width of its share of the row when `fill`). `.glyph`: the glyph alone in a glass circle.
private struct SourceButton: View {
    enum Style {
        case label(height: CGFloat, fill: Bool)
        case glyph
    }

    let kind: SourceKind
    let style: Style
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            switch style {
            case .glyph:
                SourceGlyph(kind: kind, size: 13)
                    .frame(width: 26, height: 26)
                    .background(glass(Circle()))
                    .contentShape(Circle())
            case let .label(height, fill):
                HStack(spacing: 7) {
                    SourceGlyph(kind: kind, size: (height * 0.46).rounded())
                    Text(kind.displayName)
                        .font(.system(size: max(12, (height * 0.43).rounded()), weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: fill ? .infinity : nil)
                .frame(height: height)
                .background(glass(Capsule()))
                .contentShape(Capsule())
            }
        }
        .buttonStyle(PressableStyle())
        .help(kind.isRunning ? "Show \(kind.displayName)" : "Open \(kind.displayName)")
        .onHover { hovering = $0 }
        .animation(Theme.fade, value: hovering)
    }

    /// The same glass as the capsules over the artwork: a light veil, a rim brighter on top.
    private func glass<S: InsettableShape>(_ shape: S) -> some View {
        shape.fill(Color.white.opacity(hovering ? 0.20 : 0.12))
            .background(shape.fill(.ultraThinMaterial))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.30), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            )
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
