import AppKit
import ServiceManagement
import SwiftUI

/// NSMenuItem with a closure instead of target/selector.
final class BlockMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        state = checked ? .on : .off
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { handler() }
}

extension NSMenu {
    /// Adds an item. In menus without a state column (`showsStateColumn = false`) a toggle's
    /// check goes in the icon column, and items without an icon get a blank one, so every
    /// title starts at the same x.
    @discardableResult
    func add(_ title: String, checked: Bool = false, key: String = "", icon: String? = nil, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = BlockMenuItem(title, checked: checked, key: key, handler: handler)
        if showsStateColumn {
            if let icon { item.image = MenuIcon.symbol(icon) }
        } else {
            item.state = .off
            item.image = checked ? MenuIcon.symbol("checkmark") : icon.flatMap(MenuIcon.symbol) ?? MenuIcon.blank
        }
        addItem(item)
        return item
    }

    func addHeader(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    @discardableResult
    func addSubmenu(_ title: String, icon: String? = nil, _ build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = icon.flatMap(MenuIcon.symbol) ?? (showsStateColumn ? nil : MenuIcon.blank)
        let submenu = NSMenu(title: title)
        submenu.appearance = appearance
        build(submenu)
        item.submenu = submenu
        addItem(item)
        return item
    }
}

/// Menu icons: 14 pt symbols in a 16 pt column.
enum MenuIcon {
    static func symbol(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        // Centered in a fixed 16 × 16 box so titles line up whatever the symbol's width.
        let box = NSSize(width: 16, height: 16)
        let image = NSImage(size: box, flipped: false) { rect in
            let size = symbol.size
            symbol.draw(in: NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2, width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        return image
    }

    static let blank: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }()
}

@MainActor
enum Menus {
    /// The "…" menu, also used for right click and the menu bar icon. A native 264 pt menu:
    /// the mode selector on top, then the song, the settings submenus, and the app.
    static func main(app: AppDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        menu.minimumWidth = 264
        menu.showsStateColumn = false
        let player = app.player
        let settings = app.settings

        // Modes.
        let selector = ModeSelectorView(current: app.panelModel.mode) { [weak menu] mode in
            menu?.cancelTracking()
            app.userSwitch(to: mode)
        }
        menu.addItem(viewItem(selector))
        // ⌘1, ⌘2, ⌘3 while the menu is open (shown in the segments' tooltips).
        for (index, mode) in DisplayMode.allCases.enumerated() {
            let item = menu.add(mode.label, key: "\(index + 1)") { app.userSwitch(to: mode) }
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
        }
        menu.addItem(.separator())

        // The song.
        if let state = player.state {
            if state.source.supportsFavorite {
                menu.add("Favorite", key: "l", icon: state.favorited ? "star.fill" : "star") { player.toggleFavorite() }
            }
            menu.add("Show in \(state.source.displayName)", icon: "arrow.up.forward.app") { player.open(state.source) }
            menu.add("Copy Song Link", icon: "link") {
                Task {
                    guard let url = await TrackLink.url(for: state) else { NSSound.beep(); return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
            menu.addItem(.separator())
        }

        // Small artwork hides shuffle, repeat and volume from the player, and mini artwork
        // everything but play/pause: one playback card and the volume take their place.
        if app.panelModel.mode == .artwork, app.panelModel.artworkDensity <= .small, player.state != nil {
            menu.addItem(viewItem(MenuTransportView(player: player)))
            menu.addItem(volumeItem(player: player))
            menu.addItem(.separator())
        }

        menu.addSubmenu("Audio Output", icon: "hifispeaker") { sub in
            fillOutputs(sub)
        }
        menu.addSubmenu("Source", icon: "music.note.list") { sub in
            sub.add("Automatic", checked: settings.forcedSource == nil) { settings.forcedSource = nil }
            sub.addItem(.separator())
            for kind in SourceKind.allCases where kind.isInstalled {
                sub.add(kind.displayName, checked: settings.forcedSource == kind) { settings.forcedSource = kind }
            }
        }
        menu.addSubmenu("Show Buttons", icon: "slider.horizontal.3") { sub in
            sub.add("Lyrics", checked: settings.showLyricsButton, icon: "quote.bubble") { settings.showLyricsButton.toggle() }
            sub.add("Up Next", checked: settings.showQueueButton, icon: "list.bullet") { settings.showQueueButton.toggle() }
            sub.add("Volume", checked: settings.showVolume, icon: "speaker.wave.2") { settings.showVolume.toggle() }
            sub.add("Audio Output", checked: settings.showOutput, icon: "airplayaudio") { settings.showOutput.toggle() }
        }
        menu.addItem(.separator())

        menu.add("Shrink When Paused", checked: settings.idleBehavior == .compact) {
            settings.idleBehavior = settings.idleBehavior == .compact ? .stay : .compact
        }
        menu.add("Show Over Videos", checked: settings.showOverFullScreen) {
            settings.showOverFullScreen.toggle()
        }
        let login = SMAppService.mainApp
        menu.add("Open at Login", checked: login.status == .enabled) {
            do {
                if login.status == .enabled {
                    try login.unregister()
                } else {
                    try login.register()
                }
            } catch {
                NSLog("Musicfy: couldn't change Open at Login: \(error)")
            }
        }
        let hide = menu.add(app.isPanelVisible ? "Hide Musicfy" : "Show Musicfy", key: "m") { app.togglePanel() }
        hide.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(.separator())
        menu.add("Quit Musicfy", key: "q") { NSApp.terminate(nil) }
        return menu
    }

    /// Audio output devices, with a check on the current one, and a way to the system settings.
    /// A volume slider row, lined up with the titles.
    static func volumeItem(player: PlayerController) -> NSMenuItem {
        let item = NSMenuItem()
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 264, height: 24))
        let icon = NSImageView(frame: NSRect(x: 16, y: 4, width: 16, height: 16))
        icon.image = MenuIcon.symbol("speaker.wave.2")
        icon.contentTintColor = .labelColor
        let slider = NSSlider(value: Double(player.state?.volume ?? 0), minValue: 0, maxValue: 100, target: nil, action: nil)
        slider.frame = NSRect(x: 37, y: 2, width: 264 - 37 - 16, height: 20)
        slider.controlSize = .small
        slider.isContinuous = true
        let target = SliderTarget { player.setVolume(Int($0.rounded())) }
        slider.target = target
        slider.action = #selector(SliderTarget.changed(_:))
        item.representedObject = target // keeps the target alive with the item
        row.addSubview(icon)
        row.addSubview(slider)
        item.view = row
        return item
    }

    static func output() -> NSMenu {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        menu.addHeader("Audio Output")
        fillOutputs(menu)
        return menu
    }

    private static func fillOutputs(_ menu: NSMenu) {
        let current = AudioOutputs.current
        for device in AudioOutputs.all() {
            menu.add(device.name, checked: device.id == current) { AudioOutputs.select(device.id) }
        }
        menu.addItem(.separator())
        menu.add("Sound Settings…") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private static func viewItem<V: View>(_ view: V) -> NSMenuItem {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let item = NSMenuItem()
        item.view = hosting
        return item
    }
}

/// Sends an NSSlider's value to a closure.
final class SliderTarget: NSObject {
    private let onChange: (Double) -> Void

    init(_ onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
    }

    @objc func changed(_ sender: NSSlider) {
        onChange(sender.doubleValue)
    }
}
