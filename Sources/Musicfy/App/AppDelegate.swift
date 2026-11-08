import AppKit
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
        app.setActivationPolicy(.accessory) // sin ícono en el Dock
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
    /// La tapa pasó a compacto porque no suena nada (no porque lo eligió el usuario).
    private var idleCompact = false
    /// Se escondió solo; vuelve cuando algo suena.
    private var autoHidden = false
    private var menuOpen = false
    private var applyingFrame = false

    var isPanelVisible: Bool { panel?.isVisible ?? false }

    // MARK: - Arranque

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelModel.actions = PanelActions(
            setMode: { [weak self] mode in self?.settings.mode = mode },
            toggleArtworkCompact: { [weak self] in
                guard let self else { return }
                self.settings.mode = self.panelModel.mode == .artwork ? .compact : .artwork
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
        panel.contentView = hosting

        setUpStatusItem()
        observe()

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
                guard let self else { return }
                self.placePanel(for: self.panelModel.mode)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    // MARK: - Observadores

    private func observe() {
        // El modo elegido en el menú.
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

        // Panel de letras o cola: la ventana crece hacia abajo.
        panelModel.$drawer
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] drawer in
                guard let self else { return }
                self.player.lyricsVisible = drawer == .lyrics
                self.player.queueVisible = drawer == .queue
                if self.panelModel.mode != .island { self.animateFrame(to: self.framedRect(for: self.panelModel.mode)) }
            }
            .store(in: &cancellables)

        // Play / pausa: decide si achicar, esconder o volver.
        player.$state
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateIdle() }
            .store(in: &cancellables)
    }

    // MARK: - Sin música

    private var isPlaying: Bool { player.state?.isPlaying ?? false }

    private func evaluateIdle() {
        idleWork?.cancel()
        idleWork = nil

        if isPlaying {
            var changed = false
            if idleCompact {
                idleCompact = false
                changed = true
            }
            if changed { updateMode(animated: true) }
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
            guard settings.mode == .artwork, !idleCompact else { return }
            delay = 3
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
        // Nunca cambiar la ventana debajo del mouse: se espera a que salga.
        if panelModel.isHovering || panelModel.islandExpanded || menuOpen {
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
            if settings.mode == .artwork {
                idleCompact = true
                updateMode(animated: true)
            }
        case .hide:
            autoHidden = true
            hidePanel(manual: false)
        }
    }

    // MARK: - Modo y tamaño

    private var targetMode: DisplayMode {
        idleCompact && settings.mode == .artwork ? .compact : settings.mode
    }

    private func updateMode(animated: Bool) {
        let from = panelModel.mode
        let to = targetMode
        guard from != to else { return }
        panelModel.volumeOpen = false
        panelModel.islandExpanded = false
        if to == .island {
            panelModel.drawer = .none
        } else if from == .island {
            player.lyricsVisible = false
        }

        if from == .island || to == .island || !animated || !panel.isVisible {
            // De o hacia la Isla cambia el lugar de la ventana: fundido de salida y de entrada.
            fade(to: 0, duration: animated ? 0.16 : 0) { [weak self] in
                guard let self else { return }
                self.panelModel.mode = to
                self.placePanel(for: to)
                if self.panel.isVisible { self.fade(to: 1, duration: animated ? 0.22 : 0) }
            }
            return
        }

        panelModel.mode = to
        animateFrame(to: framedRect(for: to))
    }

    private func animateFrame(to frame: NSRect) {
        guard panel.isVisible else {
            placePanel(for: panelModel.mode)
            return
        }
        applyingFrame = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Theme.resizeDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.applyingFrame = false
                self?.panel.invalidateShadow()
            }
        })
    }

    /// Ubica la ventana para el modo, sin animar.
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
            let base = mode == .artwork ? Theme.artworkSize : Theme.compactSize
            let extra = panelModel.drawer == .none ? 0 : Theme.drawerHeight
            return CGSize(width: base.width, height: base.height + extra)
        case .island:
            return islandWindowSize
        }
    }

    // Tapa y compacto: se recuerda la esquina de arriba a la izquierda.
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
        var frame = NSRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
        // Que no quede fuera de la pantalla (se desenchufó un monitor, se agrandó cerca del borde).
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        frame.origin.x = min(max(frame.minX, visible.minX + 4), visible.maxX - frame.width - 4)
        frame.origin.y = min(max(frame.minY, visible.minY + 4), visible.maxY - frame.height - 4)
        return frame
    }

    // Isla: arriba al centro de la pantalla con la barra de menú.
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
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - Theme.islandTopGap - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Dónde está la cápsula dentro de la ventana de la Isla, en coordenadas de pantalla.
    private func islandPillRect() -> NSRect {
        let frame = panel.frame
        let size = panelModel.islandExpanded ? Theme.islandExpanded : Theme.islandCollapsed
        return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    func windowDidMove(_ notification: Notification) {
        guard !applyingFrame, panelModel.mode != .island else { return }
        anchor = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    // MARK: - Mouse

    /// Se mira dónde está el mouse 30 veces por segundo. Es más confiable que el
    /// seguimiento de AppKit en una ventana que nunca está activa, y deja que la
    /// parte transparente de la Isla no bloquee clics.
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

        if panelModel.mode == .island {
            let inside = islandPillRect().insetBy(dx: -2, dy: -2).contains(mouse)
            panel.ignoresMouseEvents = !inside
            if inside {
                islandCollapseWork?.cancel()
                islandCollapseWork = nil
                if !panelModel.islandExpanded { panelModel.islandExpanded = true }
            } else if panelModel.islandExpanded, islandCollapseWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        self.islandCollapseWork = nil
                        self.panelModel.islandExpanded = false
                        self.panelModel.volumeOpen = false
                    }
                }
                islandCollapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            }
            return
        }

        let inside = panel.frame.contains(mouse)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    // MARK: - Mostrar y esconder

    func showPanel() {
        autoHidden = false
        guard !panel.isVisible else { return }
        placePanel(for: panelModel.mode)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        fade(to: 1, duration: 0.25)
        evaluateIdle()
    }

    func hidePanel(manual: Bool = true) {
        if manual { autoHidden = false }
        guard panel.isVisible else { return }
        panelModel.isHovering = false
        panelModel.islandExpanded = false
        panelModel.volumeOpen = false
        fade(to: 0, duration: 0.2) { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    func togglePanel() {
        isPanelVisible ? hidePanel() : showPanel()
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

    // MARK: - Menús

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

    // MARK: - Barra de menú

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Musicfy")
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Clic: muestra o esconde el player. Clic derecho (o con Control): el menú.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = Menus.main(app: self)
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePanel()
        }
    }
}
