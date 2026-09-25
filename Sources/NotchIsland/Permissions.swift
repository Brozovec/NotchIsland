import AppKit
import EventKit
import CoreGraphics

/// Při prvním startu si vyžádá všechna oprávnění najednou. Díky stabilnímu podpisu (Apple Development)
/// si je macOS pamatuje i po dalších buildech, takže se neptá dokola.
enum Permissions {
    private static let doneKey = "permissionsRequested.v1"

    static func requestAllOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        UserDefaults.standard.set(true, forKey: doneKey)
        Task { @MainActor in
            // 1) Nahrávání obrazovky (screenshoty)
            if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
            // 2) Kalendář
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                _ = try? await EKEventStore().requestFullAccessToEvents()
            }
            // 3) Automatizace (ovládání Spotify / Hudby) – dialog macOS ukáže jen pro běžící appku
            for bundle in ["com.spotify.client", "com.apple.Music"] { requestAutomation(bundle) }
        }
    }

    private static func requestAutomation(_ bundleId: String) {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleId }) else { return }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleId)
        DispatchQueue.global().async {
            _ = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
        }
    }

    /// Umožní znovu vyvolat dialogy (např. z nastavení).
    static func reset() { UserDefaults.standard.removeObject(forKey: doneKey); requestAllOnFirstLaunch() }
}
