import AppKit
import SwiftUI

/// Nastavení jako samostatné okno (aktivuje appku, takže funguje ⌘V, výběr textu i klávesnice).
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = L("Nastavení") + " – NotchIsland"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 460, height: 400)
            w.contentView = NSHostingView(rootView: SettingsView().padding(14).frame(minWidth: 440, maxWidth: .infinity, minHeight: 380, maxHeight: .infinity).background(Color(white: 0.11)))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
