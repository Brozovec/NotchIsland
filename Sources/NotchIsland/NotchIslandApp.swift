import AppKit
import SwiftUI

@main
struct NotchIslandApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FA.register()
        installMainMenu()
        Permissions.requestAllOnFirstLaunch()
        LaunchAtLogin.enableOnFirstLaunch()
        controller = NotchController()
        controller?.show()
        ScreenshotService.shared.openClipboard = { [weak self] in self?.controller?.open(tab: .clipboard) }
        ClipboardService.closePanel = { [weak self] in self?.controller?.close() }
        setupStatusItem()
    }

    /// Hlavní menu s Úpravami – bez něj ⌘C/⌘V/⌘X/⌘A/⌘Z v oknech appky nefungují.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("Nastavení…"), action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Ukončit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]; edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = win
        NSApp.mainMenu = main
    }

    @objc private func openSettings() { Task { @MainActor in SettingsWindow.show() } }

    @objc private func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
    }

    private func setupStatusItem() {
        // Zpřístupnění pro vkládání ze schránky – zeptat se rovnou při startu (jen jednou)
        if !UserDefaults.standard.bool(forKey: "axPrompted") {
            UserDefaults.standard.set(true, forKey: "axPrompted")
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchIsland")
        let menu = NSMenu()
        menu.addItem(withTitle: L("NotchIsland 0.1"), action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("Nastavení…"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: L("Otevřít Soukromí a zabezpečení…"), action: #selector(openPrivacy), keyEquivalent: "")
        menu.addItem(withTitle: L("Ukončit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}
