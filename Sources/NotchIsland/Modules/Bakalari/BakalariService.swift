import Foundation
import Combine
import Security

/// Rozvrh z Bakalářů: přihlášení cookie session (jako v BakalariRozvrhy), scrape veřejného rozvrhu třídy, obnova každých 30 min.
@MainActor
final class BakalariService: ObservableObject {
    static let shared = BakalariService()
    @Published private(set) var timetable: Timetable?
    @Published private(set) var status = ""
    @Published private(set) var loading = false
    private var timer: Timer?
    private let session: URLSession
    private var loggedIn = false

    private init() {
        let c = URLSessionConfiguration.default
        c.httpCookieAcceptPolicy = .always; c.httpShouldSetCookies = true; c.timeoutIntervalForRequest = 25
        session = URLSession(configuration: c)
        if let d = try? Data(contentsOf: cacheURL), let t = try? JSONDecoder().decode(Timetable.self, from: d) { timetable = t }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in Task { await self?.refresh() } }
        Task { await refresh() }
    }

    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NotchIsland/bakalari.json")
    }
    var isConfigured: Bool { let s = AppSettings.shared; return !s.bakalariUser.isEmpty && !s.bakalariClass.isEmpty && !Keychain.read("bakalariPassword").isEmpty }

    func refresh(force: Bool = false) async {
        guard isConfigured else { status = L("Vyplň Bakaláře v Nastavení"); return }
        if !force, let t = timetable, Date().timeIntervalSince(t.fetchedAt) < 600 { return }
        loading = true; defer { loading = false }
        let s = AppSettings.shared
        do {
            if !loggedIn { try await login(server: s.bakalariServer, user: s.bakalariUser, password: Keychain.read("bakalariPassword")) }
            var html = try await fetchHTML(server: s.bakalariServer, classId: s.bakalariClass)
            if html.contains("id=\"formlogin\"") {   // session vypršela
                try await login(server: s.bakalariServer, user: s.bakalariUser, password: Keychain.read("bakalariPassword"))
                html = try await fetchHTML(server: s.bakalariServer, classId: s.bakalariClass)
            }
            let parsed = try BakalariHTMLParser.parseClassTimetable(html: html)
            let t = Timetable.build(parsed.lessons, hours: parsed.hours)
            timetable = t; status = parsed.lessons.isEmpty ? L("Rozvrh je prázdný (zkontroluj třídu)") : ""
            if let d = try? JSONEncoder().encode(t) { try? d.write(to: cacheURL) }
        } catch { status = error.localizedDescription; loggedIn = false; Log.w("bakalari: \(error)") }
    }

    private func login(server: String, user: String, password: String) async throws {
        guard let base = URL(string: server) else { throw NSError(domain: "bk", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Neplatná adresa Bakalářů")]) }
        _ = try? await session.data(from: base.appendingPathComponent("login"))
        var r = URLRequest(url: base.appendingPathComponent("Login")); r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("Mozilla/5.0 (NotchIsland)", forHTTPHeaderField: "User-Agent")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
        r.httpBody = "username=\(enc(user))&password=\(enc(password))&persistent=true&returnUrl=%2FTimetable%2FPublic".data(using: .utf8)
        let (d, _) = try await session.data(for: r)
        let html = String(data: d, encoding: .utf8) ?? ""
        if html.contains("id=\"formlogin\"") || html.contains("name=\"password\"") { throw NSError(domain: "bk", code: 2, userInfo: [NSLocalizedDescriptionKey: L("Přihlášení do Bakalářů selhalo (jméno/heslo)")]) }
        loggedIn = true
    }

    private func fetchHTML(server: String, classId: String) async throws -> String {
        guard let base = URL(string: server) else { throw URLError(.badURL) }
        let enc = classId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? classId
        var r = URLRequest(url: base.appendingPathComponent("Timetable/Public/Actual/Class/\(enc)"))
        r.setValue("Mozilla/5.0 (NotchIsland)", forHTTPHeaderField: "User-Agent")
        let (d, _) = try await session.data(for: r)
        return String(data: d, encoding: .utf8) ?? ""
    }

    // MARK: dnešek
    struct TodayLesson: Identifiable { let id: String; let hour: HourRef; let lesson: Lesson; let start: Date; let end: Date }

    private func time(_ hhmm: String, on day: Date) -> Date? {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }; guard p.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: day)
    }

    func lessons(on day: Date = Date()) -> [TodayLesson] {
        guard let t = timetable else { return [] }
        let cal = Calendar.current
        let weekday = (cal.component(.weekday, from: day) + 5) % 7   // po=0
        guard weekday < 5 else { return [] }
        // rozvrh platí jen pro stažený týden
        guard cal.isDate(day, equalTo: t.weekStart, toGranularity: .weekOfYear) else { return [] }
        let g = AppSettings.shared.bakalariGroup
        return t.hours.flatMap { h -> [TodayLesson] in
            t.lessons(day: weekday, hourId: h.Id).filter { l in
                guard g != 0, let grp = l.groupAbbrev, let d = grp.first, d.isNumber, let n = Int(String(d)) else { return true }
                return n == g
            }.compactMap { l in
                guard let s = time(h.BeginTime, on: day), let e = time(h.EndTime, on: day) else { return nil }
                return TodayLesson(id: l.id + h.Caption, hour: h, lesson: l, start: s, end: e)
            }
        }
    }

    /// Aktuální / další hodina (pro domovskou obrazovku).
    func current() -> (now: TodayLesson?, next: TodayLesson?) {
        let list = lessons().filter { !$0.lesson.isCancelled }
        let now = Date()
        return (list.first { $0.start <= now && $0.end > now }, list.first { $0.start > now })
    }
}

/// Minimální Keychain wrapper pro heslo.
enum Keychain {
    static func save(_ value: String, _ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "cz.adambroz.notchisland", kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var a = q; a[kSecValueData as String] = value.data(using: .utf8)!
        SecItemAdd(a as CFDictionary, nil)
    }
    static func read(_ key: String) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "cz.adambroz.notchisland", kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }
}
