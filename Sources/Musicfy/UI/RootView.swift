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

    private var baseHeight: CGFloat {
        panel.mode == .artwork ? Theme.artworkSize.height : Theme.compactSize.height
    }

    private var framed: some View {
        ZStack {
            VisualEffectBackground(cornerRadius: radius)
            VStack(spacing: 0) {
                content
                    .frame(height: baseHeight)
                if panel.drawer != .none {
                    drawer
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
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
        .animation(Theme.smooth, value: panel.drawer)
        .animation(Theme.smooth, value: player.state == nil)
        .animation(Theme.smooth, value: player.problem)
    }

    @ViewBuilder
    private var content: some View {
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
    }

    /// Letras o cola, debajo del player.
    private var drawer: some View {
        ZStack {
            Color.black.opacity(0.1)
            WindowDragArea(onDoubleClick: { panel.drawer = .none })
            switch panel.drawer {
            case .lyrics: LyricsPanel(player: player).transition(.opacity)
            case .queue: QueuePanel(player: player).transition(.opacity)
            case .none: EmptyView()
            }
        }
        .frame(height: Theme.drawerHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
        .animation(Theme.fade, value: panel.drawer)
    }
}
