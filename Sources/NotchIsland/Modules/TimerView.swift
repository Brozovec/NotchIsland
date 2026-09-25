import SwiftUI

struct TimerView: View {
    @ObservedObject var t = TimerService.shared
    @State private var custom = ""
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
                Circle().trim(from: 0, to: t.total > 0 ? CGFloat(t.remaining / t.total) : 0)
                    .stroke(t.phase == .rest ? Color.cyan : Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: t.remaining)
                VStack(spacing: 0) {
                    Text(t.isActive ? t.text : "0:00").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(.white).monospacedDigit()
                    if t.isPomodoro { Text(t.phase == .work ? L("práce") + " \(t.pomodoroRound)" : L("pauza")).font(.system(size: 8)).foregroundStyle(.white.opacity(0.5)) }
                }
            }
            .frame(width: 84, height: 84)
            .contentShape(Circle()).onTapGesture { if t.isActive { t.toggle() } }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ForEach([5, 10, 15, 25, 45, 60], id: \.self) { m in
                        Button("\(m)") { t.start(minutes: m) }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Color.white.opacity(0.1), in: Capsule()).foregroundStyle(.white)
                    }
                    Button { t.start(minutes: 25, pomodoro: true) } label: {
                        HStack(spacing: 3) { Image(systemName: "leaf.fill"); Text("Pomodoro") }.font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Color.orange.opacity(0.35), in: Capsule()).foregroundStyle(.white)
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    TextField(L("min"), text: $custom).textFieldStyle(.plain).font(.system(size: 10)).foregroundStyle(.white).frame(width: 40)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .onSubmit { if let m = Int(custom), m > 0 { t.start(minutes: m); custom = "" } }
                    if t.isActive {
                        ctl(t.running ? "pause.fill" : "play.fill") { t.toggle() }
                        ctl("plus") { t.addMinute() }
                        ctl("stop.fill") { t.stop() }
                    }
                }
                Text(L("Odpočet běží v křídlech vedle kamery, klik = pauza. Pomodoro 25/5, po 4 kolech 15 min.")).font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }
    private func ctl(_ i: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: i).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).frame(width: 24, height: 20).background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
    }
}
