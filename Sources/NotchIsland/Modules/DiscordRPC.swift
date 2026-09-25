import Foundation
import Combine

struct DiscordVoiceUser: Identifiable, Equatable {
    let id: String
    let name: String
    let avatarURL: URL?
    let muted: Bool
    let deaf: Bool
    let speaking: Bool
}

/// Discord RPC přes lokální IPC socket. Vyžaduje vlastní aplikaci na discord.com/developers
/// (Client ID + Secret, redirect URI http://localhost). Umí: kdo je v hlasovém kanálu, mute/deafen.
@MainActor
final class DiscordRPC: ObservableObject {
    static let shared = DiscordRPC()
    @Published private(set) var connected = false
    @Published private(set) var authorized = false
    @Published private(set) var channelName: String?
    @Published private(set) var users: [DiscordVoiceUser] = []
    @Published private(set) var selfMuted = false
    @Published private(set) var selfDeaf = false
    @Published private(set) var status = L("Nepřipojeno")

    private final class Sock: @unchecked Sendable { var fd: Int32 = -1 }
    nonisolated private let sock = Sock()
    nonisolated private var fd: Int32 { get { sock.fd } set { sock.fd = newValue } }
    private let queue = DispatchQueue(label: "discord.ipc")
    private var timer: Timer?
    private var busy = false

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard !busy else { return }
        let s = AppSettings.shared
        guard !s.discordClientId.isEmpty else { status = L("Zadej Discord Client ID v Nastavení"); return }
        guard CallsService.shared.running.contains(where: { $0.name == "Discord" }) else { disconnect(); status = L("Discord neběží"); return }
        busy = true
        let clientId = s.discordClientId, secret = s.discordClientSecret, token = s.discordAccessToken
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.sync(clientId: clientId, secret: secret, token: token)
            Task { @MainActor in self.apply(result); self.busy = false }
        }
    }

    private struct Snapshot { var connected = false; var authorized = false; var status = ""; var channel: String?; var users: [DiscordVoiceUser] = []; var mute = false; var deaf = false; var newToken: String? }

    private func apply(_ r: Snapshot) {
        connected = r.connected; authorized = r.authorized; status = r.status; channelName = r.channel; users = r.users; selfMuted = r.mute; selfDeaf = r.deaf
        if let t = r.newToken { AppSettings.shared.discordAccessToken = t }
    }

    // MARK: IPC (běží na `queue`)
    nonisolated private func sync(clientId: String, secret: String, token: String) -> Snapshot {
        var snap = Snapshot()
        if fd < 0 {
            guard let f = Self.openSocket() else { snap.status = L("Discord IPC socket nenalezen"); return snap }
            fd = f
            guard let hs = send(op: 0, ["v": 1, "client_id": clientId]), (hs["evt"] as? String) == "READY" else {
                closeFd(); snap.status = L("Handshake s Discordem selhal (zkontroluj Client ID)"); return snap
            }
        }
        snap.connected = true
        var accessToken = token
        if accessToken.isEmpty {
            guard !secret.isEmpty else { snap.status = L("Zadej Discord Client Secret v Nastavení"); return snap }
            guard let a = command("AUTHORIZE", ["client_id": clientId, "scopes": ["rpc", "rpc.voice.read", "rpc.voice.write"]]),
                  let code = (a["data"] as? [String: Any])?["code"] as? String else { snap.status = L("Autorizace v Discordu zamítnuta"); return snap }
            guard let t = Self.exchange(code: code, clientId: clientId, secret: secret) else { snap.status = L("Výměna kódu za token selhala (redirect URI musí být http://localhost)"); return snap }
            accessToken = t; snap.newToken = t
        }
        guard let auth = command("AUTHENTICATE", ["access_token": accessToken]), auth["evt"] as? String != "ERROR" else {
            snap.status = L("Token neplatný – přihlašuji znovu"); snap.newToken = ""; closeFd(); return snap
        }
        snap.authorized = true
        if let vs = command("GET_VOICE_SETTINGS", [:])?["data"] as? [String: Any] {
            snap.mute = vs["mute"] as? Bool ?? false; snap.deaf = vs["deaf"] as? Bool ?? false
        }
        if let ch = command("GET_SELECTED_VOICE_CHANNEL", [:])?["data"] as? [String: Any] {
            snap.channel = ch["name"] as? String
            let states = ch["voice_states"] as? [[String: Any]] ?? []
            snap.users = states.compactMap { s in
                let u = s["user"] as? [String: Any] ?? [:]
                let v = s["voice_state"] as? [String: Any] ?? [:]
                guard let id = u["id"] as? String else { return nil }
                let name = (s["nick"] as? String) ?? (u["global_name"] as? String) ?? (u["username"] as? String) ?? "?"
                let avatar = (u["avatar"] as? String).map { URL(string: "https://cdn.discordapp.com/avatars/\(id)/\($0).png?size=64")! }
                return DiscordVoiceUser(id: id, name: name, avatarURL: avatar,
                                        muted: (v["mute"] as? Bool ?? false) || (v["self_mute"] as? Bool ?? false),
                                        deaf: (v["deaf"] as? Bool ?? false) || (v["self_deaf"] as? Bool ?? false), speaking: false)
            }
            snap.status = "V kanálu \(snap.channel ?? "")"
        } else { snap.status = L("Nejsi v hlasovém kanálu") }
        return snap
    }

    func toggleMute() { setVoice(["mute": !selfMuted]) }
    func toggleDeaf() { setVoice(["deaf": !selfDeaf]) }
    private func setVoice(_ args: [String: Any]) {
        queue.async { [weak self] in _ = self?.command("SET_VOICE_SETTINGS", args) }
    }

    nonisolated private func command(_ cmd: String, _ args: [String: Any]) -> [String: Any]? {
        let nonce = UUID().uuidString
        var r = send(op: 1, ["cmd": cmd, "args": args, "nonce": nonce])
        var tries = 0
        while let x = r, (x["nonce"] as? String) != nonce, tries < 10 { r = readFrame(); tries += 1 } // přeskoč eventy
        return r
    }

    nonisolated private func send(op: Int32, _ payload: [String: Any]) -> [String: Any]? {
        guard fd >= 0, let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var header = Data()
        var o = op.littleEndian, l = Int32(body.count).littleEndian
        header.append(Data(bytes: &o, count: 4)); header.append(Data(bytes: &l, count: 4))
        let out = header + body
        let n = out.withUnsafeBytes { write(fd, $0.baseAddress, out.count) }
        guard n == out.count else { closeFd(); return nil }
        return readFrame()
    }

    nonisolated private func readFrame() -> [String: Any]? {
        guard fd >= 0 else { return nil }
        var hdr = [UInt8](repeating: 0, count: 8)
        guard readFully(&hdr, 8) else { closeFd(); return nil }
        let len = Int(UInt32(hdr[4]) | UInt32(hdr[5]) << 8 | UInt32(hdr[6]) << 16 | UInt32(hdr[7]) << 24)
        var body = [UInt8](repeating: 0, count: len)
        guard readFully(&body, len) else { closeFd(); return nil }
        return (try? JSONSerialization.jsonObject(with: Data(body))) as? [String: Any]
    }

    nonisolated private func readFully(_ buf: inout [UInt8], _ n: Int) -> Bool {
        var got = 0
        while got < n {
            let r = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress! + got, n - got) }
            if r <= 0 { return false }
            got += r
        }
        return true
    }

    nonisolated private func closeFd() { if fd >= 0 { close(fd) }; fd = -1 }
    private func disconnect() { queue.async { [weak self] in self?.closeFd() }; connected = false; authorized = false; users = []; channelName = nil }

    nonisolated private static func openSocket() -> Int32? {
        let tmp = NSTemporaryDirectory()
        for i in 0..<10 {
            let path = tmp + "discord-ipc-\(i)"
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let s = socket(AF_UNIX, SOCK_STREAM, 0); guard s >= 0 else { continue }
            var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
            _ = withUnsafeMutablePointer(to: &addr.sun_path) { p in
                p.withMemoryRebound(to: CChar.self, capacity: 104) { strncpy($0, path, 103) }
            }
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            if ok == 0 { return s }
            close(s)
        }
        return nil
    }

    nonisolated private static func exchange(code: String, clientId: String, secret: String) -> String? {
        var r = URLRequest(url: URL(string: "https://discord.com/api/oauth2/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = ["client_id": clientId, "client_secret": secret, "grant_type": "authorization_code", "code": code, "redirect_uri": "http://localhost"]
        r.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }.joined(separator: "&").data(using: .utf8)
        let sem = DispatchSemaphore(value: 0)
        var token: String?
        URLSession.shared.dataTask(with: r) { data, _, _ in
            if let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { token = j["access_token"] as? String }
            sem.signal()
        }.resume()
        sem.wait()
        return token
    }
}
