import SwiftUI

/// Island mode: a 300 × 44 pill under the menu bar. Resting the mouse on it opens it
/// downward (380 × 160) with the controls.
///
/// The window is always the size of the open Island (plus room for the shadow); what
/// animates is the pill inside. Clicks pass through the transparent part.
struct IslandView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    /// The text and ring fade in once the pill is in place (after the morph from the panel).
    @State private var settled = false

    private var expanded: Bool { panel.islandExpanded }
    private var accent: Color { Color(nsColor: player.palette.accent) }
    private var playing: Bool { player.state?.isPlaying ?? false }

    var body: some View {
        let size = expanded ? Theme.islandExpanded : Theme.islandCollapsed
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        VStack(alignment: panel.islandAlignment.horizontal, spacing: 0) {
            ZStack(alignment: .top) {
                // Tinted with the artwork's color, like compact.
                Color(nsColor: player.palette.background)
                    .animation(Theme.crossfade, value: player.palette)
                LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center)
                    .allowsHitTesting(false)
                IslandDragArea()
                if expanded {
                    expandedContent
                        .transition(.asymmetric(
                            insertion: .opacity.animation(Theme.islandContentIn),
                            removal: .opacity.animation(.easeOut(duration: 0.08))
                        ))
                } else {
                    collapsedContent
                        .transition(.asymmetric(
                            insertion: .opacity.animation(Theme.islandContentIn),
                            removal: .opacity.animation(.easeOut(duration: 0.08))
                        ))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.islandStroke, lineWidth: 0.5))
            // Pulled down, it grows a little and its rim brightens: it's about to become the artwork.
            .overlay(shape.strokeBorder(Color.white.opacity(0.28 * panel.islandPull), lineWidth: 1))
            // The shadow comes from a plain shape behind the pill (the tint above covers it).
            // A shadow of the pill itself is redrawn every time anything inside it moves.
            .background(
                shape
                    .fill(Color.black)
                    .shadow(color: .black.opacity(expanded ? 0.32 : 0.22), radius: expanded ? 20 : 10, y: expanded ? 10 : 4)
            )
            .scaleEffect(1 + 0.08 * panel.islandPull, anchor: .top)
            .animation(Theme.islandSpring, value: expanded)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.islandShadowMargin)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: Alignment(horizontal: panel.islandAlignment.horizontal, vertical: .top)
        )
        .environment(\.colorScheme, .dark)
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
        } else {
            playingRow
        }
    }

    private var playingRow: some View {
        HStack(spacing: 10) {
            thumbnail(side: Theme.islandThumb, radius: Theme.islandThumbRadius)
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
                        Text("Paused")
                            .font(Theme.islandSubtitle)
                            .foregroundStyle(Color.white.opacity(0.55))
                            .frame(height: 14)
                    }
                } else {
                    Text("Nothing Playing")
                        .font(Theme.islandTitle)
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .id(player.state?.trackKey ?? "")
            .transition(.opacity.combined(with: .offset(y: 6)))
            .animation(Theme.crossfade, value: player.state?.trackKey)
            .allowsHitTesting(false)
            .opacity(settled ? 1 : 0)

            if player.state != nil {
                ProgressRing(player: player, playing: playing, accent: accent)
                    .opacity(settled ? 1 : 0)
                    .scaleEffect(settled ? 1 : 0.6)
            }
        }
        .padding(.leading, Theme.islandThumbInset)
        .padding(.trailing, 11)
        .frame(width: Theme.islandCollapsed.width, height: Theme.islandCollapsed.height)
    }

    private func islandSubtitle(_ state: PlayerState) -> String {
        let artist = state.artist.isEmpty ? state.album : state.artist
        return settings.forcedSource == nil && SourceKind.allCases.filter(\.isRunning).count > 1
            ? "\(artist) · \(state.source.displayName)"
            : artist
    }

    // MARK: Open

    private var expandedContent: some View {
        VStack(spacing: 0) {
            if player.state == nil {
                EmptyStateView(player: player, placement: .island)
                    .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    thumbnail(side: 56, radius: Theme.thumbRadius)
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
                .stroke(Color.white.opacity(0.12), lineWidth: 2)
            ProgressRingLayer(
                fraction: player.progressFraction(),
                rate: player.progressRate,
                color: playing ? accent : Color.white.opacity(0.55)
            )
            ZStack {
                if playing {
                    Equalizer(color: accent)
                        .frame(width: 9, height: 10)
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
        .allowsHitTesting(false)
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
        view.color = NSColor(color).cgColor
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
    final class DragView: NSView {
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
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}
