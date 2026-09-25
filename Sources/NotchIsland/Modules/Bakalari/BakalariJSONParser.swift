import Foundation

/// Nové Bakaláři (2026) vykreslují rozvrh v prohlížeči; data jsou v HTML jako `const timetableData = {...}`.
enum BakalariJSONParser {
    struct Result { let lessons: [RemoteLesson]; let hours: [HourRef]; let weekStart: Date? }

    static func extract(html: String) -> [String: Any]? {
        guard let r = html.range(of: "const timetableData = ") else { return nil }
        let start = r.upperBound
        var depth = 0, i = start, inStr = false, esc = false
        var end: String.Index?
        while i < html.endIndex {
            let c = html[i]
            if inStr { if esc { esc = false } else if c == "\\" { esc = true } else if c == "\"" { inStr = false } }
            else if c == "\"" { inStr = true }
            else if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { end = html.index(after: i); break } }
            i = html.index(after: i)
        }
        guard let end, let data = html[start..<end].data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func parse(html: String) -> Result? {
        guard let root = extract(html: html), let days = root["Days"] as? [[String: Any]] else { return nil }
        var lessons: [RemoteLesson] = []
        var hours: [Int: HourRef] = [:]
        var weekStart: Date?
        let df = DateFormatter(); df.dateFormat = "d.M.yyyy"; df.timeZone = TimeZone(identifier: "Europe/Prague")
        func hm(_ s: String?) -> String { guard let s else { return "" }; let p = s.split(separator: ":"); return p.count >= 2 ? "\(Int(p[0]) ?? 0):\(p[1])" : s }
        for (dayIndex, day) in days.enumerated() {
            if dayIndex == 0, let ds = day["Date"] as? String {
                var t = ds.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
                if t.hasSuffix(".") { t += "\(Calendar.current.component(.year, from: Date()))" }   // "21.9." → doplnit rok
                weekStart = df.date(from: t)
            }
            for hour in day["Hours"] as? [[String: Any]] ?? [] {
                guard let idx = hour["Index"] as? Int else { continue }
                if hours[idx] == nil { hours[idx] = HourRef(Id: idx, Caption: "\(idx)", BeginTime: hm(hour["Begin"] as? String), EndTime: hm(hour["End"] as? String)) }
                let hourType = (hour["Type"] as? String ?? "").lowercased()
                let infoRemoved = hour["InfoRemoved"] as? String
                let atoms = hour["Atoms"] as? [[String: Any]] ?? []
                if atoms.isEmpty, let removed = infoRemoved, !removed.isEmpty {
                    lessons.append(RemoteLesson(day: dayIndex, hour: idx, subject: removed, subjectAbbreviation: nil, type: "removed",
                                                changed: true, changeInfo: .init(raw: removed, description: removed)))
                    continue
                }
                if atoms.isEmpty, hourType == "absent" || hour["InfoAbsent"] != nil {
                    let name = hour["InfoAbsentName"] as? String ?? hour["InfoAbsent"] as? String ?? "Absence"
                    lessons.append(RemoteLesson(day: dayIndex, hour: idx, subject: name, type: "absent", changed: true, changeInfo: .init(raw: name, description: name)))
                    continue
                }
                for a in atoms {
                    let change = a["ChangeInfo"] as? String ?? ""
                    let code = (a["InfoChangeCode"] as? Int) ?? 0   // 2 = beze změny, 1 = suplování/změna
                    let atomType = (a["Type"] as? String ?? "atom").lowercased()
                    var type = "atom"
                    if atomType.contains("removed") || (a["ChangeType"] as? Int) == 4 && !change.isEmpty && change.lowercased().contains("zruš") { type = "removed" }
                    else if (a["HasAbsent"] as? Bool) == true { type = "absent" }
                    else if (a["NewAtom"] as? Bool) == true { type = "added" }
                    let changed = (a["HasChanged"] as? Bool ?? false) || (!change.isEmpty && code != 2)
                    lessons.append(RemoteLesson(day: dayIndex, hour: idx, subject: a["SubjectText"] as? String ?? "", subjectAbbreviation: a["SubjectAbbrev"] as? String,
                                                teacher: a["Teacher"] as? String ?? (a["TeacherFullname"] as? String), room: a["Room"] as? String,
                                                group: a["GroupsNames"] as? String, theme: a["Theme"] as? String, type: type, changed: changed,
                                                changeInfo: change.isEmpty ? nil : .init(raw: change, description: change),
                                                teacherFull: a["TeacherFullname"] as? String, roomFull: a["RoomFullName"] as? String,
                                                notice: a["Notice"] as? String, groupFull: a["GroupsFullNames"] as? String))
                }
            }
        }
        return Result(lessons: lessons, hours: hours.keys.sorted().map { hours[$0]! }, weekStart: weekStart)
    }
}
