import Foundation
import AppKit

/// Systémové "Now Playing" (to, co ukazuje macOS v Ovládacím centru) – Spotify, Hudba, Chrome/Safari (YouTube), cokoli.
/// Čte se přes MediaRemote adaptér spouštěný z /usr/bin/perl, protože macOS 15.4+ MediaRemote appkám blokuje.
final class SystemNowPlaying: @unchecked Sendable {
    static let shared = SystemNowPlaying()
    struct Info: Equatable {
        var title: String; var artist: String; var album: String; var bundleId: String
        var playing: Bool; var duration: Double; var elapsed: Double; var timestamp: Date
        var position: Double { playing ? elapsed + Date().timeIntervalSince(timestamp) : elapsed }
    }
    private(set) var available = false
    private var process: Process?
    private let lock = NSLock()
    private var latest: Info?
    private var lastLine = Date.distantPast

    private var script: String? { Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl") }
    private var framework: String? { Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter.framework").path }

    private init() {}

    func start() {
        guard let script, let framework, FileManager.default.fileExists(atPath: framework + "/MediaRemoteAdapter") else { Log.w("nowplaying adapter missing"); return }
        let test = Process(); test.executableURL = URL(fileURLWithPath: "/usr/bin/perl"); test.arguments = [script, framework, "test"]
        test.standardOutput = FileHandle.nullDevice; test.standardError = FileHandle.nullDevice
        try? test.run(); test.waitUntilExit()
        available = test.terminationStatus == 0
        Log.w("nowplaying adapter available=\(available)")
        guard available else { return }
        launchStream()
    }

    private func launchStream() {
        guard let script, let framework else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script, framework, "stream", "--no-diff", "--no-artwork", "--debounce=200"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            buffer.append(d)
            while let nl = buffer.firstIndex(of: 10) {
                let line = buffer[..<nl]; buffer.removeSubrange(...nl)
                self?.handle(line)
            }
        }
        p.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { self?.launchStream() }   // adaptér spadl → restart
        }
        do { try p.run(); process = p } catch { Log.w("nowplaying stream failed: \(error)") }
    }

    private func handle(_ line: Data) {
        guard let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        lock.lock(); defer { lock.unlock() }
        lastLine = Date()
        // stream posílá i prázdné/nulové payloady, když nic nehraje
        let title = j["title"] as? String ?? ""
        guard !title.isEmpty else { latest = nil; return }
        let ts = (j["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        latest = Info(title: title, artist: j["artist"] as? String ?? "", album: j["album"] as? String ?? "",
                      bundleId: j["bundleIdentifier"] as? String ?? (j["parentApplicationBundleIdentifier"] as? String ?? ""),
                      playing: j["playing"] as? Bool ?? false, duration: j["duration"] as? Double ?? 0,
                      elapsed: j["elapsedTime"] as? Double ?? 0, timestamp: ts)
    }

    func current() -> Info? { lock.lock(); defer { lock.unlock() }; return latest }

    /// Obal alba (jednorázově, ~0.1 s) – volat při změně skladby.
    func fetchArtwork() -> NSImage? {
        guard let script, let framework else { return nil }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/perl"); p.arguments = [script, framework, "get"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try? p.run()
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let b64 = j["artworkData"] as? String, let data = Data(base64Encoded: b64) else { return nil }
        return NSImage(data: data)
    }

    /// Příkazy: 2 = play/pause, 4 = další, 5 = předchozí.
    func send(_ command: Int) {
        guard let script, let framework else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/perl"); p.arguments = [script, framework, "send", "\(command)"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    static func appName(_ bundleId: String) -> String {
        switch bundleId {
        case "com.spotify.client": return "Spotify"
        case "com.apple.Music": return "Hudba"
        case "com.google.Chrome": return "Chrome"
        case "com.apple.Safari": return "Safari"
        case "com.brave.Browser": return "Brave"
        case "company.thebrowser.Browser": return "Arc"
        case "org.mozilla.firefox": return "Firefox"
        case "com.microsoft.edgemac": return "Edge"
        default:
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleId
        }
    }
}
