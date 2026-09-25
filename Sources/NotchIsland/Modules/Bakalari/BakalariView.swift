import SwiftUI

struct BakalariView: View {
    @ObservedObject var b = BakalariService.shared
    @State private var day = Date()
    @AppStorage("bakalariWeekView") private var week = false
    @State private var hovered: BakalariService.TodayLesson?
    var body: some View {
        let list = b.lessons(on: day)
        VStack(alignment: .leading, spacing: 4) {
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
                WeekGrid(t: t, hours: b.allHours)
            } else if list.isEmpty {
                Placeholder(icon: "graduationcap", title: L("Bakaláři"), text: b.status.isEmpty ? L("Dnes žádné hodiny") : b.status)
            } else {
                if let h = hovered { LessonDetailLine(l: h) }
                else if Calendar.current.isDateInToday(day) { SchoolStateLine(state: b.school) }
                else { Color.clear.frame(height: 12) }
                let grouped = Dictionary(grouping: list, by: { $0.hour.Id })
                let allHours = b.allHours
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(allHours, id: \.Id) { h in
                            if let ls = grouped[h.Id], !ls.isEmpty {
                                VStack(spacing: 2) {
                                    ForEach(ls) { l in LessonCard(l: l, split: ls.count).onHover { hovered = $0 ? l : (hovered?.id == l.id ? nil : hovered) } }
                                }.frame(height: 78)
                            } else {
                                EmptyHourCard(h: h)
                            }
                        }
                    }
                }
                .frame(height: 80)
                .animation(.easeOut(duration: 0.12), value: hovered?.id)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Detail hodiny po najetí myší: celý název, učitel, učebna, skupina, téma, poznámka, změna.
struct LessonDetailLine: View {
    let l: BakalariService.TodayLesson
    var body: some View {
        let x = l.lesson
        HStack(spacing: 6) {
            Text("\(l.hour.Caption). \(l.hour.BeginTime)–\(l.hour.EndTime)").font(.system(size: 9, weight: .bold)).foregroundStyle(.cyan)
            Text(x.subjectName.isEmpty ? x.subjectAbbrev : x.subjectName).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Text("·").foregroundStyle(.white.opacity(0.3))
            Text([x.teacherFull ?? x.teacherAbbrev, x.roomFull ?? x.roomAbbrev, x.groupFull ?? x.groupAbbrev].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            if let t = x.theme, !t.isEmpty { Text(L("téma") + ": \(t)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
            if let n = x.notice, !n.isEmpty { Text(n).font(.system(size: 9, weight: .semibold)).foregroundStyle(.yellow).lineLimit(1) }
            if let c = x.changeDescription, !c.isEmpty { Text(c).font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange).lineLimit(1) }
            Spacer(minLength: 0)
        }
        .transition(.opacity)
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

/// Celý týden: řádky dny, sloupce hodiny – dlaždice s předmětem a učebnou, dnešek zvýrazněný.
struct EmptyHourCard: View {
    let h: HourRef
    var body: some View {
        VStack(spacing: 2) {
            Text(h.Caption).font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.3))
            Spacer()
            Text(h.BeginTime).font(.system(size: 8)).foregroundStyle(.white.opacity(0.2))
        }
        .padding(.vertical, 4)
        .frame(width: 66, height: 78)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

struct WeekGrid: View {
    let t: Timetable
    let hours: [HourRef]
    private let days = ["Po", "Út", "St", "Čt", "Pá"]
    private func lessonsFor(day: Int, hour: Int) -> [Lesson] {
        let g = AppSettings.shared.bakalariGroup
        return t.lessons(day: day, hourId: hour).filter { l in
            guard g != 0, let grp = l.groupAbbrev, let c = grp.first(where: { $0.isNumber }), let n = Int(String(c)) else { return true }
            return n == g
        }
    }
    var body: some View {
        let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        let rowH: CGFloat = 30
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Color.clear.frame(width: 24, height: 10)
                ForEach(hours, id: \.Id) { h in
                    VStack(spacing: 0) {
                        Text(h.Caption).font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 10)
            ForEach(0..<5, id: \.self) { d in
                HStack(spacing: 3) {
                    Text(days[d]).font(.system(size: 9, weight: .bold)).foregroundStyle(d == today ? .cyan : .white.opacity(0.55))
                        .frame(width: 24, height: rowH)
                        .background(d == today ? Color.cyan.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    ForEach(hours, id: \.Id) { h in WeekCell(lessons: lessonsFor(day: d, hour: h.Id), isToday: d == today, height: rowH) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct WeekCell: View {
    let lessons: [Lesson]
    let isToday: Bool
    let height: CGFloat
    private func bg(_ l: Lesson) -> Color {
        if l.isCancelled { return Color.red.opacity(0.14) }
        if l.isChanged { return Color.orange.opacity(0.22) }
        return Color.white.opacity(isToday ? 0.16 : 0.09)
    }
    private var tip: String {
        lessons.map { l in
            var t = "\(l.groupAbbrev.map { "\($0) " } ?? "")\(l.subjectName.isEmpty ? l.subjectAbbrev : l.subjectName) · \(l.roomFull ?? l.roomAbbrev ?? "") · \(l.teacherFull ?? l.teacherAbbrev ?? "")"
            if let th = l.theme, !th.isEmpty { t += " · \(th)" }
            if let c = l.changeDescription { t += " · \(c)" }
            return t
        }.joined(separator: "\n")
    }
    var body: some View {
        VStack(spacing: 1) {
            if lessons.isEmpty {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.03)).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(lessons.prefix(2)) { l in
                    let multi = lessons.count > 1
                    Group {
                        if multi {
                            HStack(spacing: 3) {
                                Text(l.subjectAbbrev).font(.system(size: 8, weight: .bold))
                                Text(l.isCancelled ? "×" : (l.roomAbbrev ?? "")).font(.system(size: 7, weight: .semibold)).foregroundStyle(l.isCancelled ? .red : (l.roomChanged ? .orange : .cyan))
                            }
                        } else {
                            VStack(spacing: 0) {
                                Text(l.subjectAbbrev).font(.system(size: 10, weight: .bold))
                                Text(l.isCancelled ? L("Zrušeno") : (l.roomAbbrev ?? "")).font(.system(size: 8, weight: .semibold)).foregroundStyle(l.isCancelled ? .red : (l.roomChanged ? .orange : .cyan))
                            }
                        }
                    }
                    .foregroundStyle(l.isCancelled ? Color.white.opacity(0.4) : Color.white).strikethrough(l.isCancelled, color: .red).lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(bg(l), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(l.isCancelled ? Color.red.opacity(0.5) : (l.isChanged ? Color.orange.opacity(0.5) : .clear), style: StrokeStyle(lineWidth: 1, dash: l.isCancelled ? [2, 2] : [])))
                }
            }
        }
        .frame(height: height)
        .help(tip)
    }
}

extension Lesson {
    /// Suplování / změna zmiňuje jinou učebnu než původní → zvýraznit učebnu.
    var roomChanged: Bool {
        guard isChanged, let c = changeDescription, let r = roomAbbrev, !r.isEmpty else { return false }
        return c.contains(r)
    }
    var badge: String? { isCancelled ? "×" : (state == .added ? "+" : (isChanged ? "S" : nil)) }
}

/// Seskupí hodiny podle vyučovací hodiny (skupiny / semináře ve stejný čas).
func groupedByHour(_ list: [BakalariService.TodayLesson]) -> [(Int, [BakalariService.TodayLesson])] {
    var order: [Int] = [], map: [Int: [BakalariService.TodayLesson]] = [:]
    for l in list { if map[l.hour.Id] == nil { order.append(l.hour.Id) }; map[l.hour.Id, default: []].append(l) }
    return order.map { ($0, map[$0]!) }
}

struct LessonCard: View {
    let l: BakalariService.TodayLesson
    var split = 1   // kolik hodin sdílí stejný čas (1 = celá karta, 2+ = půlené)
    private var isNow: Bool { l.start <= Date() && l.end > Date() }
    private var x: Lesson { l.lesson }
    private var bg: Color {
        if x.isCancelled { return Color.red.opacity(0.14) }
        if isNow { return Color.green.opacity(0.22) }
        if x.isChanged { return Color.orange.opacity(0.2) }
        return Color.white.opacity(0.07)
    }
    private var border: Color {
        if x.isCancelled { return Color.red.opacity(0.5) }
        if isNow { return Color.green.opacity(0.6) }
        if x.isChanged { return Color.orange.opacity(0.5) }
        return .clear
    }
    private var badgeColor: Color { x.isCancelled ? .red : (x.state == .added ? .green : .orange) }
    var body: some View {
        let compact = split > 1
        VStack(spacing: compact ? 0 : 2) {
            if !compact { Text(l.hour.Caption).font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4)) }
            titleRow(compact: compact)
            if x.isCancelled {
                Text(L("Zrušeno")).font(.system(size: compact ? 8 : 9, weight: .semibold)).foregroundStyle(.red)
            } else {
                HStack(spacing: 4) {
                    Text(x.roomAbbrev ?? "–").font(.system(size: compact ? 9 : 10, weight: .bold)).foregroundStyle(x.roomChanged ? Color.orange : Color.cyan)
                    if compact { Text(x.teacherAbbrev ?? "").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5)).lineLimit(1) }
                }
            }
            if !compact {
                Text(x.teacherAbbrev ?? "").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                Text(l.hour.BeginTime).font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: 66).frame(maxHeight: .infinity)
        .background(bg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(border, style: StrokeStyle(lineWidth: 1, dash: x.isCancelled ? [3, 2] : [])))
        .overlay(alignment: .topLeading) { badgeView }
        .overlay(alignment: .topTrailing) {
            if let n = x.notice, !n.isEmpty { Circle().fill(Color.yellow).frame(width: 5, height: 5).padding(4) }
        }
    }
    private func titleRow(compact: Bool) -> some View {
        HStack(spacing: 3) {
            if compact, let g = x.groupAbbrev { Text(g).font(.system(size: 7)).foregroundStyle(.white.opacity(0.5)) }
            Text(x.subjectAbbrev).font(.system(size: compact ? 11 : 13, weight: .bold))
                .foregroundStyle(x.isCancelled ? Color.white.opacity(0.45) : Color.white)
                .strikethrough(x.isCancelled, color: .red)
        }
    }
    @ViewBuilder private var badgeView: some View {
        if let b = x.badge {
            Text(b).font(.system(size: 7, weight: .black)).foregroundStyle(.white).frame(width: 11, height: 11)
                .background(badgeColor, in: RoundedRectangle(cornerRadius: 3)).padding(3)
        }
    }
}
