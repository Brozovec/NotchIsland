import AppKit
import Combine

struct NowPlaying: Equatable {
    enum Source: String { case spotify = "Spotify", music = "Hudba" }
    var source: Source
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var durationSec: Double
    var positionSec: Double
    var artworkURL: URL?
}

/// Čte stav přehrávače ze Spotify / Apple Music přes AppleScript, 1× za sekundu.
@MainActor
final class MusicService: ObservableObject {
    static let shared = MusicService()
    @Published private(set) var now: NowPlaying?
    @Published private(set) var artwork: NSImage?
    private var timer: Timer?
    private var lastArtKey = ""

    private init() { start() }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { await self?.poll() }
        }
        Task { await poll() }
    }

    private func isRunning(_ bundle: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundle }
    }

    private func poll() async {
        let result: NowPlaying? = await Task.detached(priority: .utility) { [self] () -> NowPlaying? in
            if await isRunning("com.spotify.client"), let n = Self.readSpotify() { return n }
            if await isRunning("com.apple.Music"), let n = Self.readMusic() { return n }
            return nil
        }.value
        if result != now { now = result }
        await updateArtwork()
    }

    private func updateArtwork() async {
        guard let n = now else { artwork = nil; lastArtKey = ""; return }
        let key = n.source.rawValue + "|" + n.title + "|" + n.artist + "|" + n.album + "|" + (n.artworkURL?.absoluteString ?? "")
        guard key != lastArtKey else { return }
        artwork = nil // skladba se změnila – starý obal pryč hned, nový dotáhneme
        var loaded: NSImage?
        if let url = n.artworkURL {
            if let (data, _) = try? await URLSession.shared.data(from: url) { loaded = NSImage(data: data) }
        } else if n.source == .music {
            loaded = await Task.detached { Self.readMusicArtwork() }.value
        }
        // klíč si zapamatujeme jen při úspěchu, jinak to zkusíme v dalším kole znovu
        guard key == currentKey() else { return }
        if let loaded { artwork = loaded; lastArtKey = key }
    }

    private func currentKey() -> String {
        guard let n = now else { return "" }
        return n.source.rawValue + "|" + n.title + "|" + n.artist + "|" + n.album + "|" + (n.artworkURL?.absoluteString ?? "")
    }

    // MARK: AppleScript
    nonisolated private static func run(_ src: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
        return err == nil ? r : nil
    }

    nonisolated private static func readSpotify() -> NowPlaying? {
        let src = """
        tell application "Spotify"
            set s to player state as string
            set t to current track
            return s & "\\n" & (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & (artwork url of t) & "\\n" & (duration of t) & "\\n" & (player position)
        end tell
        """
        guard let r = run(src)?.stringValue else { return nil }
        let p = r.components(separatedBy: "\n")
        guard p.count >= 7 else { return nil }
        return NowPlaying(source: .spotify, isPlaying: p[0] == "playing", title: p[1], artist: p[2], album: p[3],
                          durationSec: (Double(p[5]) ?? 0) / 1000, positionSec: Double(p[6].replacingOccurrences(of: ",", with: ".")) ?? 0,
                          artworkURL: URL(string: p[4]))
    }

    nonisolated private static func readMusic() -> NowPlaying? {
        let src = """
        tell application "Music"
            set s to player state as string
            set t to current track
            return s & "\\n" & (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & (duration of t) & "\\n" & (player position)
        end tell
        """
        guard let r = run(src)?.stringValue else { return nil }
        let p = r.components(separatedBy: "\n")
        guard p.count >= 6 else { return nil }
        return NowPlaying(source: .music, isPlaying: p[0] == "playing", title: p[1], artist: p[2], album: p[3],
                          durationSec: Double(p[4].replacingOccurrences(of: ",", with: ".")) ?? 0,
                          positionSec: Double(p[5].replacingOccurrences(of: ",", with: ".")) ?? 0, artworkURL: nil)
    }

    nonisolated private static func readMusicArtwork() -> NSImage? {
        guard let d = run("tell application \"Music\" to return data of artwork 1 of current track") else { return nil }
        return NSImage(data: d.data)
    }

    // MARK: ovládání
    private func control(_ cmd: String) {
        guard let n = now else { return }
        let app = n.source == .spotify ? "Spotify" : "Music"
        Task.detached { _ = Self.run("tell application \"\(app)\" to \(cmd)") }
    }
    func playPause() { control("playpause") }
    func next() { control("next track") }
    func previous() { control("previous track") }
}
