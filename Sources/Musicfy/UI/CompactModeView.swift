import SwiftUI

/// Compact mode (320 × 136): the cover is the window. It fills the whole surface, cropped
/// to its middle band, under a veil that darkens toward the left, where the text sits.
/// At rest it's quiet: title, artist and a line of progress along the bottom edge.
/// On hover the top buttons, the times and the transport fade in.
/// (The open Island has its own layout: `IslandOpenView`.)
/// The text stays white over the cover in both appearances, as in artwork mode.
struct CompactModeView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    private var showControls: Bool { panel.isHovering || panel.volumeOpen }
    private var paused: Bool { player.state?.isPlaying == false }

    var body: some View {
        ZStack {
            Color(nsColor: player.palette.background)
            // Paused: the cover loses its color, so it reads at a glance.
            CrossfadingArtwork(player: player)
                .saturation(paused ? 0.3 : 1)
                .brightness(paused ? -0.12 : 0)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.84), location: 0),
                    .init(color: .black.opacity(0.5), location: 0.55),
                    .init(color: .black.opacity(0.08), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .allowsHitTesting(false)
            // With the controls out, the veil evens out so they read across the whole width.
            Color.black.opacity(showControls ? 0.34 : 0)
                .allowsHitTesting(false)
            WindowDragArea(onDoubleClick: panel.actions.toggleArtworkCompact)

            details
                .padding(.horizontal, 20)
                .frame(height: Theme.compactArtSide)
                .frame(maxHeight: .infinity)

            if !showControls {
                EdgeProgress(player: player, fill: Color(nsColor: player.palette.accent))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.marqueeOnLayer, true)
        .animation(Theme.smooth, value: showControls)
        .animation(Theme.fade, value: paused)
    }

    /// Title and artist; on hover the top buttons beside them and the times and transport below.
    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            // At rest the title sits in the middle; on hover it rises to make room for the controls.
            if !showControls { Spacer(minLength: 0) }
            HStack(alignment: .top, spacing: 8) {
                title
                if showControls {
                    topButtons
                        .transition(.opacity)
                } else if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
            if showControls {
                controls
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
    }

    /// Lyrics, Up Next, volume and the "…" menu, at the top right.
    private var topButtons: some View {
        HStack(spacing: 0) {
            ToolbarIcons(
                player: player,
                settings: settings,
                panel: panel,
                iconSize: 12,
                cell: 22,
                tint: Color.white.opacity(0.92),
                includesOutput: false
            )
            Button(action: panel.actions.showMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help("More Options")
        }
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        .padding(.trailing, -6)
        .fixedSize()
    }

    private var title: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 2) {
                // At rest a long title stays still, cut off with the fade; it scrolls on hover.
                MarqueeText(text: player.state?.title ?? "", font: Theme.compactTitle, color: Theme.primary, height: 19, scrolls: showControls)
                SubtitleLine(player: player, font: Theme.compactSubtitle, height: 16, showsLyric: false)
            }
            .id(player.state?.trackKey ?? "")
            .transition(.opacity)
        }
        .animation(Theme.crossfade, value: player.state?.trackKey)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            ZStack {
                if panel.volumeOpen {
                    VolumeBar(player: player).transition(.opacity)
                } else {
                    TimeBar(player: player).transition(.opacity)
                }
            }
            .animation(Theme.fade, value: panel.volumeOpen)
            TransportRow(player: player, size: .small)
                .padding(.horizontal, -6) // the buttons' own air reaches the column's edges
        }
    }
}

/// Song progress at rest: a thin line along the window's bottom edge, in the cover's accent.
struct EdgeProgress: View {
    @ObservedObject var player: PlayerController
    var fill: Color
    var height: CGFloat = 3

    var body: some View {
        PlaybackTimeline(clock: player.clock) { _ in
            ProgressBarLayer(
                fraction: player.progressFraction(),
                rate: player.progressRate,
                fill: fill,
                track: Color.white.opacity(0.18)
            )
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }
}
