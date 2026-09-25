import Foundation
import AppKit
import Combine

/// Časovač / Pomodoro. Běží v křídlech vedle kamery, klik = pauza.
@MainActor
final class TimerService: ObservableObject {
    static let shared = TimerService()
    enum Phase: String { case work, rest }
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var running = false
    @Published private(set) var isPomodoro = false
    @Published private(set) var phase: Phase = .work
    @Published private(set) var pomodoroRound = 0
    var isActive: Bool { total > 0 }
    private var tick: Timer?
    private var endDate: Date?

    private init() {}

    func start(minutes: Int, pomodoro: Bool = false) {
        isPomodoro = pomodoro; phase = .work; pomodoroRound = pomodoro ? 1 : 0
        set(seconds: TimeInterval(minutes * 60)); resume()
    }
    private func set(seconds: TimeInterval) { total = seconds; remaining = seconds }
    func toggle() { running ? pause() : resume() }
    func pause() { running = false; tick?.invalidate(); tick = nil; endDate = nil }
    func resume() {
        guard remaining > 0 else { return }
        running = true; endDate = Date().addingTimeInterval(remaining)
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.update() } }
    }
    func stop() { pause(); total = 0; remaining = 0; isPomodoro = false; pomodoroRound = 0 }
    func addMinute() { remaining += 60; total += 60; if running { endDate = Date().addingTimeInterval(remaining) } }

    private func update() {
        guard let e = endDate else { return }
        remaining = max(0, e.timeIntervalSinceNow)
        if remaining <= 0 { finished() }
    }
    private func finished() {
        pause()
        NSSound(named: "Glass")?.play()
        if isPomodoro {
            if phase == .work { phase = .rest; set(seconds: pomodoroRound % 4 == 0 ? 15 * 60 : 5 * 60) }
            else { phase = .work; pomodoroRound += 1; set(seconds: 25 * 60) }
            ScreenshotService.shared.showHUD(phase == .work ? L("Pomodoro: zpět do práce") : L("Pomodoro: pauza"), icon: "timer")
            resume()
        } else {
            ScreenshotService.shared.showHUD(L("Časovač doběhl"), icon: "timer")
            total = 0
        }
    }
    var text: String { let s = Int(remaining.rounded()); return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60) }
}
