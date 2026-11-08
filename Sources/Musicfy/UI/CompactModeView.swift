import SwiftUI

/// Compact mode (320 × 136) on a background tinted with the artwork's color.
/// At rest it's quiet: a big cover, the title and artist, and a hairline of progress.
/// On hover the times, the transport and the top buttons (over the cover) fade in.
struct CompactModeView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    private var showControls: Bool { panel.isHovering || panel.volumeOpen }

    var body: some View {
        ZStack {
            Color(nsColor: player.palette.background)
                .animation(Theme.crossfade, value: player.palette)
            LinearGradient(colors: [Color.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
            WindowDragArea(onDoubleClick: panel.actions.toggleArtworkCompact)

            HStack(alignment: .top, spacing: 12) {
                CompactCover(player: player, settings: settings, panel: panel, showControls: showControls)
                    .frame(width: Theme.compactArtSide, height: Theme.compactArtSide)
                details
                    .frame(height: Theme.compactArtSide)
            }
            .padding(.leading, Theme.compactInset)
            .padding(.trailing, 14)
            .frame(maxHeight: .infinity)
        }
        .environment(\.marqueeOnLayer, true)
        .animation(Theme.smooth, value: showControls)
    }

    /// Title and artist; under them the hairline at rest, or the times and transport on hover.
    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            // At rest the title sits in the middle of the free space; on hover it rises
            // to the top to make room for the controls.
            if !showControls { Spacer(minLength: 0) }
            title
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                if showControls {
                    controls
                        .transition(.opacity.combined(with: .offset(y: 6)))
                } else {
                    Hairline(player: player)
                        .padding(.bottom, 1)
                        .transition(.opacity)
                }
            }
        }
    }

    private var title: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: player.state?.title ?? "", font: Theme.compactTitle, color: Theme.primary, height: 19)
                SubtitleLine(player: player, font: Theme.compactSubtitle, height: 16)
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

/// Song progress at rest: a thin line, no times.
private struct Hairline: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        PlaybackTimeline(clock: player.clock) { _ in
            ProgressBarLayer(
                fraction: player.progressFraction(),
                rate: player.progressRate,
                fill: Color.white.opacity(0.62),
                track: Color.white.opacity(0.14)
            )
        }
        .frame(height: 3)
        .allowsHitTesting(false)
    }
}

/// The cover. Clicking it brings the app that's playing to the front; on hover the top
/// buttons and the "…" menu appear along its bottom edge, over a soft veil.
private struct CompactCover: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel
    let showControls: Bool
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.compactArtRadius, style: .continuous)
        ZStack(alignment: .bottom) {
            Button {
                if let kind = player.state?.source { player.open(kind) }
            } label: {
                CrossfadingArtwork(player: player)
                    .overlay(Color.black.opacity(hovering ? 0.12 : 0))
                    .contentShape(shape)
            }
            .buttonStyle(CoverPressStyle())
            .help(player.state.map { "Open \($0.source.displayName)" } ?? "")
            .onHover { hovering = $0 }

            if showControls {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0),
                        .init(color: .black.opacity(0.5), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                .allowsHitTesting(false)
                .transition(.opacity)

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
                .padding(.bottom, 3)
                .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5).allowsHitTesting(false))
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        .animation(Theme.fade, value: hovering)
        .animation(Theme.fade, value: showControls)
    }
}

/// A press that dims the cover a little without shrinking it (it's too big to bounce).
private struct CoverPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}
