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
            // Pulled down, it grows a little and its rim brightens: it's about to become the artwork.
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
        .onAppear {
            withAnimation(Theme.smooth.delay(0.03)) { settled = true }
        }
    }

    // MARK: Closed

    private var collapsedContent: some View {
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
                EmptyStateView(player: player)
                    .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    thumbnail(side: 56, radius: Theme.islandThumbRadius)
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

/// Three bars bouncing at different rhythms.
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
