import Foundation
import SwiftSoup

/// Port of `routes/timetable.js` parsing from hatcyk/hezci_rozvrhy: iterates `.bk-timetable-row`,
/// then `.bk-timetable-cell`, then `.day-item-hover` and decodes the `data-detail` JSON for
/// every atom. The returned `[RemoteLesson]` matches the shape the original Vercel API uses.
enum BakalariHTMLParser {

    private struct DayItemDetail: Codable {
        var type: String?
        var subjecttext: String?
        var teacher: String?
        var room: String?
        var group: String?
        var theme: String?
        var changeinfo: String?
        var removedinfo: String?
        var absentinfo: String?
        var InfoAbsentName: String?
        var notice: String?
    }

    struct ParsedTimetable {
        let lessons: [RemoteLesson]
        /// Hour ids + times pulled straight from the Bakaláři header (`.bk-hour-wrapper`),
        /// so the widget shows the school's actual times instead of our guess table.
        let hours: [HourRef]
    }

    static func parseClassTimetable(html: String) throws -> ParsedTimetable {
        let doc = try SwiftSoup.parse(html)
        let dayKeys = ["po", "út", "st", "čt", "pá"]
        var result: [RemoteLesson] = []
        let hourRefs = parseHourHeader(doc: doc)

        let rows = try doc.select(".bk-timetable-row")
        for row in rows.array() {
            let dayName = (try? row.select(".bk-day-day").first()?.text()) ?? ""
            let dayKey = dayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let dayIndex = dayKeys.firstIndex(of: dayKey) ?? -1
            guard dayIndex >= 0 else { continue }

            let cells = try row.select(".bk-timetable-cell")
            for (cellIndex, cell) in cells.array().enumerated() {
                let items = try cell.select(".day-item-hover")
                for item in items.array() {
                    guard let raw = try? item.attr("data-detail"), !raw.isEmpty,
                          let data = raw.data(using: .utf8) else { continue }
                    let detail = (try? JSONDecoder().decode(DayItemDetail.self, from: data)) ?? DayItemDetail()

                    var subject = ""
                    var subjectAbbrev: String? = nil
                    var teacher = detail.teacher ?? ""
                    var changeInfo: RemoteLesson.ChangeInfo? = nil
                    if let raw = detail.changeinfo, !raw.isEmpty {
                        changeInfo = RemoteLesson.ChangeInfo(raw: raw, description: raw)
                    }

                    // Real abbreviation lives in the rendered cell content — Bakaláři's
                    // `<div class="middle">` shows the same short code the user sees on the web
                    // (e.g. "EKF", "ČJL"). This is more reliable than guessing from
                    // `subjecttext`, whose split structure varies between deployments.
                    if let middleText = try? item.select(".middle").first()?.text(),
                       !middleText.isEmpty {
                        subjectAbbrev = middleText.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    let subjectParts: [String] = (detail.subjecttext ?? "")
                        .split(separator: "|")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    let fullName: String = subjectParts.first ?? ""
                    // Fallback: if we didn't get an abbrev from .middle, try subjecttext[1].
                    if subjectAbbrev == nil, subjectParts.count >= 2, !subjectParts[1].isEmpty {
                        subjectAbbrev = subjectParts[1]
                    }

                    let lowerType = (detail.type ?? "").lowercased()
                    if lowerType == "removed", let removed = detail.removedinfo {
                        // Parse "Vyjmuto z rozvrhu (PŘEDMĚT, UČITEL)" / "Zrušeno (PŘEDMĚT, UČITEL)"
                        if let match = removed.range(of: #"\(([^,]+),\s*([^)]+)\)"#, options: .regularExpression) {
                            let inside = removed[match]
                            let inner = inside.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                            let parts = inner.split(separator: ",", maxSplits: 1).map {
                                $0.trimmingCharacters(in: .whitespaces)
                            }
                            if parts.count == 2 {
                                subject = String(parts[0])
                                teacher = abbreviateTeacher(String(parts[1]))
                            }
                        }
                        if subject.isEmpty {
                            subject = fullName
                            if teacher.isEmpty { teacher = detail.teacher ?? "" }
                        }
                        changeInfo = RemoteLesson.ChangeInfo(raw: removed, description: removed)
                    } else if lowerType == "absent", let name = detail.InfoAbsentName {
                        subject = capitalizeFirst(name)
                        let info: String
                        if let absentinfo = detail.absentinfo, !absentinfo.isEmpty {
                            info = "\(name) (\(absentinfo))"
                        } else {
                            info = name
                        }
                        changeInfo = RemoteLesson.ChangeInfo(raw: detail.absentinfo ?? "Absence", description: info)
                    } else {
                        subject = fullName
                    }

                    let lesson = RemoteLesson(
                        day: dayIndex,
                        dayName: dayName,
                        hour: cellIndex,
                        subject: subject,
                        subjectAbbreviation: subjectAbbrev,
                        teacher: teacher,
                        room: detail.room,
                        group: detail.group,
                        theme: detail.theme,
                        type: detail.type,
                        changed: changeInfo != nil,
                        changeInfo: changeInfo
                    )
                    result.append(lesson)
                }
            }
        }
        return ParsedTimetable(lessons: result, hours: hourRefs)
    }

    /// Read `.bk-hour-wrapper` (or `.bk-hour`) elements from the header row.
    /// Each cell holds the hour number + start time (`.from`) + end time (`.to`).
    private static func parseHourHeader(doc: Document) -> [HourRef] {
        guard let hourEls = try? doc.select(".bk-hour-wrapper, .bk-hour") else { return [] }
        var refs: [HourRef] = []
        for (idx, el) in hourEls.array().enumerated() {
            let numText = ((try? el.select(".num").first()?.text())
                ?? (try? el.select(".bk-hour-num").first()?.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let from = ((try? el.select(".from").first()?.text())
                ?? (try? el.select(".bk-hour-from").first()?.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let to = ((try? el.select(".to").first()?.text())
                ?? (try? el.select(".bk-hour-to").first()?.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let id = Int(numText) ?? idx
            refs.append(HourRef(Id: id, Caption: numText.isEmpty ? "\(id)" : numText, BeginTime: from, EndTime: to))
        }
        return refs
    }

    /// Parse the class dropdown — `<select id="selectedClass">` — into `(id, name)` pairs.
    /// Matches Štefan's fallback in `/api/definitions`.
    static func parseClasses(html: String) throws -> [DefinitionEntity] {
        let doc = try SwiftSoup.parse(html)
        guard let select = try? doc.select("#selectedClass option").array() else { return [] }
        return select.compactMap { el in
            guard let id = try? el.attr("value"), !id.isEmpty,
                  let name = try? el.text(), !name.isEmpty else { return nil }
            return DefinitionEntity(id: id, name: name)
        }
    }

    // MARK: - Helpers (mirroring Štefan's JS helpers)

    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }

    /// Port of `abbreviateTeacherName` from `routes/timetable.js`: strips titles, detects whether
    /// the name is "Surname Firstname" (typical Czech) and outputs "F. Surname".
    private static func abbreviateTeacher(_ fullName: String) -> String {
        var cleaned = fullName
        let titlePattern = #"^(?:Mgr\.|Ing\.|Bc\.|Dr\.|Ph\.D\.|RNDr\.|PaedDr\.|MBA)\s+"#
        while let range = cleaned.range(of: titlePattern, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        cleaned = cleaned.replacingOccurrences(of: #",?\s*(?:Ph\.D\.|CSc\.|MBA)$"#,
                                               with: "",
                                               options: [.regularExpression, .caseInsensitive])
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        let parts = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        if parts.isEmpty { return "" }
        if parts.count == 1 { return parts[0].prefix(2).uppercased() }

        let firstLower = parts[0].lowercased()
        let surnameSuffixes = ["ová", "ný", "ná", "ský", "ská", "ík", "ek", "ák", "vič", "ovič"]
        let reversed = surnameSuffixes.contains { firstLower.hasSuffix($0) }

        let firstName: String
        let lastName: String
        if reversed {
            lastName = parts[0]
            firstName = parts[parts.count - 1]
        } else {
            firstName = parts[0]
            lastName = parts[parts.count - 1]
        }
        guard let initial = firstName.first else { return cleaned }
        return "\(initial). \(lastName)"
    }
}
