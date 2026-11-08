import SwiftUI

/// The drawn part of the "…" menu: the mode selector at the top (inside an NSMenuItem.view).
/// A well as wide as the menu (inset like its separators), three equal segments 50 high.
/// Quiet: the chosen one is lifted and its player drawn in the accent color.
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
        .frame(minWidth: 244, maxWidth: .infinity)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(MenuInk.well))
        .padding(.horizontal, MenuInk.inset)
        .padding(.top, 4)
        .padding(.bottom, 3)
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
            VStack(spacing: 4) {
                ModePictogram(mode: mode, selected: selected)
                    .frame(width: 30, height: 19)
                Text(mode.label)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Theme.ink.opacity(selected || hovering ? 0.88 : 0.6))
            }
            .padding(.bottom, 1)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? MenuInk.lifted : Theme.ink.opacity(hovering ? 0.05 : 0))
                    .shadow(color: selected ? MenuInk.liftShadow : .clear, radius: 1, y: 0.5)
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
/// Hairline screen; the player in the accent color when chosen, a soft gray otherwise.
private struct ModePictogram: View {
    let mode: DisplayMode
    let selected: Bool
    private var player: Color { selected ? Color.accentColor : Theme.ink.opacity(0.45) }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.ink.opacity(0.05))
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Theme.ink.opacity(selected ? 0.32 : 0.22), lineWidth: 0.75)
            Rectangle()
                .fill(Theme.ink.opacity(0.16))
                .frame(height: 2.5)
                .padding(.horizontal, 0.75)
                .padding(.top, 0.75)
            playerShape
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    @ViewBuilder
    private var playerShape: some View {
        switch mode {
        case .artwork:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(player)
                .frame(width: 8, height: 8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 5)
                .padding(.trailing, 3)
        case .compact:
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(player)
                .frame(width: 12, height: 4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 5)
                .padding(.trailing, 3)
        case .island:
            Capsule()
                .fill(player)
                .frame(width: 11, height: 3.5)
                .padding(.top, 4.5)
        }
    }
}

/// Playback in the "…" menu when the player is too small to show it: one card, shaped like
/// the mode selector (as wide as the menu), with shuffle, previous, play/pause, next and repeat.
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
        .frame(minWidth: 244, maxWidth: .infinity)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(MenuInk.well))
        .padding(.horizontal, MenuInk.inset)
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
    /// Side inset of the cards, matching the menu's separators.
    static let inset: CGFloat = 10
    static let well = Theme.adaptive(dark: NSColor(white: 1, alpha: 0.05), light: NSColor(white: 0, alpha: 0.05))
    static let lifted = Theme.adaptive(dark: NSColor(white: 1, alpha: 0.15), light: NSColor(white: 1, alpha: 1))
    static let liftShadow = Theme.adaptive(dark: NSColor(white: 0, alpha: 0.35), light: NSColor(white: 0, alpha: 0.18))
}
