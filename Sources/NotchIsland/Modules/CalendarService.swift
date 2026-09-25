import EventKit
import Combine

struct CalEvent: Identifiable { let id: String; let title: String; let start: Date; let end: Date; let allDay: Bool; let color: CGColor?; let location: String? }

/// EventKit – události z Kalendáře pro libovolný den (cache po dnech).
@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    @Published private(set) var events: [CalEvent] = []   // dnes + zítra (pro kompaktní přehled)
    @Published private(set) var status = "…"
    @Published private(set) var version = 0                  // změna → views si znovu načtou dny
    private let store = EKEventStore()
    private var timer: Timer?
    private var cache: [Date: [CalEvent]] = [:]

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.reload() }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in Task { @MainActor in self?.reload() } }
        requestAndLoad()
    }

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAndLoad() {
        store.requestFullAccessToEvents { [weak self] ok, _ in
            Task { @MainActor in
                if ok { self?.reload() } else { self?.status = L("Bez přístupu ke kalendáři") }
            }
        }
    }

    private func reload() {
        guard hasAccess else { return }
        cache = [:]
        let today = Calendar.current.startOfDay(for: Date())
        events = (self.events(on: today) + self.events(on: Calendar.current.date(byAdding: .day, value: 1, to: today)!)).filter { $0.end > Date() }
        status = events.isEmpty ? L("Nic nadcházejícího") : ""
        version += 1
    }

    func events(on day: Date) -> [CalEvent] {
        let start = Calendar.current.startOfDay(for: day)
        if let c = cache[start] { return c }
        guard hasAccess else { return [] }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let list = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { CalEvent(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? L("(bez názvu)"), start: $0.startDate, end: $0.endDate,
                            allDay: $0.isAllDay, color: $0.calendar.cgColor, location: $0.location) }
        cache[start] = list
        return list
    }
}
