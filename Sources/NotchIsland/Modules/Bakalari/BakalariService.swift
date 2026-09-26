import Foundation
import Combine
import Security
import UserNotifications

/// Rozvrh z Bakalářů: přihlášení cookie session (jako v BakalariRozvrhy), scrape veřejného rozvrhu třídy, obnova každých 30 min.
@MainActor
final class BakalariService: ObservableObject {
    static let shared = BakalariService()
    @Published private(set) var timetable: Timetable?          // aktuální týden
    @Published private(set) var nextTimetable: Timetable?      // příští týden
    @Published private(set) var permanentTimetable: Timetable? // stálý (pro ostatní týdny)
    @Published private(set) var status = ""
    @Published private(set) var loading = false
    @Published private(set) var classes: [DefinitionEntity] = []
    @Published private(set) var loginOK = false
    /// Aktuální školní stav (přepočítává se každých 15 s).
    @Published private(set) var school: SchoolState = .none
    enum SchoolState: Equatable {
        case none
        case lesson(TodayLesson, endsIn: TimeInterval)
        case breakTime(next: TodayLesson, startsIn: TimeInterval, length: TimeInterval)
        case beforeSchool(first: TodayLesson, startsIn: TimeInterval)
        case done
    }
    private var stateTimer: Timer?
    private var notifiedKey = ""
    private var timer: Timer?
    private let session: URLSession
    private var loggedIn = false

    private init() {
        let c = URLSessionConfiguration.default
        c.httpCookieAcceptPolicy = .always; c.httpShouldSetCookies = true; c.timeoutIntervalForRequest = 25
        session = URLSession(configuration: c)
        if let d = try? Data(contentsOf: cacheURL), let t = try? JSONDecoder().decode(Timetable.self, from: d) { timetable = t }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in Task { await self?.refresh() } }
        stateTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.updateState() }
        Task { await refresh(); updateState() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Po zadání serveru + jména + hesla: přihlásí se a stáhne seznam tříd.
    func loadClasses() async {
        let s = AppSettings.shared
        loading = true; defer { loading = false }
        do {
            try await login(server: s.bakalariServer, user: s.bakalariUser, password: Keychain.read("bakalariPassword"))
            guard let base = URL(string: s.bakalariServer) else { return }
            var r = URLRequest(url: base.appendingPathComponent("Timetable/Public")); r.setValue("Mozilla/5.0 (NotchIsland)", forHTTPHeaderField: "User-Agent")
            let (d, _) = try await session.data(for: r)
            let list = try BakalariHTMLParser.parseClasses(html: String(data: d, encoding: .utf8) ?? "")
            classes = list; loginOK = true
            status = list.isEmpty ? L("Přihlášeno, ale seznam tříd je prázdný") : ""
            if s.bakalariClass.isEmpty, let f = list.first { s.bakalariClass = f.id }
            timetable = nil
            await refresh(force: true)
        } catch { status = error.localizedDescription; loginOK = false }
    }

    struct TodayLessonKey: Equatable { let id: String }

    /// Přepočet stavu: hodina / přestávka / před školou / po škole + oznámení při začátku přestávky.
    private func updateState() {
        guard isConfigured else { school = .none; return }
        let list = lessons().filter { !$0.lesson.isCancelled }
        let now = Date()
        var new: SchoolState = .none
        if list.isEmpty { new = .none }
        else if let cur = list.first(where: { $0.start <= now && $0.end > now }) { new = .lesson(cur, endsIn: cur.end.timeIntervalSince(now)) }
        else if let next = list.first(where: { $0.start > now }) {
            if let prev = list.last(where: { $0.end <= now }) { new = .breakTime(next: next, startsIn: next.start.timeIntervalSince(now), length: next.start.timeIntervalSince(prev.end)) }
            else { new = .beforeSchool(first: next, startsIn: next.start.timeIntervalSince(now)) }
        } else { new = .done }
        school = new
        // oznámení: začátek přestávky / poslední hodina skončila
        let key: String
        switch new {
        case .breakTime(let next, _, let len): key = "break-\(next.id)"
            if key != notifiedKey { notify(String(format: L("Přestávka %d min"), Int(len / 60)), String(format: L("Další: %@ v %@, učebna %@"), next.lesson.subjectName.isEmpty ? next.lesson.subjectAbbrev : next.lesson.subjectName, next.hour.BeginTime, next.lesson.roomAbbrev ?? "–")) }
        case .done: key = "done-\(Calendar.current.startOfDay(for: now))"
            if key != notifiedKey { notify(L("Konec vyučování"), L("Dnes už žádná hodina není.")) }
        case .lesson(let l, _): key = "lesson-\(l.id)"
        default: key = ""
        }
        notifiedKey = key
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
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
            var html = try await fetchHTML(server: s.bakalariServer, classId: s.bakalariClass, kind: "Actual")
            if html.contains("id=\"formlogin\"") {   // session vypršela
                try await login(server: s.bakalariServer, user: s.bakalariUser, password: Keychain.read("bakalariPassword"))
                html = try await fetchHTML(server: s.bakalariServer, classId: s.bakalariClass, kind: "Actual")
            }
            let t = parse(html)
            timetable = t; status = t.lessonsByCell.isEmpty ? L("Rozvrh je prázdný (zkontroluj třídu)") : ""
            updateState()
            if let d = try? JSONEncoder().encode(t) { try? d.write(to: cacheURL) }
            // příští týden a stálý rozvrh (pro listování dopředu / dozadu)
            if let h = try? await fetchHTML(server: s.bakalariServer, classId: s.bakalariClass, kind: "Next") {
                var n = parse(h)
                if n.weekStart == t.weekStart, let ws = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: t.weekStart) { n = Timetable(weekStart: ws, hours: n.hours, lessonsByCell: n.lessonsByCell, fetchedAt: n.fetchedAt) }
                nextTimetable = n
            }
            if let h = try? await fetchHTML(server: s.bakalariServer, classId: s.bakalariClass, kind: "Permanent") { permanentTimetable = parse(h) }
        } catch { status = error.localizedDescription; loggedIn = false; Log.w("bakalari: \(error)") }
    }

    private func parse(_ html: String) -> Timetable {
        if let j = BakalariJSONParser.parse(html: html) { return Timetable.build(j.lessons, hours: j.hours, weekStart: j.weekStart) }
        if let p = try? BakalariHTMLParser.parseClassTimetable(html: html) { return Timetable.build(p.lessons, hours: p.hours) }
        return Timetable.build([], hours: [])
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

    private func fetchHTML(server: String, classId: String, kind: String = "Actual") async throws -> String {
        guard let base = URL(string: server) else { throw URLError(.badURL) }
        let enc = classId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? classId
        var r = URLRequest(url: base.appendingPathComponent("Timetable/Public/\(kind)/Class/\(enc)"))
        r.setValue("Mozilla/5.0 (NotchIsland)", forHTTPHeaderField: "User-Agent")
        let (d, _) = try await session.data(for: r)
        return String(data: d, encoding: .utf8) ?? ""
    }

    /// Všechny vyučovací hodiny 0–12 (časy z Bakalářů, jinak ze zvonění školy).
    var allHours: [HourRef] {
        let known = Dictionary(uniqueKeysWithValues: (timetable?.hours ?? []).map { ($0.Id, $0) })
        return (0...12).map { known[$0] ?? SchoolHours.hourRef($0) }
    }

    // MARK: dnešek
    struct TodayLesson: Identifiable, Equatable { let id: String; let hour: HourRef; let lesson: Lesson; let start: Date; let end: Date }

    private func time(_ hhmm: String, on day: Date) -> Date? {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }; guard p.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: day)
    }

    /// Rozvrh pro daný den: aktuální týden, příští týden, jinak stálý rozvrh.
    func timetable(for day: Date) -> Timetable? {
        let cal = Calendar.current
        if let t = timetable, cal.isDate(day, equalTo: t.weekStart, toGranularity: .weekOfYear) { return t }
        if let n = nextTimetable, cal.isDate(day, equalTo: n.weekStart, toGranularity: .weekOfYear) { return n }
        return permanentTimetable ?? timetable
    }

    func lessons(on day: Date = Date()) -> [TodayLesson] {
        guard let t = timetable(for: day) else { return [] }
        let cal = Calendar.current
        let weekday = (cal.component(.weekday, from: day) + 5) % 7   // po=0
        guard weekday < 5 else { return [] }
        let g = AppSettings.shared.bakalariGroup
        return t.hours.flatMap { h -> [TodayLesson] in
            t.lessons(day: weekday, hourId: h.Id).filter { l in
                guard g != 0, let grp = l.groupAbbrev, let d = grp.first(where: { $0.isNumber }), let n = Int(String(d)) else { return true }
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
