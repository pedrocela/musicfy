import SwiftUI

/// Elige la vista según el modo y le pone el marco (esquinas, borde, permisos).
struct RootView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    var body: some View {
        Group {
            if panel.mode == .island {
                IslandView(player: player, settings: settings, panel: panel)
            } else {
                framed
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var radius: CGFloat {
        panel.mode == .artwork ? Theme.artworkRadius : Theme.compactRadius
    }

    private var framed: some View {
        ZStack {
            VisualEffectBackground(cornerRadius: radius)
            if player.state == nil {
                ZStack {
                    WindowDragArea(onDoubleClick: panel.actions.toggleArtworkCompact)
                    EmptyStateView(player: player)
                }
                .transition(.opacity)
            } else if panel.mode == .artwork {
                ArtworkModeView(player: player, settings: settings, panel: panel)
                    .transition(.opacity)
            } else {
                CompactModeView(player: player, settings: settings, panel: panel)
                    .transition(.opacity)
            }
            VStack {
                Spacer()
                PermissionBanner(player: player)
                    .padding(.bottom, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.windowStroke, lineWidth: 0.5)
        )
        .animation(Theme.smooth, value: panel.mode)
        .animation(Theme.smooth, value: player.state == nil)
        .animation(Theme.smooth, value: player.problem)
    }
}
