import SwiftUI

/// The drawn part of the "…" menu: the mode selector at the top (inside an NSMenuItem.view).
/// 254 × 64 container, three 81 × 58 segments. Monochrome; the chosen one is lifted.
struct ModeSelectorView: View {
    let current: DisplayMode
    let choose: (DisplayMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(DisplayMode.allCases.enumerated()), id: \.offset) { index, mode in
                ModeSegment(mode: mode, shortcut: index + 1, selected: mode == current) { choose(mode) }
            }
        }
        .padding(3)
        .frame(width: 254, height: 64)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(MenuInk.well))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
    }
}

private struct ModeSegment: View {
    let mode: DisplayMode
    let shortcut: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ModePictogram(mode: mode)
                    .frame(width: 36, height: 24)
                Text(mode.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.bottom, 2)
            .foregroundStyle(Theme.ink)
            .opacity(selected || hovering ? 1 : 0.55)
            .frame(width: 81, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(selected ? MenuInk.lifted : Theme.ink.opacity(hovering ? 0.06 : 0))
                    .shadow(color: selected ? MenuInk.liftShadow : .clear, radius: 1, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help("\(mode.label) (⌘\(shortcut))")
        .onHover { hovering = $0 }
        .animation(Theme.fade, value: hovering)
    }
}

/// A tiny screen with its menu bar and the player where it sits in that mode:
/// a square at the top right (Artwork), a bar (Compact), a pill under the menu bar (Island).
private struct ModePictogram: View {
    let mode: DisplayMode
    private let player = Theme.ink

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(Theme.ink.opacity(0.08))
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(Theme.ink.opacity(0.35), lineWidth: 1)
            Rectangle()
                .fill(Theme.ink.opacity(0.28))
                .frame(height: 3)
                .padding(.horizontal, 1)
                .padding(.top, 1)
            playerShape
        }
        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
    }

    @ViewBuilder
    private var playerShape: some View {
        switch mode {
        case .artwork:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(player)
                .frame(width: 10, height: 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 6)
                .padding(.trailing, 3)
        case .compact:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(player)
                .frame(width: 15, height: 5)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 6)
                .padding(.trailing, 3)
        case .island:
            Capsule()
                .fill(player)
                .frame(width: 13, height: 4)
                .padding(.top, 5)
        }
    }
}

/// Playback in the "…" menu when the player is too small to show it: one card, shaped like
/// the mode selector (254 wide), with shuffle, previous, play/pause, next and repeat.
/// The menu stays open, so shuffle and repeat show their new state right away.
struct MenuTransportView: View {
    @ObservedObject var player: PlayerController

    var body: some View {
        let state = player.state
        let playing = state?.isPlaying ?? false
        let repeatMode = state?.repeatMode ?? .off
        let kind = state?.source ?? .music
        HStack(spacing: 2) {
            MenuTransportButton(symbol: "shuffle", size: 13, active: state?.shuffle == true, help: "Shuffle") {
                player.toggleShuffle()
            }
            .opacity(kind.hasPlayModes ? 1 : 0)
            .allowsHitTesting(kind.hasPlayModes)
            MenuTransportButton(symbol: kind.previousSymbol, size: 15, help: kind.previousHelp) { player.previous() }
            MenuTransportButton(symbol: playing ? "pause.fill" : "play.fill", size: 19, help: "Play/Pause") {
                player.playPause()
            }
            MenuTransportButton(symbol: kind.nextSymbol, size: 15, help: kind.nextHelp) { player.next() }
            MenuTransportButton(
                symbol: repeatMode == .one ? "repeat.1" : "repeat",
                size: 13,
                active: repeatMode != .off,
                help: "Repeat"
            ) { player.cycleRepeat() }
            .opacity(kind.hasPlayModes ? 1 : 0)
            .allowsHitTesting(kind.hasPlayModes)
        }
        .padding(3)
        .frame(width: 254, height: 40)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(MenuInk.well))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
    }
}

private struct MenuTransportButton: View {
    let symbol: String
    let size: CGFloat
    var active: Bool? = nil
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Theme.ink)
                .opacity(active == false && !hovering ? 0.55 : 1)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(active == true ? MenuInk.lifted : Theme.ink.opacity(hovering ? 0.06 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.fade, value: hovering)
        .animation(Theme.fade, value: active)
    }
}

/// The menu's drawn parts follow the menu's appearance (the system's): a well a shade off
/// the menu, and the chosen segment lifted out of it (lighter in dark mode, white in light).
private enum MenuInk {
    static let well = Theme.adaptive(dark: NSColor(white: 1, alpha: 0.05), light: NSColor(white: 0, alpha: 0.05))
    static let lifted = Theme.adaptive(dark: NSColor(white: 1, alpha: 0.15), light: NSColor(white: 1, alpha: 1))
    static let liftShadow = Theme.adaptive(dark: NSColor(white: 0, alpha: 0.35), light: NSColor(white: 0, alpha: 0.18))
}
