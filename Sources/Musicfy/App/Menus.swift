import AppKit
import ServiceManagement

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
    static func main(app: AppDelegate) -> NSMenu {
        let menu = NSMenu()
        let player = app.player
        let settings = app.settings

        if let state = player.state {
            menu.addHeader(state.title.isEmpty ? "Sonando en \(state.source.displayName)" : "\(state.title) · \(state.source.displayName)")
            menu.add("Abrir \(state.source.displayName)") { player.open(state.source) }
            menu.addItem(.separator())
        }

        menu.add(app.isPanelVisible ? "Esconder player" : "Mostrar player") { app.togglePanel() }

        menu.addSubmenu("Modo") { sub in
            for mode in DisplayMode.allCases {
                sub.add(mode.label, checked: settings.mode == mode) { settings.mode = mode }
            }
        }
        menu.addSubmenu("Qué app mostrar") { sub in
            sub.add("La que esté sonando", checked: settings.forcedSource == nil) { settings.forcedSource = nil }
            sub.addItem(.separator())
            for kind in SourceKind.allCases where kind.isInstalled {
                sub.add("Siempre \(kind.displayName)", checked: settings.forcedSource == kind) { settings.forcedSource = kind }
            }
        }
        menu.addSubmenu("Botones") { sub in
            sub.add("Letras", checked: settings.showLyricsButton) { settings.showLyricsButton.toggle() }
            sub.add("Volumen", checked: settings.showVolume) { settings.showVolume.toggle() }
            sub.add("Salida de audio", checked: settings.showOutput) { settings.showOutput.toggle() }
        }
        menu.addSubmenu("Cuando no suena nada") { sub in
            for behavior in IdleBehavior.allCases {
                sub.add(behavior.label, checked: settings.idleBehavior == behavior) { settings.idleBehavior = behavior }
            }
        }

        menu.addItem(.separator())
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
