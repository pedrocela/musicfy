import AppKit
import SwiftUI

/// While the player is dragged toward the top center, an outline of the Island shows where
/// it will land. It brightens as the player gets close and lights up once a release would
/// turn it into the Island.
@MainActor
final class IslandGhost {
    private final class Model: ObservableObject {
        @Published var armed = false
    }

    private let model = Model()
    private lazy var window: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Theme.islandCollapsed),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Just above the player, so the outline shows over it as it reaches the top.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.alphaValue = 0
        let host = NSHostingView(rootView: GhostView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }()

    /// `closeness` from 0 (far) to 1 (on it); `armed` when letting go would make the Island.
    func show(at frame: NSRect, closeness: CGFloat, armed: Bool) {
        if window.frame != frame { window.setFrame(frame, display: false) }
        if !window.isVisible { window.orderFrontRegardless() }
        let alpha = armed ? 1 : 0.5 * closeness
        if abs(window.alphaValue - alpha) > 0.01 { window.alphaValue = alpha }
        if model.armed != armed {
            withAnimation(Theme.smooth) { model.armed = armed }
        }
    }

    func hide() {
        guard window.isVisible else { return }
        model.armed = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.window.orderOut(nil) }
        })
    }

    private struct GhostView: View {
        @ObservedObject var model: Model

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            shape
                .fill(Color.black.opacity(model.armed ? 0.45 : 0.28))
                .overlay(
                    shape.strokeBorder(
                        Color.white.opacity(model.armed ? 0.7 : 0.35),
                        style: StrokeStyle(lineWidth: model.armed ? 1.5 : 1, dash: model.armed ? [] : [4, 4])
                    )
                )
                .scaleEffect(model.armed ? 1 : 0.92)
                .environment(\.colorScheme, .dark)
        }
    }
}
