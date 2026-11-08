import SwiftUI

/// Modo compacto (320 × 144): miniatura, título y controles sobre un fondo
/// teñido con el color de la tapa.
struct CompactModeView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var settings: Settings
    @ObservedObject var panel: PanelModel

    var body: some View {
        ZStack {
            Color(nsColor: player.palette.background)
                .animation(Theme.crossfade, value: player.palette)
            LinearGradient(colors: [Color.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
            WindowDragArea(onDoubleClick: panel.actions.toggleArtworkCompact)

            VStack(spacing: 0) {
                header
                ZStack {
                    if panel.volumeOpen {
                        VolumeBar(player: player).transition(.opacity)
                    } else {
                        TimeBar(player: player).transition(.opacity)
                    }
                }
                .padding(.top, 12)
                .animation(Theme.fade, value: panel.volumeOpen)
                TransportRow(player: player, size: .medium)
                    .padding(.top, 2)
            }
            // 16 arriba hasta la tapita; abajo, 10 más el aire propio de los
            // botones: a la vista, el mismo margen arriba y abajo.
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                CrossfadingArtwork(player: player)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .allowsHitTesting(false)

            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(text: player.state?.title ?? "", font: Theme.compactTitle, color: Theme.primary, height: 18)
                    SubtitleLine(player: player, font: Theme.compactSubtitle, height: 16)
                }
                .id(player.state?.trackKey ?? "")
                .transition(.opacity)
            }
            .animation(Theme.crossfade, value: player.state?.trackKey)

            ZStack(alignment: .trailing) {
                if panel.isHovering {
                    HStack(spacing: 0) {
                        ToolbarIcons(
                            player: player,
                            settings: settings,
                            panel: panel,
                            iconSize: 13,
                            cell: 24,
                            tint: Color.white.opacity(0.85),
                            includesOutput: false
                        )
                        Button(action: panel.actions.showMenu) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .help("Más opciones")
                    }
                    .transition(.opacity.combined(with: .offset(x: 6)))
                } else if let kind = player.state?.source {
                    SourceChip(kind: kind, style: .plain)
                        .transition(.opacity)
                }
            }
            .animation(Theme.fade, value: panel.isHovering)
        }
        .frame(height: 44)
    }
}
