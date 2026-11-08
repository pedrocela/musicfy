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
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.05)))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .environment(\.colorScheme, .dark)
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
            .foregroundStyle(Color.white)
            .opacity(selected || hovering ? 1 : 0.55)
            .frame(width: 81, height: 58)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.15 : hovering ? 0.06 : 0))
                    .shadow(color: .black.opacity(selected ? 0.35 : 0), radius: 1, y: 1)
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
    private let player = Color.white

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(Color.white.opacity(0.08))
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            Rectangle()
                .fill(Color.white.opacity(0.28))
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
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.05)))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .environment(\.colorScheme, .dark)
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
                .foregroundStyle(Color.white)
                .opacity(active == false && !hovering ? 0.55 : 1)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(active == true ? 0.15 : hovering ? 0.06 : 0))
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
