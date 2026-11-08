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
    private var islandHoverSince: Date?
    /// La tapa pasó a compacto porque no suena nada (no porque lo eligió el usuario).
    private var idleCompact = false
    /// Se escondió solo; vuelve cuando algo suena.
    private var autoHidden = false
    private var menuOpen = false
    private var applyingFrame = false
    /// El usuario pidió otro modo estando en pausa: no se vuelve a achicar solo hasta que suene algo.
    private var userOverrodeIdle = false
    private var swapGeneration = 0
    // Arrastre de la ventana (para soltarla arriba al centro y que se vuelva Isla).
    private var draggingWindow = false
    private var dragStartAnchor: NSPoint?
    // Cambio de tamaño desde los bordes.
    private var resizeStartFrame = NSRect.zero
    private var resizeStartSide: CGFloat = 0

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
        // Encima de la interfaz, una capa invisible que toma sólo los bordes para agrandar.
        let grip = ResizeGripView()
        grip.allowedEdges = { [weak self] in self?.resizableEdges ?? [] }
        grip.onBegin = { [weak self] in self?.beginResize() }
        grip.onResize = { [weak self] edges, dx, dy in self?.resize(edges: edges, dx: dx, dy: dy) ?? false }
        grip.onEnd = { [weak self] in self?.endResize() }
        let container = NSView(frame: NSRect(origin: .zero, size: Theme.artworkSize))
        for view in [hosting, grip] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        panel.contentView = container

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
                if self.panelModel.mode != .island, !self.panelModel.swapOut { self.animateFrame(to: self.framedRect(for: self.panelModel.mode)) }
                // Con un panel abierto la tapa no se achica; al cerrarlo, sí (si sigue en pausa).
                self.evaluateIdle()
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
            userOverrodeIdle = false
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
            if settings.mode == .artwork, panelModel.mode == .artwork, panelModel.drawer == .none, !userOverrodeIdle {
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

        if !animated || !panel.isVisible {
            panelModel.mode = to
            placePanel(for: to)
            return
        }
        if from == .island || to == .island {
            swap(to: to)
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

    /// De o hacia la Isla la ventana cambia de lugar y de forma. La vista que se va se achica
    /// hacia arriba, se desenfoca y se apaga; la ventana salta a su lugar nuevo sin que se vea
    /// y la vista nueva llega desde arriba con un resorte, enfocándose.
    private func swap(to mode: DisplayMode) {
        swapGeneration += 1
        let generation = swapGeneration
        withAnimation(.easeIn(duration: 0.15)) { panelModel.swapOut = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { @MainActor in
                guard let self, self.swapGeneration == generation else { return }
                self.panelModel.mode = mode
                self.placePanel(for: mode)
                self.panel.hasShadow = false
                self.panel.alphaValue = 1
                DispatchQueue.main.async {
                    Task { @MainActor in
                        guard self.swapGeneration == generation else { return }
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { self.panelModel.swapOut = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            Task { @MainActor in
                                guard self.swapGeneration == generation, self.panelModel.mode != .island else { return }
                                self.panel.hasShadow = true
                                self.panel.invalidateShadow()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Cambio de modo pedido con un gesto (tirar de un borde, soltar arriba, bajar la Isla).
    private func userSwitch(to mode: DisplayMode) {
        if !isPlaying { userOverrodeIdle = true }
        if settings.mode == mode {
            idleCompact = false
            updateMode(animated: true)
        } else {
            settings.mode = mode // el observador hace el resto
        }
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
            let base = mode == .artwork
                ? CGSize(width: panelModel.artworkSide, height: panelModel.artworkSide)
                : Theme.compactSize
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
        let margin = Theme.islandShadowMargin
        let x: CGFloat
        switch panelModel.islandAlignment {
        case .leading: x = visible.minX + Theme.islandSideGap - margin
        case .center: x = visible.midX - size.width / 2
        case .trailing: x = visible.maxX - Theme.islandSideGap + margin - size.width
        }
        return NSRect(x: x, y: visible.maxY - Theme.islandTopGap - size.height, width: size.width, height: size.height)
    }

    /// Distancia del borde izquierdo de la ventana al de la cápsula.
    private func islandPillOffset(width: CGFloat, alignment: IslandAlignment) -> CGFloat {
        let margin = Theme.islandShadowMargin
        switch alignment {
        case .leading: return margin
        case .center: return (islandWindowSize.width - width) / 2
        case .trailing: return islandWindowSize.width - margin - width
        }
    }

    /// Dónde está la cápsula dentro de la ventana de la Isla, en coordenadas de pantalla.
    private func islandPillRect() -> NSRect {
        let frame = panel.frame
        let size = panelModel.islandExpanded ? Theme.islandExpanded : Theme.islandCollapsed
        let x = frame.minX + islandPillOffset(width: size.width, alignment: panelModel.islandAlignment)
        return NSRect(x: x, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Al soltar la Isla después de arrastrarla: se pega a la izquierda, al centro o a la derecha.
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
        // Se cambia la alineación sin que la cápsula salte y después se la lleva a su lugar.
        if target != panelModel.islandAlignment {
            panelModel.islandAlignment = target
            var frame = panel.frame
            frame.origin.x = pill.minX - islandPillOffset(width: pill.width, alignment: target)
            panel.setFrame(frame, display: true)
        }
        animateFrame(to: islandWindowRect())
    }

    func windowDidMove(_ notification: Notification) {
        guard !applyingFrame, panelModel.mode != .island else { return }
        anchor = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    // MARK: - Agrandar y achicar desde los bordes

    /// Tapa: todos los bordes (con un panel abierto, el de abajo es del panel). Compacto: sólo
    /// el de abajo, para estirarlo hasta la tapa. Isla: ninguno.
    private var resizableEdges: ResizeEdges {
        guard !panelModel.swapOut else { return [] }
        switch panelModel.mode {
        case .artwork: return panelModel.drawer == .none ? .all : [.left, .right, .top]
        case .compact: return panelModel.drawer == .none ? .bottom : []
        case .island: return []
        }
    }

    private func beginResize() {
        resizeStartFrame = panel.frame
        resizeStartSide = panelModel.artworkSide
    }

    /// Devuelve `false` cuando el gesto termina en otro modo.
    private func resize(edges: ResizeEdges, dx: CGFloat, dy: CGFloat) -> Bool {
        let range = Theme.artworkSideRange
        switch panelModel.mode {
        case .artwork:
            var horizontal: CGFloat = 0, vertical: CGFloat = 0
            if edges.contains(.right) { horizontal = dx } else if edges.contains(.left) { horizontal = -dx }
            if edges.contains(.bottom) { vertical = -dy } else if edges.contains(.top) { vertical = dy }
            let proposed = resizeStartSide + (abs(horizontal) >= abs(vertical) ? horizontal : vertical)

            // Achicarla bastante más allá del mínimo la pasa a compacto.
            if proposed < range.lowerBound - 56 {
                panelModel.artworkSide = range.lowerBound
                userSwitch(to: .compact)
                return false
            }
            // Pasado el mínimo o el máximo, se resiste como una goma.
            let side: CGFloat
            if proposed < range.lowerBound {
                side = range.lowerBound - (range.lowerBound - proposed) * 0.25
            } else if proposed > range.upperBound {
                side = range.upperBound + (proposed - range.upperBound) * 0.25
            } else {
                side = proposed
            }
            let extra = panelModel.drawer == .none ? 0 : Theme.drawerHeight
            // Queda fija la esquina opuesta a la que se tira.
            let top = edges.contains(.top) ? resizeStartFrame.maxY - resizeStartSide + side : resizeStartFrame.maxY
            let left = edges.contains(.left) ? resizeStartFrame.maxX - side : resizeStartFrame.minX
            panelModel.artworkSide = side
            panel.setFrame(NSRect(x: left, y: top - side - extra, width: side, height: side + extra), display: true)
            return true

        case .compact:
            let pull = -dy // hacia abajo
            // Estirar el compacto hacia abajo lo vuelve tapa.
            if pull > 52 {
                userSwitch(to: .artwork)
                return false
            }
            let stretch = max(0, pull) * 0.35
            var frame = resizeStartFrame
            frame.size.height += stretch
            frame.origin.y -= stretch
            panel.setFrame(frame, display: true)
            return true

        case .island:
            return false
        }
    }

    private func endResize() {
        let range = Theme.artworkSideRange
        let clamped = min(max(panelModel.artworkSide, range.lowerBound), range.upperBound)
        if clamped != panelModel.artworkSide { panelModel.artworkSide = clamped }
        guard panelModel.mode != .island else { return }
        let target = framedRect(for: panelModel.mode)
        if target != panel.frame {
            animateFrame(to: target) // vuelve la goma
        } else {
            panel.invalidateShadow()
        }
    }

    // MARK: - Arrastrar entre modos

    /// Zona de la Isla: arriba al centro de la pantalla con la barra de menú.
    private func isInIslandZone(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let visible = screen.visibleFrame
        return point.y > visible.maxY - 64 && point.y <= screen.frame.maxY && abs(point.x - visible.midX) < 200
    }

    /// Lo llama la zona de arrastre al apretar el mouse sobre la tapa o el compacto.
    func windowDragBegan() {
        guard panelModel.mode != .island else { return }
        draggingWindow = true
        dragStartAnchor = anchor
    }

    /// Al soltar: si quedó arriba al centro, se vuelve Isla.
    func windowDragEnded() {
        guard draggingWindow else { return }
        draggingWindow = false
        let drop = panelModel.islandHint
        withAnimation(Theme.smooth) { panelModel.islandHint = false }
        guard drop else { return }
        // La tapa vuelve a donde estaba antes del arrastre cuando se salga de la Isla.
        if let start = dragStartAnchor { anchor = start }
        panelModel.islandAlignment = .center
        userSwitch(to: .island)
    }

    private func trackWindowDrag(mouse: NSPoint) {
        guard draggingWindow else { return }
        if NSEvent.pressedMouseButtons & 1 == 0 {
            windowDragEnded()
            return
        }
        let hint = isInIslandZone(mouse)
        if hint != panelModel.islandHint {
            withAnimation(Theme.smooth) { panelModel.islandHint = hint }
        }
    }

    /// La Isla se tira hacia abajo: va siguiendo al mouse.
    func islandPulled(by distance: CGFloat) {
        let progress = min(1, max(0, distance / Theme.islandPullThreshold))
        if abs(progress - panelModel.islandPull) > 0.01 {
            panelModel.islandPull = progress
        }
    }

    /// Se soltó la Isla después de tirarla hacia abajo. Si pasó el umbral, se vuelve tapa
    /// justo debajo de donde quedó; si no, vuelve a su lugar.
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
        trackWindowDrag(mouse: mouse)

        if panelModel.mode == .island {
            let inside = islandPillRect().insetBy(dx: -2, dy: -2).contains(mouse)
            panel.ignoresMouseEvents = !inside
            if inside {
                islandCollapseWork?.cancel()
                islandCollapseWork = nil
                if !panelModel.islandExpanded {
                    // Se abre si el mouse se queda 0,15 s: pasar de largo no la despliega.
                    let since = islandHoverSince ?? Date()
                    islandHoverSince = since
                    if Date().timeIntervalSince(since) >= 0.15 { panelModel.islandExpanded = true }
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
                }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + Theme.hoverExitDelay, execute: work)
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
