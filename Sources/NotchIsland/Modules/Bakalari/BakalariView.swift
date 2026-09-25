import SwiftUI

struct BakalariView: View {
    @ObservedObject var b = BakalariService.shared
    @State private var day = Date()
    @AppStorage("bakalariWeekView") private var week = false
    var body: some View {
        let list = b.lessons(on: day)
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Picker("", selection: $week) { Text(L("Dnes")).tag(false); Text(L("Týden")).tag(true) }.pickerStyle(.segmented).controlSize(.mini).frame(width: 110)
                Button { day = Calendar.current.date(byAdding: .day, value: -1, to: day)! } label: { Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold)) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
                Text(day, format: .dateTime.weekday(.wide).day().month()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .onTapGesture { day = Date() }
                Button { day = Calendar.current.date(byAdding: .day, value: 1, to: day)! } label: { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(AppSettings.shared.bakalariClass).font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                if b.loading { ProgressView().controlSize(.mini).tint(.white) }
                Button { Task { await b.refresh(force: true) } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 9)) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
            }
            if !b.isConfigured {
                Placeholder(icon: "graduationcap", title: L("Bakaláři"), text: L("Vyplň Bakaláře v Nastavení"))
            } else if week, let t = b.timetable {
                WeekGrid(t: t)
            } else if list.isEmpty {
                Placeholder(icon: "graduationcap", title: L("Bakaláři"), text: b.status.isEmpty ? L("Dnes žádné hodiny") : b.status)
            } else {
                if Calendar.current.isDateInToday(day) { SchoolStateLine(state: b.school) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) { ForEach(list) { LessonCard(l: $0) } }
                }
            }
        }
    }
}

/// "Nyní: přestávka 20 min, další MAT v 10:50 (204)" apod.
struct SchoolStateLine: View {
    let state: BakalariService.SchoolState
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(color)
            Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(.white).lineLimit(1)
            Spacer()
        }
    }
    private var icon: String { switch state { case .lesson: return "book.fill"; case .breakTime: return "cup.and.saucer.fill"; case .beforeSchool: return "sunrise.fill"; case .done: return "checkmark.circle.fill"; case .none: return "graduationcap" } }
    private var color: Color { switch state { case .lesson: return .green; case .breakTime: return .orange; default: return .cyan } }
    private var text: String {
        func m(_ t: TimeInterval) -> String { String(format: L("%d min"), max(0, Int(ceil(t / 60)))) }
        switch state {
        case .lesson(let l, let e): return L("Nyní") + ": \(l.lesson.subjectAbbrev) (\(l.lesson.roomAbbrev ?? "–")) · " + L("konec za") + " " + m(e)
        case .breakTime(let n, let s, let len): return L("Přestávka") + " \(Int(len / 60)) min · " + L("další") + " \(n.lesson.subjectAbbrev) (\(n.lesson.roomAbbrev ?? "–")) " + L("za") + " " + m(s)
        case .beforeSchool(let f, let s): return L("První hodina") + " \(f.lesson.subjectAbbrev) " + L("za") + " " + m(s)
        case .done: return L("Konec vyučování")
        case .none: return ""
        }
    }
}

/// Celý týden: řádky dny, sloupce hodiny.
struct WeekGrid: View {
    let t: Timetable
    private let days = ["Po", "Út", "St", "Čt", "Pá"]
    private func firstLesson(day: Int, hour: Int) -> Lesson? {
        let g = AppSettings.shared.bakalariGroup
        return t.lessons(day: day, hourId: hour).first { l in
            guard g != 0, let grp = l.groupAbbrev, let c = grp.first(where: { $0.isNumber }), let n = Int(String(c)) else { return true }
            return n == g
        }
    }
    var body: some View {
        let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text("").frame(width: 18)
                ForEach(t.hours, id: \.Id) { h in Text(h.Caption).font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.4)).frame(maxWidth: .infinity) }
            }
            ForEach(0..<5, id: \.self) { d in
                HStack(spacing: 2) {
                    Text(days[d]).font(.system(size: 7, weight: .bold)).foregroundStyle(d == today ? .cyan : .white.opacity(0.5)).frame(width: 18)
                    ForEach(t.hours, id: \.Id) { h in
                        WeekCell(lesson: firstLesson(day: d, hour: h.Id), isToday: d == today)
                    }
                }
            }
        }
    }
}

struct LessonCard: View {
    let l: BakalariService.TodayLesson
    private var isNow: Bool { l.start <= Date() && l.end > Date() }
    var body: some View {
        VStack(spacing: 2) {
            Text(l.hour.Caption).font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4))
            Text(l.lesson.subjectAbbrev).font(.system(size: 13, weight: .bold)).foregroundStyle(l.lesson.isCancelled ? .white.opacity(0.35) : .white).strikethrough(l.lesson.isCancelled)
            Text(l.lesson.roomAbbrev ?? "–").font(.system(size: 10, weight: .semibold)).foregroundStyle(.cyan.opacity(l.lesson.isCancelled ? 0.4 : 1))
            Text(l.lesson.teacherAbbrev ?? "").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            Text("\(l.hour.BeginTime)").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
        }
        .frame(width: 66, height: 78)
        .background(isNow ? Color.green.opacity(0.22) : (l.lesson.isChanged ? Color.orange.opacity(0.18) : Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(isNow ? Color.green.opacity(0.6) : .clear, lineWidth: 1))
        .help([l.lesson.subjectName, l.lesson.groupAbbrev, l.lesson.changeDescription].compactMap { $0 }.joined(separator: " · "))
    }
}

struct WeekCell: View {
    let lesson: Lesson?
    let isToday: Bool
    private var bg: Color {
        guard let l = lesson else { return Color.white.opacity(0.03) }
        if l.isChanged { return Color.orange.opacity(0.25) }
        return Color.white.opacity(isToday ? 0.14 : 0.08)
    }
    private var tip: String {
        guard let l = lesson else { return "" }
        var t = "\(l.subjectName) · \(l.roomAbbrev ?? "") · \(l.teacherAbbrev ?? "")"
        if let c = l.changeDescription { t += " · \(c)" }
        return t
    }
    var body: some View {
        let cancelled = lesson?.isCancelled == true
        Text(lesson?.subjectAbbrev ?? "")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(cancelled ? Color.white.opacity(0.3) : Color.white)
            .strikethrough(cancelled)
            .frame(maxWidth: .infinity)
            .frame(height: 15)
            .background(bg, in: RoundedRectangle(cornerRadius: 3))
            .help(tip)
    }
}
