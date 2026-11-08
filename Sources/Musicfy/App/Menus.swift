import AppKit
import ServiceManagement
import SwiftUI

/// NSMenuItem con un bloque en vez de target/selector.
final class BlockMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        state = checked ? .on : .off
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    @objc private func fire() { handler() }
}

extension NSMenu {
    @discardableResult
    func add(_ title: String, checked: Bool = false, key: String = "", _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = BlockMenuItem(title, checked: checked, key: key, handler: handler)
        addItem(item)
        return item
    }

    func addHeader(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    func addSubmenu(_ title: String, _ build: (NSMenu) -> Void) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        build(submenu)
        item.submenu = submenu
        addItem(item)
    }
}

@MainActor
enum Menus {
    /// El menú de los tres puntos, del clic derecho y de la barra de menú.
    /// Arriba, los tres modos con su dibujito; después lo del tema; los botones a la vista;
    /// y al final lo de la app.
    static func main(app: AppDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        menu.minimumWidth = 320
        let player = app.player
        let settings = app.settings

        // Modos.
        let cards = ModeCardsView(
            current: app.panelModel.mode == .island ? .island : settings.mode,
            accent: Color(nsColor: player.palette.accent),
            choose: { [weak menu] mode in
                menu?.cancelTracking()
                app.userSwitch(to: mode)
            }
        )
        menu.addItem(viewItem(cards))
        // ⌘1, ⌘2, ⌘3 con el menú abierto.
        for (index, mode) in DisplayMode.allCases.enumerated() {
            let item = menu.add(mode.label, key: "\(index + 1)") { app.userSwitch(to: mode) }
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
        }
        menu.addItem(.separator())

        // El tema.
        if let state = player.state {
            if state.source.supportsFavorite {
                let like = menu.add("Me gusta", key: "l") { player.toggleFavorite() }
                like.image = symbol(state.favorited ? "star.fill" : "star")
            }
            menu.add("Mostrar en \(state.source.displayName)") { player.open(state.source) }
                .image = symbol("arrow.up.forward.app")
            menu.add("Copiar enlace del tema") {
                Task {
                    guard let url = await TrackLink.url(for: state) else { NSSound.beep(); return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
            .image = symbol("link")
            menu.addItem(.separator())
        }

        // Botones a la vista.
        menu.addItem(viewItem(VisibleButtonsView(settings: settings)))
        menu.addItem(.separator())

        menu.add("Achicar al pausar", checked: settings.idleBehavior == .compact) {
            settings.idleBehavior = settings.idleBehavior == .compact ? .stay : .compact
        }
        let hide = menu.add(app.isPanelVisible ? "Esconder Musicfy" : "Mostrar Musicfy", key: "m") { app.togglePanel() }
        hide.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(.separator())

        menu.addSubmenu("Salida de audio") { sub in
            let current = AudioOutputs.current
            for device in AudioOutputs.all() {
                sub.add(device.name, checked: device.id == current) { AudioOutputs.select(device.id) }
            }
        }
        menu.addSubmenu("Qué app mostrar") { sub in
            sub.add("La que esté sonando", checked: settings.forcedSource == nil) { settings.forcedSource = nil }
            sub.addItem(.separator())
            for kind in SourceKind.allCases where kind.isInstalled {
                sub.add("Siempre \(kind.displayName)", checked: settings.forcedSource == kind) { settings.forcedSource = kind }
            }
        }
        let login = SMAppService.mainApp
        menu.add("Abrir al iniciar sesión", checked: login.status == .enabled) {
            do {
                if login.status == .enabled {
                    try login.unregister()
                } else {
                    try login.register()
                }
            } catch {
                NSLog("Musicfy: no se pudo cambiar el inicio automático: \(error)")
            }
        }
        menu.addItem(.separator())
        menu.add("Salir de Musicfy", key: "q") { NSApp.terminate(nil) }
        return menu
    }

    private static func viewItem<V: View>(_ view: V) -> NSMenuItem {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let item = NSMenuItem()
        item.view = hosting
        return item
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    static func output() -> NSMenu {
        let menu = NSMenu()
        menu.addHeader("Salida de audio")
        let current = AudioOutputs.current
        for device in AudioOutputs.all() {
            menu.add(device.name, checked: device.id == current) { AudioOutputs.select(device.id) }
        }
        return menu
    }
}
