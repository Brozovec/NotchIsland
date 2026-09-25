import Foundation
import ServiceManagement

/// Spouštění po přihlášení přes SMAppService (macOS 13+). Zapne se při prvním startu, dá se vypnout v Nastavení.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { Log.w("launch at login \(on): \(error)") }
    }
    static func enableOnFirstLaunch() {
        let key = "launchAtLoginConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(true)
    }
}
