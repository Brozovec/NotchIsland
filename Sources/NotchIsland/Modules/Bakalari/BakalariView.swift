import SwiftUI

struct BakalariView: View {
    @ObservedObject var b = BakalariService.shared
    @State private var day = Date()
    var body: some View {
        let list = b.lessons(on: day)
        VStack(spacing: 4) {
            HStack(spacing: 8) {
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
            } else if list.isEmpty {
                Placeholder(icon: "graduationcap", title: L("Bakaláři"), text: b.status.isEmpty ? L("Dnes žádné hodiny") : b.status)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) { ForEach(list) { LessonCard(l: $0) } }
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
