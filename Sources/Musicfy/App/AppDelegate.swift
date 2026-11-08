import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) var shared: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon
        app.run()
    }

    let settings = Settings()
    lazy var player = PlayerController(settings: settings)
    let panelModel = PanelModel()

    private var panel: PlayerPanel!
    private var statusItem: NSStatusItem!
    private var cancellables: Set<AnyCancellable> = []
    private var mouseTimer: Timer?
    private var hoverExitWork: DispatchWorkItem?
    private var idleWork: DispatchWorkItem?
    private var islandCollapseWork: DispatchWorkItem?
    private var islandHoverSince: Date?
    /// Artwork switched to compact because nothing is playing (not because the user chose it).
    private var idleCompact = false
    /// Hid itself; comes back when something plays.
    private var autoHidden = false
    /// Out of the way of a full-screen video or app; back when it leaves full screen.
    private var hiddenForFullScreen = false
    private var menuOpen = false
    private var applyingFrame = false
    /// The user picked a mode while paused: don't auto-shrink again until something plays.
    private var userOverrodeIdle = false
    // Morph to or from the Island.
    private var transitionGeneration = 0
    private var morphTarget: DisplayMode?
    // Dragging the window (dropping it at the top center turns it into the Island).
    private var draggingWindow = false
    private var dragStartAnchor: NSPoint?
    private let islandGhost = IslandGhost()
    // Resizing from the edges.
    private var resizeStartFrame = NSRect.zero
    private var resizeStartSide: CGFloat = 0
    private var resizeSwitchedMode = false
    /// The still window during a live artwork resize, and the player's rect on screen inside it.
    private var resizeCanvas: NSRect?
    private var canvasEdges: ResizeEdges = []
    private var liveFrame = NSRect.zero
    private var hideHotKey: HotKey?
    private var grip: ResizeGripView!

    var isPanelVisible: Bool { panel?.isVisible ?? false }
    private var transitioning: Bool { panelModel.morph != nil }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelModel.actions = PanelActions(
            setMode: { [weak self] mode in self?.userSwitch(to: mode) },
            toggleArtworkCompact: { [weak self] in
                guard let self else { return }
                self.userSwitch(to: self.panelModel.mode == .artwork ? .compact : .artwork)
            },
            hide: { [weak self] in self?.hidePanel() },
            showMenu: { [weak self] in self?.showMainMenu() },
            showOutputMenu: { [weak self] in self?.showOutputMenu() }
        )

        panel = PlayerPanel()
        panel.delegate = self
        let root = RootView(player: player, settings: settings, panel: panelModel)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        // On top of the UI, an invisible layer that only takes the edges, for resizing.
        BackgroundCursor.enable()
        grip = ResizeGripView()
        grip.allowedEdges = { [weak self] in self?.resizableEdges ?? [] }
        grip.onBegin = { [weak self] in self?.beginResize() }
        grip.onResize = { [weak self] edges, dx, dy in self?.resize(edges: edges, dx: dx, dy: dy) ?? false }
        grip.onEnd = { [weak self] in self?.endResize() }
        let container = NSView(frame: NSRect(origin: .zero, size: Theme.artworkSize))
        for view in [hosting, grip!] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        panel.contentView = container

        setUpStatusItem()
        observe()
        // ⌥⌘M from any app: show or hide the player.
        hideHotKey = HotKey(keyCode: kVK_ANSI_M, modifiers: cmdKey | optionKey, id: 1) { [weak self] in
            self?.togglePanel()
        }

        panelModel.mode = settings.mode
        placePanel(for: settings.mode)
        showPanel()

        player.start()
        startMousePolling()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.transitioning else { return }
                self.placePanel(for: self.panelModel.mode)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    // MARK: - Observers

    private func observe() {
        watchFullScreen()
        // Over full-screen apps and videos, only if asked.
        settings.$showOverFullScreen
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                self?.panel.showsOverFullScreen = show
                self?.checkFullScreen()
            }
            .store(in: &cancellables)

        // The mode chosen in Settings.
        settings.$mode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.idleCompact = false
                self.updateMode(animated: true)
                self.evaluateIdle()
            }
            .store(in: &cancellables)

        settings.$idleBehavior
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.idleCompact = false
                self.updateMode(animated: true)
                self.evaluateIdle()
            }
            .store(in: &cancellables)

        // Lyrics or queue panel: the window grows downward.
        panelModel.$drawer
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] drawer in
                guard let self else { return }
                self.player.lyricsVisible = drawer == .lyrics
                self.player.queueVisible = drawer == .queue
                if self.panelModel.mode != .island, !self.transitioning {
                    self.animateFrame(to: self.framedRect(for: self.panelModel.mode))
                }
                // With a panel open the artwork doesn't shrink; once it closes, it does (if still paused).
                self.evaluateIdle()
            }
            .store(in: &cancellables)

        // Play / pause: decide whether to shrink, hide or come back.
        player.$state
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateIdle() }
            .store(in: &cancellables)
    }

    // MARK: - Nothing playing

    private var isPlaying: Bool { player.state?.isPlaying ?? false }

    private func evaluateIdle() {
        idleWork?.cancel()
        idleWork = nil

        if isPlaying {
            userOverrodeIdle = false
            if idleCompact {
                idleCompact = false
                updateMode(animated: true)
            }
            if autoHidden {
                autoHidden = false
                showPanel()
            }
            return
        }

        let delay: TimeInterval
        switch settings.idleBehavior {
        case .stay:
            return
        case .compact:
            guard settings.mode == .artwork, !idleCompact, !userOverrodeIdle, panelModel.drawer == .none else { return }
            delay = 1.5
        case .hide:
            guard isPanelVisible else { return }
            delay = 30
        }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.idleTimerFired() }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func idleTimerFired() {
        guard !isPlaying else { return }
        // Never change the window under the mouse: wait for it to leave.
        if panelModel.isHovering || panelModel.islandExpanded || menuOpen || transitioning {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in self?.idleTimerFired() }
            }
            idleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
            return
        }
        switch settings.idleBehavior {
        case .stay:
            break
        case .compact:
            if settings.mode == .artwork, panelModel.mode == .artwork, panelModel.drawer == .none, !userOverrodeIdle {
                idleCompact = true
                updateMode(animated: true)
            }
        case .hide:
            autoHidden = true
            hidePanel(manual: false)
        }
    }

    // MARK: - Mode and size

    private var targetMode: DisplayMode {
        idleCompact && settings.mode == .artwork ? .compact : settings.mode
    }

    /// A mode change asked for by the user (menu, double click, a gesture).
    func userSwitch(to mode: DisplayMode) {
        if !isPlaying { userOverrodeIdle = true }
        idleCompact = false
        if settings.mode != mode { settings.mode = mode } // the observer runs again later; it's a no-op by then
        updateMode(animated: true)
    }

    private func updateMode(animated: Bool) {
        let from = panelModel.mode
        let to = targetMode
        guard from != to, morphTarget != to else { return }
        panelModel.volumeOpen = false
        if to == .island {
            panelModel.drawer = .none
        } else if from == .island {
            player.lyricsVisible = false
        }

        if !animated || !panel.isVisible {
            transitionGeneration += 1
            morphTarget = nil
            panelModel.morph = nil
            panelModel.islandExpanded = false
            panelModel.mode = to
            placePanel(for: to)
            return
        }
        if from == .island || to == .island {
            morph(from: from, to: to)
            return
        }

        panelModel.islandExpanded = false
        panelModel.mode = to
        animateFrame(to: framedRect(for: to))
    }

    private func animateFrame(
        to frame: NSRect,
        duration: TimeInterval = Theme.resizeDuration,
        completion: (() -> Void)? = nil
    ) {
        guard panel.isVisible else {
            applyingFrame = true
            panel.setFrame(frame, display: true)
            applyingFrame = false
            completion?()
            return
        }
        applyingFrame = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyingFrame = false
                self.panel.invalidateShadow()
                completion?()
            }
        })
    }

    /// To or from the Island, the window turns into the other shape in one motion: the frame
    /// travels between the panel and the pill while the artwork shrinks into (or grows out of)
    /// the pill's thumbnail. Both ends look exactly like the real views, so the handoff is invisible.
    private func morph(from: DisplayMode, to: DisplayMode) {
        transitionGeneration += 1
        let generation = transitionGeneration
        morphTarget = to
        hoverExitWork?.cancel()
        hoverExitWork = nil
        islandCollapseWork?.cancel()
        islandCollapseWork = nil
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1

        let still = Transaction(animation: nil)

        if to == .island {
            let look: MorphLook = from == .compact ? .compact : .artwork
            // A quick crossfade from the live view to its morph twin (same look, without the text).
            withAnimation(.easeOut(duration: 0.12)) {
                panelModel.isHovering = false
                panelModel.islandHint = false
                panelModel.morph = Morph(look: look, progress: 0)
            }
            let pill = islandPillRect(inWindow: islandWindowRect(), expanded: false)
            DispatchQueue.main.async { [weak self] in
                Task { @MainActor in
                    guard let self, self.transitionGeneration == generation else { return }
                    withAnimation(Theme.morph) { self.panelModel.morph?.progress = 1 }
                    self.animateFrame(to: pill, duration: Theme.morphDuration) { [weak self] in
                        guard let self, self.transitionGeneration == generation else { return }
                        withTransaction(still) {
                            self.panelModel.islandExpanded = false
                            self.panelModel.mode = .island
                            self.panelModel.morph = nil
                        }
                        self.morphTarget = nil
                        self.placePanel(for: .island)
                    }
                }
            }
        } else {
            let look: MorphLook = to == .compact ? .compact : .artwork
            let pill = islandPillRect(inWindow: panel.frame, expanded: false)
            withTransaction(still) {
                panelModel.islandExpanded = false
                panelModel.isHovering = false
                panelModel.morph = Morph(look: look, progress: 1)
                panelModel.mode = to
            }
            applyingFrame = true
            panel.setFrame(pill, display: true)
            applyingFrame = false
            DispatchQueue.main.async { [weak self] in
                Task { @MainActor in
                    guard let self, self.transitionGeneration == generation else { return }
                    withAnimation(Theme.morph) { self.panelModel.morph?.progress = 0 }
                    self.animateFrame(to: self.framedRect(for: to), duration: Theme.morphDuration) { [weak self] in
                        guard let self, self.transitionGeneration == generation else { return }
                        self.morphTarget = nil
                        // The text and controls fade in over the finished shape.
                        withAnimation(.easeOut(duration: 0.2)) { self.panelModel.morph = nil }
                        self.panel.hasShadow = true
                        self.panel.invalidateShadow()
                    }
                }
            }
        }
    }

    /// Places the window for the mode, without animation.
    private func placePanel(for mode: DisplayMode) {
        applyingFrame = true
        if mode == .island {
            panel.hasShadow = false
            panel.setFrame(islandWindowRect(), display: true)
        } else {
            panel.hasShadow = true
            panel.ignoresMouseEvents = false
            panel.setFrame(framedRect(for: mode), display: true)
        }
        panel.invalidateShadow()
        applyingFrame = false
    }

    private func size(for mode: DisplayMode) -> CGSize {
        switch mode {
        case .artwork, .compact:
            let base = mode == .artwork
                ? CGSize(width: panelModel.artworkSide, height: panelModel.artworkSide)
                : Theme.compactSize
            let extra = panelModel.drawer == .none ? 0 : Theme.drawerHeight
            return CGSize(width: base.width, height: base.height + extra)
        case .island:
            return islandWindowSize
        }
    }

    // Artwork and compact remember their top-left corner.
    private var anchor: NSPoint {
        get {
            if let saved = UserDefaults.standard.string(forKey: "panelTopLeft") {
                return NSPointFromString(saved)
            }
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
            return NSPoint(x: visible.maxX - Theme.artworkSize.width - 20, y: visible.maxY - 20)
        }
        set {
            UserDefaults.standard.set(NSStringFromPoint(newValue), forKey: "panelTopLeft")
        }
    }

    private func framedRect(for mode: DisplayMode) -> NSRect {
        let size = size(for: mode)
        let frame = NSRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
        // Keep it on screen (a display was unplugged, it grew near an edge).
        return keptOnScreen(frame)
    }

    /// The area of the screen a frame is on (or the one under the mouse while dragging)
    /// below the menu bar, less a small margin. The player never leaves it.
    private func usableArea(for frame: NSRect, near point: NSPoint? = nil) -> NSRect {
        let screens = NSScreen.screens
        let byPoint = point.flatMap { p in screens.first { NSMouseInRect(p, $0.frame, false) } }
        let byOverlap = screens.max { a, b in
            let x = a.visibleFrame.intersection(frame), y = b.visibleFrame.intersection(frame)
            return x.width * x.height < y.width * y.height
        }
        let screen = byPoint ?? byOverlap ?? NSScreen.main ?? screens[0]
        // The whole screen except the menu bar: the player floats above the Dock, so the
        // Dock's reserved strip (or the sliver an auto-hidden Dock keeps) doesn't stop it.
        var area = screen.frame
        area.size.height = screen.visibleFrame.maxY - area.minY
        return area.insetBy(dx: Theme.screenMargin, dy: Theme.screenMargin)
    }

    /// The same frame, slid back inside the screen's usable area.
    func keptOnScreen(_ frame: NSRect, near point: NSPoint? = nil) -> NSRect {
        let area = usableArea(for: frame, near: point)
        var frame = frame
        frame.origin.x = min(max(frame.minX, area.minX), area.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, area.minY), area.maxY - frame.height)
        return frame
    }

    // Island: top center of the screen with the menu bar.
    private var islandWindowSize: CGSize {
        CGSize(
            width: Theme.islandExpanded.width + Theme.islandShadowMargin * 2,
            height: Theme.islandExpanded.height + Theme.islandShadowMargin * 1.5
        )
    }

    private func islandWindowRect() -> NSRect {
        let screen = NSScreen.screens.first ?? NSScreen.main!
        let visible = screen.visibleFrame
        let size = islandWindowSize
        let margin = Theme.islandShadowMargin
        let x: CGFloat
        switch panelModel.islandAlignment {
        case .leading: x = visible.minX + Theme.islandSideGap - margin
        case .center: x = visible.midX - size.width / 2
        case .trailing: x = visible.maxX - Theme.islandSideGap + margin - size.width
        }
        return NSRect(x: x, y: visible.maxY - Theme.islandTopGap - size.height, width: size.width, height: size.height)
    }

    /// Distance from the window's left edge to the pill's.
    private func islandPillOffset(width: CGFloat, alignment: IslandAlignment) -> CGFloat {
        let margin = Theme.islandShadowMargin
        switch alignment {
        case .leading: return margin
        case .center: return (islandWindowSize.width - width) / 2
        case .trailing: return islandWindowSize.width - margin - width
        }
    }

    /// Where the pill sits inside an Island window frame, in screen coordinates.
    private func islandPillRect(inWindow frame: NSRect, expanded: Bool) -> NSRect {
        let size = expanded ? Theme.islandExpanded : Theme.islandCollapsed
        let x = frame.minX + islandPillOffset(width: size.width, alignment: panelModel.islandAlignment)
        return NSRect(x: x, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    private func islandPillRect() -> NSRect {
        islandPillRect(inWindow: panel.frame, expanded: panelModel.islandExpanded)
    }

    /// After dragging the Island sideways: it snaps to the left, center or right.
    func snapIsland() {
        guard panelModel.mode == .island else { return }
        let pill = islandPillRect()
        let visible = (NSScreen.screens.first ?? NSScreen.main!).visibleFrame
        let third = visible.width / 3
        let target: IslandAlignment
        switch pill.midX {
        case ..<(visible.minX + third): target = .leading
        case (visible.maxX - third)...: target = .trailing
        default: target = .center
        }
        // Change the alignment without the pill jumping, then carry it to its place.
        if target != panelModel.islandAlignment {
            panelModel.islandAlignment = target
            var frame = panel.frame
            frame.origin.x = pill.minX - islandPillOffset(width: pill.width, alignment: target)
            panel.setFrame(frame, display: true)
        }
        animateFrame(to: islandWindowRect())
    }

    func windowDidMove(_ notification: Notification) {
        guard !applyingFrame, !transitioning, panelModel.mode != .island else { return }
        anchor = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    // MARK: - Resizing from the edges

    /// Artwork: every edge. Compact: every edge too, to stretch it into the artwork.
    /// With lyrics or Up Next open below, the bottom edge belongs to that panel. Island: none.
    private var resizableEdges: ResizeEdges {
        guard !transitioning else { return [] }
        let open = panelModel.drawer != .none
        switch panelModel.mode {
        case .artwork: return open ? [.left, .right, .top] : .all
        case .compact: return open ? [.left, .right, .top] : .all
        case .island: return []
        }
    }

    private func beginResize() {
        resizeStartFrame = panel.frame
        resizeStartSide = panelModel.artworkSide
        resizeSwitchedMode = false
    }

    /// Returns `false` when the gesture ends in another mode.
    private func resize(edges: ResizeEdges, dx: CGFloat, dy: CGFloat) -> Bool {
        resizeLog.notice("step mode=\(self.panelModel.mode.rawValue, privacy: .public) edges=\(edges.rawValue, privacy: .public) dx=\(Int(dx), privacy: .public) dy=\(Int(dy), privacy: .public) mouse=\(NSStringFromPoint(NSEvent.mouseLocation), privacy: .public) window=\(NSStringFromRect(self.panel.frame), privacy: .public) live=\(NSStringFromRect(self.liveFrame), privacy: .public)")
        let range = Theme.artworkSideRange
        switch panelModel.mode {
        case .artwork:
            let extra = panelModel.drawer == .none ? 0 : Theme.drawerHeight
            // Only the top or bottom edge, pushed inward, squashes it into compact: it follows
            // the mouse 1:1 while compact fades in over it.
            // With a panel open below, only the top edge does it, and the panel stays.
            if edges == .top || edges == .bottom {
                let squash = edges == .bottom ? dy : -dy
                if squash > 0 {
                    let compact = Theme.compactSize
                    let progress = min(1, squash / max(1, resizeStartSide - compact.height))
                    let width = resizeStartSide + (compact.width - resizeStartSide) * progress
                    let height = resizeStartSide + (compact.height - resizeStartSide) * progress + extra
                    let top = edges == .top ? resizeStartFrame.minY + height : resizeStartFrame.maxY
                    panelModel.squash = progress
                    applyLiveResize(NSRect(x: resizeStartFrame.minX, y: top - height, width: width, height: height))
                    return true
                }
                if panelModel.squash > 0 { panelModel.squash = 0 }
            }

            var horizontal: CGFloat = 0, vertical: CGFloat = 0
            if edges.contains(.right) { horizontal = dx } else if edges.contains(.left) { horizontal = -dx }
            if edges.contains(.bottom) { vertical = -dy } else if edges.contains(.top) { vertical = dy }
            // From a corner, the size follows the mouse projected onto the corner's diagonal,
            // so the corner slides smoothly under the pointer instead of jumping between axes.
            let growth: CGFloat
            if edges.contains(.left) || edges.contains(.right), edges.contains(.top) || edges.contains(.bottom) {
                growth = (horizontal + vertical) / 2
            } else {
                growth = horizontal + vertical
            }
            let proposed = resizeStartSide + growth
            // Past the minimum or maximum it resists, like rubber.
            var side: CGFloat
            if proposed < range.lowerBound {
                side = range.lowerBound - (range.lowerBound - proposed) * 0.25
            } else if proposed > range.upperBound {
                side = range.upperBound + (proposed - range.upperBound) * 0.25
            } else {
                side = proposed
            }
            // The screen's edges are a hard stop: it grows only as far as there is room.
            let area = usableArea(for: resizeStartFrame)
            let roomWide = edges.contains(.left) ? resizeStartFrame.maxX - area.minX : area.maxX - resizeStartFrame.minX
            let roomHigh = edges.contains(.top) ? area.maxY - resizeStartFrame.minY : resizeStartFrame.maxY - area.minY
            side = min(side, range.upperBound + 40, max(range.lowerBound, min(roomWide, roomHigh - extra)))
            // The corner opposite the one being pulled stays exactly where it was.
            let height = side + extra
            let left = edges.contains(.left) ? resizeStartFrame.maxX - side : resizeStartFrame.minX
            let bottom = edges.contains(.top) ? resizeStartFrame.minY : resizeStartFrame.maxY - height
            let frame = NSRect(x: left, y: bottom, width: side, height: height)
            if edges.contains(.left) || edges.contains(.right) {
                // Corners and sides: the window holds still and the player is drawn inside it.
                if resizeCanvas == nil {
                    openCanvas(edges: edges, room: CGSize(width: roomWide, height: roomHigh))
                }
                showLive(frame, side: side)
            } else {
                applyLiveResize(frame, side: side)
            }
            return true

        case .compact:
            // Compact follows the mouse 1:1 toward the artwork size; the artwork fades in as it grows.
            var growth: CGFloat = 0
            if edges.contains(.bottom) { growth = max(growth, -dy) }
            if edges.contains(.top) { growth = max(growth, dy) }
            if edges.contains(.right) { growth = max(growth, dx) }
            if edges.contains(.left) { growth = max(growth, -dx) }
            let side = panelModel.artworkSide
            let base = Theme.compactSize
            let extra = panelModel.drawer == .none ? 0 : Theme.drawerHeight
            let progress = min(1, max(0, growth / max(1, side - base.height)))
            let width = base.width + (side - base.width) * progress
            let height = base.height + (side - base.height) * progress + extra
            let left = edges.contains(.left) ? resizeStartFrame.maxX - width : resizeStartFrame.minX
            panelModel.grow = progress
            // Pulled from the top it grows upward (the bottom stays); otherwise downward.
            let bottom = edges.contains(.top) ? resizeStartFrame.minY : resizeStartFrame.maxY - height
            let frame = NSRect(x: left, y: bottom, width: width, height: height)
            applyLiveResize(keptOnScreen(frame))
            return true

        case .island:
            return false
        }
    }

    /// Grows the window, once, to hold any size the gesture can reach from the fixed corner,
    /// with the player drawn where it was. From here on only the drawing changes.
    private func openCanvas(edges: ResizeEdges, room: CGSize) {
        let extra = panelModel.drawer == .none ? 0 : Theme.drawerHeight
        let reach = min(Theme.artworkSideRange.upperBound + 40, room.width, room.height - extra)
        let width = max(reach, resizeStartFrame.width)
        let height = max(reach + extra, resizeStartFrame.height)
        let canvas = NSRect(
            x: edges.contains(.left) ? resizeStartFrame.maxX - width : resizeStartFrame.minX,
            y: edges.contains(.top) ? resizeStartFrame.minY : resizeStartFrame.maxY - height,
            width: width,
            height: height
        )
        resizeCanvas = canvas
        canvasEdges = edges
        applyingFrame = true // the window moves, the player doesn't: keep the saved position
        showLive(resizeStartFrame, side: resizeStartSide)
        panel.setFrame(canvas, display: true)
        resizeLog.notice("canvas \(NSStringFromRect(canvas), privacy: .public) from \(NSStringFromRect(self.resizeStartFrame), privacy: .public)")
    }

    /// Draws the player at `frame` (screen points) inside the still canvas window.
    private func showLive(_ frame: NSRect, side: CGFloat, animation: Animation? = nil) {
        guard let canvas = resizeCanvas else { return }
        liveFrame = frame
        let rect = CGRect(
            x: frame.minX - canvas.minX,
            y: canvas.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
        var transaction = Transaction(animation: animation)
        transaction.disablesAnimations = animation == nil
        withTransaction(transaction) {
            panelModel.artworkSide = side
            panelModel.liveRect = rect
        }
        panel.invalidateShadow()
    }

    /// Back to a window the size of the player.
    private func closeCanvas() {
        guard resizeCanvas != nil else { return }
        let frame = liveFrame
        resizeCanvas = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { panelModel.liveRect = nil }
        panel.setFrame(frame, display: true)
        applyingFrame = false
        anchor = NSPoint(x: frame.minX, y: frame.maxY)
        panel.invalidateShadow()
        resizeLog.notice("closed at \(NSStringFromRect(frame), privacy: .public)")
    }

    /// One step of a live resize: the model, the window and the layout change together,
    /// with no animation, so the content never lags a frame behind the window.
    private func applyLiveResize(_ frame: NSRect, side: CGFloat? = nil) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let side { panelModel.artworkSide = side }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(frame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        CATransaction.commit()
    }

    private func endResize() {
        resizeLog.notice("end window=\(NSStringFromRect(self.panel.frame), privacy: .public) mode=\(self.panelModel.mode.rawValue, privacy: .public) grow=\(Double(self.panelModel.grow), privacy: .public) squash=\(Double(self.panelModel.squash), privacy: .public) switched=\(self.resizeSwitchedMode, privacy: .public)")
        guard !resizeSwitchedMode else { return }
        let startAnchor = NSPoint(x: resizeStartFrame.minX, y: resizeStartFrame.maxY)
        switch panelModel.mode {
        case .compact:
            if panelModel.grow >= 0.35 {
                // Past a third of the way: finish the trip into artwork.
                withAnimation(Theme.smooth) { panelModel.grow = 1 }
                userSwitch(to: .artwork)
                resetStretch(after: Theme.resizeDuration)
            } else {
                anchor = startAnchor
                withAnimation(Theme.smooth) { panelModel.grow = 0 }
                animateFrame(to: framedRect(for: .compact))
            }
        case .artwork:
            if panelModel.squash > 0 {
                if panelModel.squash >= 0.35 {
                    withAnimation(Theme.smooth) { panelModel.squash = 1 }
                    userSwitch(to: .compact)
                    resetStretch(after: Theme.resizeDuration)
                } else {
                    anchor = startAnchor
                    withAnimation(Theme.smooth) { panelModel.squash = 0 }
                    animateFrame(to: framedRect(for: .artwork))
                }
                return
            }
            let range = Theme.artworkSideRange
            let clamped = min(max(panelModel.artworkSide, range.lowerBound), range.upperBound)
            if resizeCanvas != nil {
                guard clamped != panelModel.artworkSide else {
                    closeCanvas()
                    return
                }
                // Past the minimum or maximum: the rubber springs back inside the canvas,
                // toward the fixed corner, then the window shrinks to fit.
                let extra = panelModel.drawer == .none ? 0 : Theme.drawerHeight
                let target = NSRect(
                    x: canvasEdges.contains(.left) ? liveFrame.maxX - clamped : liveFrame.minX,
                    y: canvasEdges.contains(.top) ? liveFrame.minY : liveFrame.maxY - clamped - extra,
                    width: clamped,
                    height: clamped + extra
                )
                showLive(target, side: clamped, animation: Theme.smooth)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    Task { @MainActor in self?.closeCanvas() }
                }
                return
            }
            if clamped != panelModel.artworkSide { panelModel.artworkSide = clamped }
            let target = framedRect(for: .artwork)
            if target != panel.frame {
                animateFrame(to: target) // the rubber springs back
            } else {
                panel.invalidateShadow()
            }
        case .island:
            break
        }
    }

    private func resetStretch(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor in
                self?.panelModel.grow = 0
                self?.panelModel.squash = 0
            }
        }
    }

    // MARK: - Dragging between modes

    /// The Island zone: top center of the screen with the menu bar.
    /// Where the closed Island sits when it's centered.
    private var centeredPillRect: NSRect {
        let visible = (NSScreen.screens.first ?? NSScreen.main!).visibleFrame
        let size = Theme.islandCollapsed
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - Theme.islandTopGap - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Called by the drag area when the mouse goes down on the artwork or compact view.
    func windowDragBegan() {
        guard panelModel.mode != .island, !transitioning else { return }
        draggingWindow = true
        dragStartAnchor = anchor
    }

    /// Every step of a window drag (the drag runs its own event loop): where the window
    /// goes. It stays on screen; near the top center an outline of the Island appears,
    /// and once the window's top reaches the top edge there it's armed and pulled toward
    /// the center, so letting go turns it into the Island.
    func windowDragged(to proposed: NSRect, mouse: NSPoint) -> NSPoint {
        var frame = keptOnScreen(proposed, near: mouse)
        guard draggingWindow, let islandScreen = NSScreen.screens.first else { return frame.origin }
        let pill = centeredPillRect
        let top = islandScreen.visibleFrame.maxY - Theme.screenMargin
        let onIslandScreen = NSMouseInRect(mouse, islandScreen.frame, false)
        let offCenter = abs(proposed.midX - pill.midX)
        let belowTop = max(0, top - proposed.maxY)
        let armed = onIslandScreen
            && offCenter < Theme.islandSnapWidth
            && belowTop < Theme.islandSnapDepth
        if armed {
            // A light magnetic pull toward the center.
            let centeredX = pill.midX - frame.width / 2
            frame.origin.x += (centeredX - frame.origin.x) * 0.5
        }
        let distance = (offCenter * offCenter + belowTop * belowTop).squareRoot()
        let closeness = onIslandScreen ? max(0, 1 - distance / 360) : 0
        if closeness > 0 || armed {
            islandGhost.show(at: pill, closeness: closeness, armed: armed)
        } else {
            islandGhost.hide()
        }
        if armed != panelModel.islandHint {
            withAnimation(Theme.smooth) { panelModel.islandHint = armed }
        }
        return frame.origin
    }

    /// On release: if it's at the top center, it becomes the Island.
    func windowDragEnded() {
        guard draggingWindow else { return }
        draggingWindow = false
        islandGhost.hide()
        guard panelModel.islandHint else { return }
        // The panel goes back to where it was before the drag when it leaves the Island.
        if let start = dragStartAnchor { anchor = start }
        panelModel.islandAlignment = .center
        userSwitch(to: .island)
    }

    /// Safety net: a drag whose mouse-up got lost still ends.
    private func trackWindowDrag(mouse: NSPoint) {
        guard draggingWindow, NSEvent.pressedMouseButtons & 1 == 0 else { return }
        windowDragEnded()
    }

    /// The Island is being pulled down: it follows the mouse.
    func islandPulled(by distance: CGFloat) {
        let progress = min(1, max(0, distance / Theme.islandPullThreshold))
        if abs(progress - panelModel.islandPull) > 0.01 {
            panelModel.islandPull = progress
        }
    }

    /// The Island was released after pulling it down. Past the threshold it becomes the artwork
    /// right where it is; otherwise it goes back to its place.
    func islandReleased(pulled distance: CGFloat) {
        withAnimation(Theme.smooth) { panelModel.islandPull = 0 }
        guard distance >= Theme.islandPullThreshold else {
            snapIsland()
            return
        }
        let pill = islandPillRect()
        let side = panelModel.artworkSide
        anchor = NSPoint(x: pill.midX - side / 2, y: pill.maxY)
        userSwitch(to: .artwork)
    }

    // MARK: - Mouse

    /// The mouse position is checked 30 times a second. It's more reliable than AppKit tracking
    /// in a window that's never active, and lets the Island's transparent area pass clicks through.
    private func startMousePolling() {
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollMouse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func pollMouse() {
        guard let panel, panel.isVisible, !menuOpen else { return }
        let mouse = NSEvent.mouseLocation
        trackWindowDrag(mouse: mouse)
        guard !transitioning else { return }

        if panelModel.mode == .island {
            let inside = islandPillRect().insetBy(dx: -2, dy: -2).contains(mouse)
            panel.ignoresMouseEvents = !inside
            if inside {
                islandCollapseWork?.cancel()
                islandCollapseWork = nil
                if !panelModel.islandExpanded {
                    // Opens after a brief rest: brushing past doesn't unfold it.
                    let since = islandHoverSince ?? Date()
                    islandHoverSince = since
                    if Date().timeIntervalSince(since) >= Theme.islandOpenDelay { panelModel.islandExpanded = true }
                }
            } else {
                islandHoverSince = nil
                if panelModel.islandExpanded, islandCollapseWork == nil {
                    let work = DispatchWorkItem { [weak self] in
                        Task { @MainActor in
                            guard let self else { return }
                            self.islandCollapseWork = nil
                            self.panelModel.islandExpanded = false
                            self.panelModel.volumeOpen = false
                        }
                    }
                    islandCollapseWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + Theme.islandCloseDelay, execute: work)
                }
            }
            return
        }

        let inside = panel.frame.contains(mouse)
        if inside { grip.refreshCursor(atScreenPoint: mouse) }
        if inside {
            hoverExitWork?.cancel()
            hoverExitWork = nil
            if !panelModel.isHovering { panelModel.isHovering = true }
        } else if panelModel.isHovering, hoverExitWork == nil {
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.hoverExitWork = nil
                    self.panelModel.isHovering = false
                    self.panelModel.volumeOpen = false
                }
            }
            hoverExitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Theme.hoverExitDelay, execute: work)
        }
    }

    // MARK: - Show and hide

    func showPanel() {
        autoHidden = false
        guard !panel.isVisible else { return }
        if !settings.showOverFullScreen, FullScreen.covers(framedOrIslandRect) {
            hiddenForFullScreen = true // shows when full screen ends
            return
        }
        placePanel(for: panelModel.mode)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        fade(to: 1, duration: 0.25)
        evaluateIdle()
    }

    func hidePanel(manual: Bool = true) {
        if manual {
            autoHidden = false
            hiddenForFullScreen = false
        }
        guard panel.isVisible else { return }
        panelModel.isHovering = false
        panelModel.islandExpanded = false
        panelModel.volumeOpen = false
        fade(to: 0, duration: 0.2) { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    func togglePanel() {
        isPanelVisible || hiddenForFullScreen ? hidePanel() : showPanel()
    }

    /// Where the player would be on screen in its current mode.
    private var framedOrIslandRect: NSRect {
        panelModel.mode == .island ? islandWindowRect() : framedRect(for: panelModel.mode)
    }

    /// Full screen came or went (a Space changed, another app came forward): step aside
    /// for a full-screen window on the player's display, and come back after.
    private func checkFullScreen() {
        let covered = !settings.showOverFullScreen && FullScreen.covers(framedOrIslandRect)
        if covered, panel.isVisible {
            hiddenForFullScreen = true
            panelModel.isHovering = false
            panelModel.islandExpanded = false
            panelModel.volumeOpen = false
            fade(to: 0, duration: 0.15) { [weak self] in
                guard let self, self.hiddenForFullScreen else { return }
                self.panel.orderOut(nil)
            }
        } else if !covered, hiddenForFullScreen {
            hiddenForFullScreen = false
            showPanel()
        }
    }

    private func watchFullScreen() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.checkFullScreen()
                    // Entering full screen animates; look again once it has settled.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        MainActor.assumeIsolated { self?.checkFullScreen() }
                    }
                }
            }
        }
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval, then completion: (() -> Void)? = nil) {
        guard duration > 0 else {
            panel.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        }, completionHandler: {
            Task { @MainActor in completion?() }
        })
    }

    // MARK: - Menus

    func showMainMenu() {
        popUp(Menus.main(app: self))
    }

    private func showOutputMenu() {
        popUp(Menus.output())
    }

    private func popUp(_ menu: NSMenu) {
        menuOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        menuOpen = false
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = Self.menuBarIcon()
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Click (any button): the menu. Show and hide live in the menu and on ⌥⌘M.
    @objc private func statusItemClicked() {
        statusItem.menu = Menus.main(app: self)
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// A little "cover": a rounded square with the note cut out of it. Template image,
    /// so the menu bar tints it for light and dark.
    private static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let cover = NSRect(x: 1.5, y: 1.5, width: rect.width - 3, height: rect.height - 3)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: cover, xRadius: 4, yRadius: 4).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .bold)
            if let note = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let noteSize = note.size
                let origin = NSPoint(x: cover.midX - noteSize.width / 2, y: cover.midY - noteSize.height / 2)
                note.draw(in: NSRect(origin: origin, size: noteSize), from: .zero, operation: .destinationOut, fraction: 1)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Musicfy"
        return image
    }
}
