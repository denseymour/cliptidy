import AppKit
import ServiceManagement

/// Owns the menu bar item, the preferences, and the clipboard watcher.
final class AppController: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    private let defaults = UserDefaults.standard
    private let autoKey = "autoCleanEnabled"
    private let modeKey = "cleanMode"

    private var autoClean: Bool {
        get { defaults.bool(forKey: autoKey) }
        set { defaults.set(newValue, forKey: autoKey) }
    }

    private var mode: CleanMode {
        get { CleanMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .joinParagraphs }
        set { defaults.set(newValue.rawValue, forKey: modeKey) }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        startWatching()
    }

    // MARK: - Menu

    private func buildMenu() {
        updateIcon()

        let menu = NSMenu()

        let cleanNow = item("Clean Clipboard Now", #selector(cleanNow))
        cleanNow.keyEquivalent = "c"
        cleanNow.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(cleanNow)

        let auto = item("Auto-clean on Copy", #selector(toggleAuto))
        auto.state = autoClean ? .on : .off
        menu.addItem(auto)

        menu.addItem(.separator())
        menu.addItem(header("Mode"))
        for m in CleanMode.allCases {
            let mi = item(m.rawValue, #selector(selectMode(_:)))
            mi.representedObject = m.rawValue
            mi.state = (m == mode) ? .on : .off
            mi.toolTip = m.detail
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(header("ClipTidy"))
        let quit = item("Quit", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbol = autoClean ? "wand.and.sparkles.inverse" : "wand.and.sparkles"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ClipTidy")
        button.image?.isTemplate = true
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        return mi
    }

    private func header(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        return mi
    }

    // MARK: - Actions

    @objc private func cleanNow() {
        applyClean()
    }

    @objc private func toggleAuto() {
        autoClean.toggle()
        buildMenu()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = CleanMode(rawValue: raw) {
            mode = m
            buildMenu()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Clipboard

    private func startWatching() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.pollClipboard()
        }
    }

    private func pollClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard autoClean else { return }
        applyClean()
    }

    /// Reads the clipboard, cleans it with the current mode, and writes it
    /// back. Records our own write so the watcher does not reprocess it.
    private func applyClean() {
        let pb = NSPasteboard.general
        guard let original = pb.string(forType: .string), !original.isEmpty else { return }
        let cleaned = Cleaner.clean(original, mode: mode)
        guard cleaned != original else { return }
        pb.clearContents()
        pb.setString(cleaned, forType: .string)
        lastChangeCount = pb.changeCount
    }

    // MARK: - Launch at login

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Login item registration only works for a bundled, launched .app.
            // Ignore failures (for example when run via `swift run`).
        }
        buildMenu()
    }
}
