import Foundation
import Network

/// Lokální HTTP server pro rozšíření prohlížeče (extension/). Rozšíření každou sekundu POSTne stav
/// přehrávání (YouTube, YouTube Music, Spotify Web, SoundCloud…) a v odpovědi dostane příkazy (play/pause/next/prev).
final class BrowserMediaServer: @unchecked Sendable {
    static let shared = BrowserMediaServer()
    static let port: UInt16 = 47831
    struct State: Equatable { var playing: Bool; var title: String; var artist: String; var album: String; var artwork: String?; var site: String; var duration: Double; var position: Double; var updated: Date }
    private(set) var state: State?
    private var pendingCommands: [String] = []
    private let lock = NSLock()
    private var listener: NWListener?

    private init() {}

    func start() {
        do {
            let p = NWParameters.tcp
            p.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            let l = try NWListener(using: p)
            l.newConnectionHandler = { [weak self] c in self?.handle(c) }
            l.start(queue: DispatchQueue(label: "browser.media"))
            listener = l
            Log.w("browser media server on 127.0.0.1:\(Self.port)")
        } catch { Log.w("browser media server failed: \(error)") }
    }

    func send(_ cmd: String) { lock.lock(); pendingCommands.append(cmd); lock.unlock() }
    func current() -> State? { lock.lock(); defer { lock.unlock() }; if let s = state, Date().timeIntervalSince(s.updated) < 4 { return s }; return nil }

    private func handle(_ c: NWConnection) {
        c.start(queue: DispatchQueue(label: "browser.media.conn"))
        receive(c, buffer: Data())
    }
    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer; if let data { buf.append(data) }
            if let r = Self.parse(buf) { self.respond(c, r) } else if done || err != nil { c.cancel() } else { self.receive(c, buffer: buf) }
        }
    }
    private static func parse(_ d: Data) -> (method: String, path: String, body: Data)? {
        guard let hdrEnd = d.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: d[..<hdrEnd.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n"); let req = lines[0].split(separator: " ")
        guard req.count >= 2 else { return nil }
        let len = lines.compactMap { l -> Int? in let p = l.split(separator: ":", maxSplits: 1); return p.count == 2 && p[0].lowercased() == "content-length" ? Int(p[1].trimmingCharacters(in: .whitespaces)) : nil }.first ?? 0
        let body = d[hdrEnd.upperBound...]
        guard body.count >= len else { return nil }
        return (String(req[0]), String(req[1]), Data(body.prefix(len)))
    }
    private func respond(_ c: NWConnection, _ r: (method: String, path: String, body: Data)) {
        var status = "200 OK", payload = "{}"
        if r.method == "OPTIONS" { status = "204 No Content"; payload = "" }
        else if r.method == "POST", r.path.hasPrefix("/nowplaying"), let j = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any] {
            lock.lock()
            if (j["title"] as? String ?? "").isEmpty { state = nil } else {
                state = State(playing: j["playing"] as? Bool ?? false, title: j["title"] as? String ?? "", artist: j["artist"] as? String ?? "", album: j["album"] as? String ?? "",
                              artwork: j["artwork"] as? String, site: j["site"] as? String ?? "Web", duration: j["duration"] as? Double ?? 0, position: j["position"] as? Double ?? 0, updated: Date())
            }
            let cmds = pendingCommands; pendingCommands = []
            lock.unlock()
            payload = "{\"commands\":[\(cmds.map { "\"\($0)\"" }.joined(separator: ","))]}"
        } else if r.path.hasPrefix("/ping") { payload = "{\"app\":\"NotchIsland\"}" }
        else { status = "404 Not Found" }
        let resp = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: content-type\r\nAccess-Control-Allow-Methods: POST, GET, OPTIONS\r\nContent-Length: \(payload.utf8.count)\r\nConnection: close\r\n\r\n\(payload)"
        c.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in c.cancel() })
    }
}
