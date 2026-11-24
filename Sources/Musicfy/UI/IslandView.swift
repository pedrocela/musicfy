import SwiftUI

/// Island mode: a 300 × 44 pill under the menu bar. Resting the mouse on it opens it
/// downward to 416 × 136, controls and all (`IslandOpenView`).
///
/// The window is always the size of the open Island (plus room for the shadow); what
/// animates is the pill inside. Clicks pass through the transparent part.
struct IslandView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    /// The text and ring fade in once the pill is in place (after the morph from the panel).
    @State private var settled = false

    @Environment(\.colorScheme) private var scheme
    private var expanded: Bool { panel.islandExpanded }
    private var accent: Color { Color(nsColor: player.palette.tint) }
    /// The accent over the cover's dark veil: the bright one in both appearances.
    private var coverAccent: Color { Color(nsColor: player.palette.accent) }
    private var playing: Bool { player.state?.isPlaying ?? false }

    var body: some View {
        let lyricsMode = player.showsIslandLyrics
        let size = expanded ? Theme.islandExpanded : (lyricsMode
            ? CGSize(width: panel.islandLyricsWidth, height: Theme.islandLyrics.height)
            : Theme.islandCollapsed)
        // Closed it's a full pill; open, the same soft corner as compact.
        let shape = RoundedRectangle(cornerRadius: Theme.radius(for: size), style: .continuous)
        VStack(alignment: panel.islandAlignment.horizontal, spacing: 0) {
            ZStack(alignment: .top) {
                // Tinted with the artwork's color, like compact.
                // Follows the system appearance: deep in dark mode, pale in light mode.
                Color(nsColor: player.palette.backdrop)
                    .animation(Theme.crossfade, value: player.palette)
                LinearGradient(colors: [Theme.sheen, .clear], startPoint: .top, endPoint: .center)
                    .allowsHitTesting(false)
                // Closed, the cover is the pill: its middle band from edge to edge, under a
                // veil: darker toward the left, where the title sits. With lyrics, a blur of its colors.
                if !expanded, player.state != nil {
                    ZStack {
                        CrossfadingArtwork(player: player)
                            // With lyrics there's no picture, only its colors: the cover
                            // far out of focus, enlarged so the soft edge stays outside the pill.
                            .saturation(playing ? (lyricsMode ? 1.4 : 1) : 0.3)
                            .brightness(playing ? 0 : -0.12)
                            .blur(radius: lyricsMode ? Theme.islandLyricsBlur : 0, opaque: false)
                            .scaleEffect(lyricsMode ? 1.5 : 1)
                            .animation(Theme.islandSpring, value: lyricsMode)
                        // With lyrics the line is centered, so the veil is even end to end.
                        LinearGradient(
                            stops: lyricsMode ? [
                                .init(color: .black.opacity(0.38), location: 0),
                                .init(color: .black.opacity(0.38), location: 1),
                            ] : [
                                .init(color: .black.opacity(0.86), location: 0),
                                .init(color: .black.opacity(0.55), location: 0.6),
                                .init(color: .black.opacity(0.08), location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity.animation(Theme.fade))
                    .animation(Theme.fade, value: playing)
                }
                IslandDragArea()
                if expanded {
                    expandedContent
                        .transition(.asymmetric(
                            insertion: .opacity.animation(Theme.islandContentIn),
                            removal: .opacity.animation(.easeOut(duration: 0.08))
                        ))
                } else {
                    collapsedContent
                        // White over the cover in both appearances.
                        .environment(\.colorScheme, player.state == nil ? scheme : .dark)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(Theme.islandContentIn),
                            removal: .opacity.animation(.easeOut(duration: 0.08))
                        ))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.islandStroke, lineWidth: 0.5))
            // The shadow comes from a plain shape behind the pill (the tint above covers it).
            // A shadow of the pill itself is redrawn every time anything inside it moves.
            .background(
                // Soft like a macOS window's shadow: a wide haze on every side (top included),
                // a closer layer for depth and a faint contact line around the 6 pt corners.
                // All of it fits inside the window's margins (Theme.islandShadow*).
                shape
                    .fill(Color.black)
                    .shadow(color: Theme.islandShadowAmbient.opacity(expanded ? 1 : 0.6), radius: expanded ? 22 : 10, y: expanded ? 12 : 4)
                    .shadow(color: Theme.islandShadowNear.opacity(expanded ? 1 : 0.8), radius: expanded ? 6 : 3, y: expanded ? 3 : 1)
                    .shadow(color: Theme.islandShadowContact, radius: 0.5, y: 0)
            )
            // Pulled down, it grows a little: it's about to become the artwork. No darker rim:
            // in light mode it read as a hard edge. Kept small so the shadow fits the margins.
            .scaleEffect(1 + 0.04 * panel.islandPull, anchor: .top)
            .animation(Theme.islandSpring, value: expanded)
            .animation(Theme.islandSpring, value: lyricsMode)
            // The pill follows the line with the line's own spring, so width and text move as one.
            .animation(Theme.lyricLineMove, value: panel.islandLyricsWidth)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.islandShadowSide)
        .padding(.top, Theme.islandShadowTop)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: Alignment(horizontal: panel.islandAlignment.horizontal, vertical: .top)
        )
        .environment(\.marqueeOnLayer, true)
        .onAppear {
            withAnimation(Theme.smooth.delay(0.03)) { settled = true }
        }
    }

    // MARK: Closed

    @ViewBuilder
    private var collapsedContent: some View {
        if player.state == nil {
            EmptyIslandRow(player: player)
                .opacity(settled ? 1 : 0)
                .padding(.leading, Theme.islandThumbInset)
                .padding(.trailing, 12)
                .frame(width: Theme.islandCollapsed.width, height: Theme.islandCollapsed.height)
        } else if player.showsIslandLyrics {
            lyricsRow
                .transition(.opacity.animation(Theme.islandContentIn))
        } else {
            playingRow
                .transition(.opacity.animation(Theme.islandContentIn))
        }
    }

    /// Lyrics on: only the line being sung, large and centered over the cover's blurred colors, with the cover itself at the left end; the progress is a hairline along the bottom.
    private var lyricsRow: some View {
        HStack(spacing: 0) {
            // The cover itself, sharp, at the left end; its blurred colors fill the rest.
            CrossfadingArtwork(player: player)
                .saturation(playing ? 1 : 0.3)
                .brightness(playing ? 0 : -0.12)
                .animation(Theme.fade, value: playing)
                .frame(width: Theme.islandLyricsCover, height: Theme.islandLyricsCover)
                .clipped()
                .allowsHitTesting(false)
                .opacity(settled ? 1 : 0)
            Group {
                if let lyrics = player.lyrics, lyrics.isSynced {
                    let beats = IslandLyricBeats.shared.beats(for: lyrics.lines)
                    PlaybackTimeline(clock: player.clock) { now in
                        IslandLyrics(
                            lines: beats,
                            // Ahead of the song by about the crossfade and the pill resize, so the line is crisp by the time it's sung.
                            current: IslandLyricBeats.index(in: beats, at: player.lyricsPosition(at: now, lead: 0.85)) ?? -1,
                            dimmed: !playing,
                            // Before the first line: the song's title and artist instead of
                            // "♪", so the start says what's playing. Later breaks stay "♪".
                            intro: announcement,
                            onLine: fitIsland
                        )
                        .equatable()
                    }
                } else {
                    // While the lyrics load: the song's title and artist, quietly, where
                    // the line goes.
                    Text(announcement)
                        .font(Theme.islandLyric)
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .task(id: announcement) { fitIsland(to: announcement) }
                }
            }
            // Even on both sides, so the line sits in the middle of the room beside the cover.
            .padding(.horizontal, Theme.islandLyricsMargins / 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .opacity(settled ? 1 : 0)
        }
        // The song's progress: a hairline along the whole bottom edge.
        .overlay(alignment: .bottom) {
            PlaybackTimeline(clock: player.clock) { _ in
                ProgressBarLayer(
                    fraction: player.progressFraction(),
                    rate: player.progressRate,
                    fill: playing ? coverAccent : Theme.quaternary,
                    track: Color.white.opacity(0.18)
                )
            }
            .frame(height: 2)
            .allowsHitTesting(false)
            .opacity(settled ? 1 : 0)
        }
        .frame(width: panel.islandLyricsWidth, height: Theme.islandLyrics.height)
        .onDisappear { fitIsland(to: nil) }
    }

    private var announcement: String {
        guard let state = player.state else { return "" }
        return state.artist.isEmpty ? state.title : "\(state.title) · \(state.artist)"
    }

    /// Widens the lyrics Island when the line being sung doesn't fit, and narrows it back
    /// to the usual width when it does. Past the widest, the line shrinks to fit.
    private func fitIsland(to line: String?) {
        var width = Theme.islandLyrics.width
        if let line, !line.isEmpty {
            // The pill hugs the line: no dead space after a short one.
            let text = IslandLyricBeats.width(of: line)
            width = min(Theme.islandLyricsMaxWidth, max(Theme.islandLyricsMinWidth, ceil(text) + Theme.islandLyricsChrome + 2))
        }
        if panel.islandLyricsWidth != width { panel.islandLyricsWidth = width }
    }

    private var playingRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                if let state = player.state {
                    MarqueeText(
                        text: state.title,
                        font: Theme.islandTitle,
                        color: playing ? Theme.primary : Theme.primary.opacity(0.85),
                        height: 16,
                        trailingFade: 36,
                        scrolls: false
                    )
                    if playing {
                        SubtitleLine(player: player, font: Theme.islandSubtitle, height: 14, text: islandSubtitle(state), showsLyric: true)
                    } else {
                        Text("Paused")
                            .font(Theme.islandSubtitle)
                            .foregroundStyle(Theme.quaternary)
                            .frame(height: 14)
                    }
                } else {
                    Text("Nothing Playing")
                        .font(Theme.islandTitle)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .id(player.state?.trackKey ?? "")
            .transition(.opacity.combined(with: .offset(y: 6)))
            .animation(Theme.crossfade, value: player.state?.trackKey)
            .allowsHitTesting(false)
            .opacity(settled ? 1 : 0)

            if player.state != nil, !playing {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .opacity(settled ? 1 : 0)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .padding(.leading, Theme.islandTextInset)
        .padding(.trailing, 16)
        .frame(width: Theme.islandCollapsed.width, height: Theme.islandCollapsed.height)
        // The song's progress: a hairline along the whole bottom edge, as with lyrics.
        .overlay(alignment: .bottom) {
            if player.state != nil {
                EdgeProgress(player: player, fill: playing ? coverAccent : Theme.quaternary, height: 2)
                    .opacity(settled ? 1 : 0)
            }
        }
        .animation(Theme.fade, value: playing)
    }

    private func islandSubtitle(_ state: PlayerState) -> String {
        let artist = state.artist.isEmpty ? state.album : state.artist
        return settings.forcedSource == nil && SourceKind.allCases.filter(\.isRunning).count > 1
            ? "\(artist) · \(state.source.displayName)"
            : artist
    }

    // MARK: Open

    /// Cover-led: the cover floats and its colors tint the Island (`IslandOpenView`).
    @ViewBuilder
    private var expandedContent: some View {
        Group {
            if player.state == nil {
                EmptyStateView(player: player)
            } else {
                IslandOpenView(player: player, settings: settings, panel: panel)
            }
        }
        .frame(width: Theme.islandExpanded.width, height: Theme.islandExpanded.height, alignment: .top)
    }

    /// Clicking the cover brings the app that's playing to the front, as in compact.
    private func thumbnail(side: CGFloat, radius: CGFloat) -> some View {
        IslandCover(player: player, side: side, radius: radius)
    }
}

/// The lyric lines as the closed Island shows them: a long line (over 400 pt of text)
/// plays in two beats. It splits at the punctuation nearest its middle (a comma usually
/// separates the beats well), else at the space nearest the middle, and the second half
/// comes in after its share of the line's time, rolling up like a new line.
@MainActor
final class IslandLyricBeats {
    static let shared = IslandLyricBeats()
    private var source: [Lyrics.Line] = []
    private var result: [Lyrics.Line] = []

    /// The lyric's font (Bold italic), to measure lines as they'll be drawn.
    private static let font: NSFont = {
        let base = NSFont.systemFont(ofSize: Theme.islandLyricSize, weight: .bold)
        let italic = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: italic, size: Theme.islandLyricSize) ?? base
    }()
    private static var room: CGFloat { Theme.islandLyricsMaxWidth - Theme.islandLyricsChrome - 2 }
    /// Lines wider than this (about half the screen's worth of pill) read better in two beats,
    /// even when they'd fit in the widest pill.
    private static let splitAbove: CGFloat = 400

    static func width(of text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    func beats(for lines: [Lyrics.Line]) -> [Lyrics.Line] {
        if lines == source { return result }
        source = lines
        result = []
        for (i, line) in lines.enumerated() {
            guard Self.width(of: line.text) > Self.splitAbove, let (first, second) = Self.split(line.text) else {
                result.append(line)
                continue
            }
            // The time to the next line often includes a pause after this one is sung: spread
            // the halves over about how long the words take (~0.11 s a character), not the
            // whole gap, or the second half comes in late.
            let gap = (i + 1 < lines.count ? lines[i + 1].time : line.time + 6) - line.time
            let sung = min(gap, Double(line.text.count) * 0.11 + 0.3)
            let share = Double(first.count) / Double(max(1, first.count + second.count))
            result.append(Lyrics.Line(time: line.time, text: first))
            result.append(Lyrics.Line(time: line.time + sung * share, text: second))
        }
        return result
    }

    static func index(in lines: [Lyrics.Line], at position: Double) -> Int? {
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }

    /// Where to cut: punctuation nearest the middle whose halves both fit (and neither is
    /// under a quarter of the line), else the space nearest the middle.
    private static func split(_ text: String) -> (String, String)? {
        let chars = Array(text)
        let middle = chars.count / 2
        func halves(at cut: Int) -> (String, String)? {
            let a = String(chars[..<cut]).trimmingCharacters(in: .whitespaces)
            let b = String(chars[cut...]).trimmingCharacters(in: .whitespaces)
            return a.isEmpty || b.isEmpty ? nil : (a, b)
        }
        let punctuation: Set<Character> = [",", ";", ":", "—", "–", "?", "!", ")"]
        let marks = chars.indices.filter { punctuation.contains(chars[$0]) && $0 + 1 < chars.count }
        for mark in marks.sorted(by: { abs($0 - middle) < abs($1 - middle) }) {
            // Not so near an end that one beat is a word or two.
            guard min(mark + 1, chars.count - mark - 1) * 4 >= chars.count else { continue }
            if let (a, b) = halves(at: mark + 1), width(of: a) <= room, width(of: b) <= room { return (a, b) }
        }
        let spaces = chars.indices.filter { chars[$0] == " " }
        guard let space = spaces.min(by: { abs($0 - middle) < abs($1 - middle) }) else { return nil }
        return halves(at: space)
    }
}

/// The closed Island's karaoke: only the current line, large and centered. When the line
/// changes, the new one crossfades in place and the pill resizes to fit it.
private struct IslandLyrics: View, Equatable {
    let lines: [Lyrics.Line]
    /// -1 before the first line.
    let current: Int
    let dimmed: Bool
    /// Shown before the first line instead of "♪": the song's title and artist.
    let intro: String
    /// Told the line being sung each time it changes, so the pill can fit it.
    let onLine: @MainActor (String?) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.current == b.current && a.dimmed == b.dimmed && a.intro == b.intro && a.lines == b.lines
    }

    var body: some View {
        // Only the line being sung, centered. A new line crossfades in place while the
        // pill grows or shrinks around it: nothing rolls up.
        ZStack {
            Text(text(at: current))
                .font(Theme.islandLyric)
                .foregroundStyle(Theme.primary)
                .opacity(dimmed ? 0.6 : 1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .id(current)
                // The old line leaves as the pill starts to move; the new one arrives once
                // the width has nearly settled, so no text is seen cut by the edge.
                .transition(.asymmetric(
                    insertion: .opacity.animation(Theme.lyricLineIn),
                    removal: .opacity.animation(Theme.lyricLineOut)
                ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // What's shown, "♪" included: an instrumental break gets the narrowest pill, not the
        // default width.
        .task(id: "\(current)|\(intro)") { onLine(text(at: current)) }
        .animation(Theme.fade, value: dimmed)
    }

    private func text(at index: Int) -> String {
        if index < 0, !intro.isEmpty { return intro }
        guard index >= 0, index < lines.count else { return "♪" }
        let text = lines[index].text
        return text.isEmpty ? "♪" : text
    }
}

private struct IslandCover: View {
    @ObservedObject var player: PlayerController
    let side: CGFloat
    let radius: CGFloat
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Button {
            if let kind = player.state?.source { player.open(kind) }
        } label: {
            ZStack { CrossfadingArtwork(player: player) }
                .frame(width: side, height: side)
                .overlay(Color.black.opacity(hovering ? 0.15 : 0))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.ink.opacity(hovering ? 0.25 : 0.1), lineWidth: 0.5))
                .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .help(player.state.map { "Open \($0.source.displayName)" } ?? "")
        .onHover { hovering = $0 }
        .animation(Theme.fade, value: hovering)
    }
}

/// At the right of the closed Island: a ring with the song's progress and, inside,
/// three dancing bars (or a play icon when paused).
private struct ProgressRing: View {
    @ObservedObject var player: PlayerController
    let playing: Bool
    let accent: Color

    var body: some View {
        // No timeline here: Core Animation runs the ring to the end of the song, and it's
        // set again only when the player publishes something new.
        ZStack {
            Circle()
                .stroke(Theme.ink.opacity(0.12), lineWidth: 2)
            ProgressRingLayer(
                fraction: player.progressFraction(),
                rate: player.progressRate,
                color: playing ? accent : Theme.quaternary
            )
            ZStack {
                if playing {
                    Equalizer(color: accent)
                        .frame(width: 9, height: 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.5)))
                } else {
                    PlayTriangle()
                        .fill(Theme.secondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.5)))
                }
            }
            .animation(Theme.smooth, value: playing)
        }
        .frame(width: 22, height: 22)
        .animation(Theme.crossfade, value: playing)
        .allowsHitTesting(false)
    }
}

/// The play glyph of the closed Island, drawn by hand so it sits centered in the ring.
///
/// It fills the ring's frame and puts the triangle's centroid (a third of the way in from
/// the flat side) on the center, not its box: centered by the box, the heavy flat side
/// makes it read as shifted left. Drawing it in the full frame also keeps pixel snapping
/// from eating a small offset.
private struct PlayTriangle: Shape {
    private static let width: CGFloat = 8
    private static let height: CGFloat = 9
    private static let cornerRadius: CGFloat = 1.3

    func path(in rect: CGRect) -> Path {
        let left = rect.midX - Self.width / 3
        let right = rect.midX + Self.width * 2 / 3
        let top = rect.midY - Self.height / 2
        let bottom = rect.midY + Self.height / 2
        let a = CGPoint(x: left, y: top)
        let b = CGPoint(x: right, y: rect.midY)
        let c = CGPoint(x: left, y: bottom)
        let r = Self.cornerRadius
        var path = Path()
        // Start halfway down the flat side so every corner gets the same rounding.
        path.move(to: CGPoint(x: left, y: rect.midY))
        path.addArc(tangent1End: a, tangent2End: b, radius: r)
        path.addArc(tangent1End: b, tangent2End: c, radius: r)
        path.addArc(tangent1End: c, tangent2End: a, radius: r)
        path.closeSubpath()
        return path
    }
}

/// Three bars bouncing at different rhythms.
///
/// Drawn with Core Animation: the bars move in the window server, so the app doesn't
/// wake up 30 times a second to redraw them while the Island just sits there playing.
private struct Equalizer: NSViewRepresentable {
    let color: Color

    func makeNSView(context: Context) -> EqualizerView { EqualizerView() }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.color = color.resolve(in: context.environment).cgColor
    }
}

final class EqualizerView: NSView {
    /// Each bar: cycles per second and where in its cycle it starts.
    private static let bars: [(speed: Double, phase: Double)] = [(1.05, 0.0), (0.8, 0.4), (1.3, 0.7)]
    private static let barWidth: CGFloat = 2
    private static let spacing: CGFloat = 1.5
    private static let low: CGFloat = 3
    private static let high: CGFloat = 9

    private let barLayers: [CALayer] = EqualizerView.bars.map { _ in CALayer() }

    var color: CGColor = NSColor.white.cgColor {
        didSet {
            guard color != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for bar in barLayers { bar.backgroundColor = color }
            CATransaction.commit()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in barLayers {
            bar.cornerRadius = Self.barWidth / 2
            bar.backgroundColor = color
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        let count = CGFloat(Self.bars.count)
        return NSSize(width: count * Self.barWidth + (count - 1) * Self.spacing, height: 10)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let total = intrinsicContentSize.width
        var x = (bounds.width - total) / 2
        for bar in barLayers {
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.low)
            bar.position = CGPoint(x: x + Self.barWidth / 2, y: bounds.midY)
            x += Self.barWidth + Self.spacing
        }
        CATransaction.commit()
        startIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startIfNeeded()
    }

    /// The same wave as before: height = 3 + 6 × (0.5 + 0.5 · sin(2π · (t · speed + phase))).
    /// Low to high and back with a sine-shaped ease is that sine.
    private func startIfNeeded() {
        guard window != nil else { return }
        for (bar, spec) in zip(barLayers, Self.bars) where bar.animation(forKey: "wave") == nil {
            let period = 1 / spec.speed
            let wave = CABasicAnimation(keyPath: "bounds.size.height")
            wave.fromValue = Self.low
            wave.toValue = Self.high
            wave.duration = period / 2
            wave.autoreverses = true
            wave.repeatCount = .infinity
            wave.timingFunction = CAMediaTimingFunction(controlPoints: 0.37, 0, 0.63, 1)
            // The sine is lowest a quarter cycle before its phase starts.
            wave.timeOffset = ((spec.phase + 0.25).truncatingRemainder(dividingBy: 1)) * period
            wave.isRemovedOnCompletion = false
            bar.add(wave, forKey: "wave")
        }
    }
}

/// Island background: right click opens the menu; dragging moves it along the top edge
/// and on release it snaps left, center or right. Pulled down, it becomes the artwork.
private struct IslandDragArea: NSViewRepresentable {
    final class DragView: NSView, WindowDragSurface {
        private var startMouse = NSPoint.zero
        private var startOrigin = NSPoint.zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            startMouse = NSEvent.mouseLocation
            startOrigin = window?.frame.origin ?? .zero
        }

        /// Follows the mouse sideways, and downward too (to turn it into the artwork).
        /// It doesn't move up: it's already against the menu bar.
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

        /// A drag that started on the Island's text or buttons: same as from the background.
        func takeOverDrag(from mouseDown: NSEvent) {
            self.mouseDown(with: mouseDown)
            window?.trackEvents(
                matching: [.leftMouseDragged, .leftMouseUp],
                timeout: NSEvent.foreverDuration,
                mode: .eventTracking
            ) { [weak self] event, stop in
                guard let self, let event else { return }
                if event.type == .leftMouseUp {
                    self.mouseUp(with: event)
                    stop.pointee = true
                } else {
                    self.mouseDragged(with: event)
                }
            }
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}
