import SwiftUI

/// The open Island (on hover), cover-led: the cover floats on the left with its own shadow
/// and its colors bleed into the Island behind it, so every album paints it differently.
/// Beside it: title and artist with Lyrics and "…" at the top right; play in a solid circle
/// with previous and next beside it and the time at the right; a scrubbable bar at the bottom
/// (the volume takes its place while open).
struct IslandOpenView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    private static let cover: CGFloat = 108
    private static let radius: CGFloat = 5

    var body: some View {
        ZStack {
            // The cover's colors, blown up and blurred, over the Island's own tint.
            CrossfadingArtwork(player: player)
                .frame(width: Theme.islandExpanded.width, height: Theme.islandExpanded.width)
                .blur(radius: 44)
                .opacity(0.42)
                .frame(width: Theme.islandExpanded.width, height: Theme.islandExpanded.height)
                .clipped()
                .allowsHitTesting(false)

            HStack(spacing: 16) {
                cover
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    transport
                    Spacer(minLength: 0)
                    bar
                }
                .frame(height: Self.cover)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
        }
        .frame(width: Theme.islandExpanded.width, height: Theme.islandExpanded.height)
        .animation(Theme.fade, value: panel.volumeOpen)
    }

    /// Clicking it brings the app that's playing to the front.
    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        return Button {
            if let kind = player.state?.source { player.open(kind) }
        } label: {
            CrossfadingArtwork(player: player)
                .frame(width: Self.cover, height: Self.cover)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.coverStroke, lineWidth: 0.5))
                .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .shadow(color: .black.opacity(0.35), radius: 7, y: 4)
        .help(player.state.map { "Open \($0.source.displayName)" } ?? "")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(
                    text: player.state?.title ?? "",
                    font: .system(size: 16, weight: .bold),
                    color: Theme.primary,
                    height: 20
                )
                SubtitleLine(player: player, font: .system(size: 12, weight: .medium), height: 16, showsLyric: true)
            }
            .id(player.state?.trackKey ?? "")
            .transition(.opacity)
            .animation(Theme.crossfade, value: player.state?.trackKey)
            HStack(spacing: 0) {
                ToolbarIcons(
                    player: player,
                    settings: settings,
                    panel: panel,
                    iconSize: 12,
                    cell: 22,
                    tint: Theme.primary.opacity(0.8),
                    includesOutput: false
                )
                Button(action: panel.actions.showMenu) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.primary.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help("More Options")
            }
            .padding(.trailing, -4) // the buttons' own air reaches the edge
        }
    }

    /// Play first, in a solid circle you can't miss; previous and next beside it; the time
    /// at the right.
    private var transport: some View {
        let state = player.state
        let kind = state?.source ?? .music
        let playing = state?.isPlaying ?? false
        return HStack(spacing: 10) {
            Button(action: { player.playPause() }) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(nsColor: player.palette.backdrop))
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: playing ? 0 : 1) // the triangle's weight sits left of its box
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.primary))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help("Play/Pause")
            .padding(.trailing, 2)
            IconButton(symbol: kind.previousSymbol, size: 15, tint: Theme.primary.opacity(0.85), help: kind.previousHelp, action: { player.previous() })
            IconButton(symbol: kind.nextSymbol, size: 15, tint: Theme.primary.opacity(0.85), help: kind.nextHelp, action: { player.next() })
            Spacer(minLength: 0)
            PlaybackTimeline(clock: player.clock) { now in
                Text("\(TimeText.format(player.position(at: now))) / \(TimeText.format(state?.duration ?? 0))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.timeColor)
            }
        }
    }

    private var bar: some View {
        ZStack {
            if panel.volumeOpen {
                VolumeBar(player: player, fill: Theme.primary)
                    .transition(.opacity)
            } else {
                IslandScrubBar(player: player)
                    .transition(.opacity)
            }
        }
        .frame(height: 12)
    }
}

/// The song's progress, white, dragged to seek.
private struct IslandScrubBar: View {
    @ObservedObject var player: PlayerController
    @State private var dragFraction: Double?

    var body: some View {
        PlaybackTimeline(clock: player.clock) { _ in
            ScrubBar(
                fraction: dragFraction ?? player.progressFraction(),
                rate: dragFraction == nil ? player.progressRate : 0,
                fill: Theme.primary,
                onChange: { dragFraction = $0 },
                onCommit: { value in
                    player.seek(toFraction: value)
                    dragFraction = nil
                }
            )
        }
    }
}
