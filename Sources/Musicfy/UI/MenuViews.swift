import SwiftUI

/// Las piezas dibujadas del menú de los tres puntos (van dentro de NSMenuItem.view).
/// El menú es siempre oscuro, como el player.

// MARK: - Tarjetas de modo

struct ModeCardsView: View {
    let current: DisplayMode
    let accent: Color
    let choose: (DisplayMode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(DisplayMode.allCases.enumerated()), id: \.offset) { index, mode in
                ModeCard(mode: mode, shortcut: "⌘\(index + 1)", selected: mode == current, accent: accent) {
                    choose(mode)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(width: 320)
        .environment(\.colorScheme, .dark)
    }
}

private struct ModeCard: View {
    let mode: DisplayMode
    let shortcut: String
    let selected: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ModeGlyph(mode: mode, art: selected ? accent : Color.white.opacity(0.42))
                    .frame(width: 56, height: 38)
                Text(mode.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(selected ? 1 : 0.85))
                Text(shortcut)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.16 : hovering ? 0.08 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.32 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(Theme.fade, value: hovering)
    }
}

/// Dibujito de cada modo. `art` es el color de la tapita.
private struct ModeGlyph: View {
    let mode: DisplayMode
    let art: Color

    private let line = Color.white.opacity(0.55)
    private let frame = Color.white.opacity(0.14)

    var body: some View {
        switch mode {
        case .artwork:
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(art)
                VStack(alignment: .leading, spacing: 2.5) {
                    Capsule().fill(Color.white.opacity(0.9)).frame(width: 18, height: 2.5)
                    Capsule().fill(Color.white.opacity(0.6)).frame(width: 26, height: 2)
                }
                .padding(5)
            }
            .frame(width: 36, height: 36)
        case .compact:
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(art).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(line).frame(width: 22, height: 2.5)
                    Capsule().fill(line.opacity(0.6)).frame(width: 16, height: 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .frame(width: 54, height: 22)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(frame))
        case .island:
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                HStack(spacing: 3) {
                    Circle().fill(art).frame(width: 5, height: 5)
                    Capsule().fill(Color.white.opacity(0.7)).frame(width: 12, height: 2)
                }
                .padding(.horizontal, 4)
                .frame(height: 9)
                .background(Capsule().fill(Color.black.opacity(0.9)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                .padding(.top, 3)
            }
            .frame(width: 54, height: 34)
        }
    }
}

// MARK: - Botones a la vista

struct VisibleButtonsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Botones a la vista")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            HStack(spacing: 0) {
                toggle("quote.bubble", "Letras", $settings.showLyricsButton)
                toggle("list.bullet", "A continuación", $settings.showQueueButton)
                toggle("speaker.wave.2", "Volumen", $settings.showVolume)
                toggle("airplayaudio", "Salida", $settings.showOutput)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: 320, alignment: .leading)
        .environment(\.colorScheme, .dark)
    }

    private func toggle(_ symbol: String, _ label: String, _ isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? Color.black.opacity(0.85) : Color.white.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isOn.wrappedValue ? Color.white : Color.white.opacity(0.1)))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .animation(Theme.fade, value: isOn.wrappedValue)
        }
        .buttonStyle(PressableStyle())
        .help(label)
    }
}
