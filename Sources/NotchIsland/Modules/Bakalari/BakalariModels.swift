import Foundation

// Modely převzaté z projektu BakalariRozvrhy (Adam Brož).
struct HourRef: Codable, Hashable { let Id: Int; let Caption: String; let BeginTime: String; let EndTime: String }
struct DefinitionEntity: Codable, Hashable, Identifiable { let id: String; let name: String }

struct RemoteLesson: Codable {
    let day: Int; let dayName: String?; let hour: Int
    let subject: String?; let subjectAbbreviation: String?; let teacher: String?; let room: String?
    let group: String?; let theme: String?; let type: String?; let changed: Bool?; let changeInfo: ChangeInfo?
    struct ChangeInfo: Codable { let raw: String?; let description: String? }
    init(day: Int, dayName: String? = nil, hour: Int, subject: String? = nil, subjectAbbreviation: String? = nil, teacher: String? = nil,
         room: String? = nil, group: String? = nil, theme: String? = nil, type: String? = nil, changed: Bool? = nil, changeInfo: ChangeInfo? = nil) {
        self.day = day; self.dayName = dayName; self.hour = hour; self.subject = subject; self.subjectAbbreviation = subjectAbbreviation
        self.teacher = teacher; self.room = room; self.group = group; self.theme = theme; self.type = type; self.changed = changed; self.changeInfo = changeInfo
    }
}

enum LessonState: String, Codable { case normal, changed, removed, added, absent }

struct Lesson: Codable, Hashable, Identifiable {
    var id: String { "\(dayIndex)-\(hourId)-\(subjectAbbrev)-\(groupAbbrev ?? "")-\(state.rawValue)" }
    let dayIndex: Int; let hourId: Int
    let subjectAbbrev: String; let subjectName: String
    let teacherAbbrev: String?; let roomAbbrev: String?; let groupAbbrev: String?
    let state: LessonState; let changeDescription: String?
    var isCancelled: Bool { state == .removed || state == .absent }
    var isChanged: Bool { state == .changed || state == .added }
}

enum SchoolHours {
    static let table: [Int: (String, String)] = [
        0: ("7:10", "7:55"), 1: ("8:00", "8:45"), 2: ("8:50", "9:35"), 3: ("9:45", "10:30"), 4: ("10:50", "11:35"), 5: ("11:40", "12:25"),
        6: ("12:35", "13:20"), 7: ("13:25", "14:10"), 8: ("14:20", "15:05"), 9: ("15:10", "15:55"), 10: ("16:00", "16:45"), 11: ("16:50", "17:35"), 12: ("17:40", "18:25"),
    ]
    static func hourRef(_ id: Int) -> HourRef { let (b, e) = table[id] ?? ("", ""); return HourRef(Id: id, Caption: "\(id)", BeginTime: b, EndTime: e) }
}

/// Zpracovaný týdenní rozvrh: hodiny + lekce podle (den, hodina).
struct Timetable: Codable {
    let weekStart: Date
    let hours: [HourRef]
    let lessonsByCell: [String: [Lesson]]
    let fetchedAt: Date
    func lessons(day: Int, hourId: Int) -> [Lesson] { lessonsByCell["\(day)-\(hourId)"] ?? [] }

    static func build(_ lessons: [RemoteLesson], hours: [HourRef], weekStart: Date? = nil) -> Timetable {
        var cal = Calendar(identifier: .iso8601); cal.firstWeekday = 2; cal.timeZone = TimeZone(identifier: "Europe/Prague") ?? .current
        let today = cal.startOfDay(for: Date())
        let monday = weekStart.map { cal.startOfDay(for: $0) } ?? (cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today)
        var byCell: [String: [Lesson]] = [:]
        var minH = Int.max, maxH = 0
        for r in lessons {
            let d = max(0, min(4, r.day)); minH = min(minH, r.hour); maxH = max(maxH, r.hour)
            let (ab, name) = splitSubject(r.subject ?? "", r.subjectAbbreviation)
            byCell["\(d)-\(r.hour)", default: []].append(Lesson(dayIndex: d, hourId: r.hour, subjectAbbrev: ab, subjectName: name,
                teacherAbbrev: cleanTeacher(r.teacher), roomAbbrev: r.room, groupAbbrev: normalizeGroup(r.group), state: state(r),
                changeDescription: r.changeInfo?.description ?? r.changeInfo?.raw))
        }
        if minH == .max { minH = 1 }; if maxH == 0 { maxH = 7 }
        let hs = hours.isEmpty ? (min(minH, 1)...maxH).map { SchoolHours.hourRef($0) } : hours.filter { $0.Id >= min(minH, 1) && $0.Id <= maxH }
        return Timetable(weekStart: monday, hours: hs, lessonsByCell: byCell, fetchedAt: Date())
    }
    private static func state(_ r: RemoteLesson) -> LessonState {
        let t = (r.type ?? "").lowercased()
        if t.contains("removed") { return .removed }; if t.contains("absent") { return .absent }; if t.contains("added") { return .added }
        return r.changed == true ? .changed : .normal
    }
    private static func splitSubject(_ name: String, _ abbrev: String?) -> (String, String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        if let a = abbrev?.trimmingCharacters(in: .whitespaces), !a.isEmpty { return (a, n) }
        guard !n.isEmpty else { return ("—", "") }
        let w = n.split(separator: " ")
        return (w.count >= 2 ? w.prefix(3).compactMap { $0.first }.map { String($0).uppercased() }.joined() : String(n.prefix(3)).uppercased(), n)
    }
    private static func cleanTeacher(_ t: String?) -> String? {
        guard var c = t?.trimmingCharacters(in: .whitespaces), !c.isEmpty else { return nil }
        for title in ["Mgr.", "Ing.", "Bc.", "PaedDr.", "Mgr.A.", "Mgr.Bc."] where c.hasPrefix(title) { c = String(c.dropFirst(title.count)).trimmingCharacters(in: .whitespaces) }
        return c
    }
    private static func normalizeGroup(_ raw: String?) -> String? {
        guard let g = raw?.trimmingCharacters(in: .whitespaces), !g.isEmpty else { return nil }
        if g.lowercased().contains("celá") { return nil }
        if let m = g.range(of: #"^(\d+)[\.\s]*(?:skupina|sk)?$"#, options: .regularExpression) { return "\(g[m].prefix(while: { $0.isNumber })).sk" }
        if let m = g.range(of: #"^sk\s*(\d+)$"#, options: [.regularExpression, .caseInsensitive]) { return "\(g[m].filter { $0.isNumber }).sk" }
        return g
    }
}
