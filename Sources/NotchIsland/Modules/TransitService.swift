import Foundation
import Combine

struct Departure: Identifiable, Equatable {
    let id: String
    let line: String
    let routeType: Int
    let headsign: String
    let scheduled: Date
    let predicted: Date
    let delayMin: Int
    let platform: String
    let tripId: String
    let stopName: String
    var minutes: Int { max(0, Int(predicted.timeIntervalSinceNow / 60)) }
    var mode: TransitMode { TransitMode(routeType: routeType) }
}

enum TransitMode {
    case tram, metro, train, bus, trolley, ferry, other
    init(routeType: Int) {
        switch routeType { case 0: self = .tram; case 1: self = .metro; case 2: self = .train; case 3: self = .bus
        case 4: self = .ferry; case 11: self = .trolley; default: self = .other }
    }
    var fa: String { switch self { case .tram: return FA.tram; case .metro: return FA.subway; case .train: return FA.train; case .bus, .trolley: return FA.bus; case .ferry: return FA.ship; case .other: return FA.bus } }
    var colorHex: UInt { // barvy PID
        switch self { case .tram: return 0x9A2B2B; case .metro: return 0x1F6E43; case .train: return 0x1F4E9A; case .bus: return 0x1D5FB8
        case .trolley: return 0x6A1B9A; case .ferry: return 0x0E7C86; case .other: return 0x555555 }
    }
}

struct TrackedVehicle: Equatable {
    var line: String; var headsign: String; var lastStop: String; var nextStop: String
    var delayMin: Int; var speed: Double?; var updated: Date; var isCanceled: Bool
}

/// PID bez API klíče: statické GTFS (data.pid.cz) + veřejné GTFS-Realtime feedy (trip_updates, vehicle_positions).
@MainActor
final class TransitService: ObservableObject {
    static let shared = TransitService()
    @Published var stopQuery = ""
    @Published private(set) var resolvedStop = ""
    @Published private(set) var departures: [Departure] = []
    @Published private(set) var error: String?
    @Published private(set) var loading = false
    @Published private(set) var tracked: TrackedVehicle?
    @Published private(set) var trackedTripId: String?
    @Published private(set) var status = L("Připravuji data PID…")
    @Published private(set) var suggestions: [String] = []
    private var stopNames: [String] = []   // seznam názvů zastávek pro našeptávání
    private var lastSuggestQuery = ""

    private var refreshTimer: Timer?
    private var lastUpdates: [PIDRealtime.TripUpdate] = []
    private var lastFetch = Date.distantPast

    private init() {
        stopQuery = AppSettings.shared.favoriteStops.first ?? ""
        // obnovovat jen když je Doprava vidět nebo sledujeme spoj; při otevření záložky se obnoví hned
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            guard let self, NotchState.isVisible(.transit) || self.trackedTripId != nil else { return }
            Task { await self.refresh() }
        }
    }

    /// Našeptávání názvů zastávek (z GTFS PID, načte se na pozadí při prvním psaní).
    func suggest(_ q: String) async {
        let n = PIDStatic.normalize(q); lastSuggestQuery = n
        guard n.count >= 2, n != PIDStatic.normalize(resolvedStop) else { suggestions = []; return }
        if stopNames.isEmpty {
            guard (try? await PIDStatic.shared.ensureLoaded()) != nil else { return }
            stopNames = Array(Set(await PIDStatic.shared.stops.values.map(\.name))).sorted()
        }
        guard lastSuggestQuery == n else { return }
        let pref = stopNames.filter { PIDStatic.normalize($0).hasPrefix(n) }
        let contains = pref.count < 6 ? stopNames.filter { !pref.contains($0) && PIDStatic.normalize($0).contains(n) } : []
        suggestions = Array((pref + contains).prefix(6))
    }
    func clearSuggestions() { suggestions = [] }

    private var lastRefresh = Date.distantPast
    /// Zavolat při zobrazení záložky – obnoví jen když jsou data starší než 20 s.
    func refreshIfStale() { if Date().timeIntervalSince(lastRefresh) > 20 { Task { await refresh() } } }

    func refresh() async {
        lastRefresh = Date()
        loading = true; defer { loading = false }
        let token = AppSettings.shared.golemioToken.trimmingCharacters(in: .whitespaces)
        if !token.isEmpty {
            switch await refreshViaAPI(token: token) {
            case .ok: return
            case .unknownStop: departures = []; resolvedStop = ""; status = ""; error = nil; return
            case .failed: break // síť / token → záloha přes veřejná data
            }
        }
        do {
            try await PIDStatic.shared.ensureLoaded()
            status = ""
            if Date().timeIntervalSince(lastFetch) > 15 { lastUpdates = try await PIDRealtime.tripUpdates(); lastFetch = Date() }
            await buildDepartures()
            if let t = trackedTripId { await loadTracked(tripId: t) }
            error = nil
        } catch {
            self.error = "PID data: \(error.localizedDescription)"
            status = ""
        }
    }

    enum APIResult { case ok, unknownStop, failed }
    /// Rychlá cesta: Golemio departure boards (vyžaduje token). Při chybě sítě/tokenu → záloha přes GTFS-RT.
    private func refreshViaAPI(token: String) async -> APIResult {
        let q = stopQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { departures = []; status = ""; return .ok }
        var c = URLComponents(string: "https://api.golemio.cz/v2/pid/departureboards")!
        c.queryItems = [.init(name: "names[]", value: q), .init(name: "minutesAfter", value: "120"), .init(name: "limit", value: "40"), .init(name: "order", value: "real")]
        var r = URLRequest(url: c.url!); r.setValue(token, forHTTPHeaderField: "X-Access-Token"); r.timeoutInterval = 15
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return .failed }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { return .unknownStop }
        guard code == 200, let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let deps = root["departures"] as? [[String: Any]] else { return .failed }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        func date(_ a: Any?) -> Date? { guard let s = a as? String else { return nil }; return iso.date(from: s) ?? iso2.date(from: s) }
        let stopsArr = (root["stops"] as? [[String: Any]]) ?? []
        resolvedStop = stopsArr.first?["stop_name"] as? String ?? q
        departures = deps.compactMap { x in
            let route = x["route"] as? [String: Any] ?? [:], trip = x["trip"] as? [String: Any] ?? [:]
            let dep = x["departure_timestamp"] as? [String: Any] ?? [:], delay = x["delay"] as? [String: Any] ?? [:], st = x["stop"] as? [String: Any] ?? [:]
            guard let sched = date(dep["scheduled"]) else { return nil }
            let pred = date(dep["predicted"]) ?? sched
            let mins = (delay["is_available"] as? Bool ?? false) ? (delay["minutes"] as? Int ?? (delay["seconds"] as? Int ?? 0) / 60) : 0
            let tid = trip["id"] as? String ?? UUID().uuidString
            return Departure(id: tid + sched.description, line: route["short_name"] as? String ?? "?", routeType: route["type"] as? Int ?? -1,
                             headsign: trip["headsign"] as? String ?? "", scheduled: sched, predicted: pred, delayMin: mins,
                             platform: st["platform_code"] as? String ?? "", tripId: tid, stopName: resolvedStop)
        }
        status = ""; error = nil
        if let t = trackedTripId, (try? await PIDStatic.shared.ensureLoaded()) != nil {
            if Date().timeIntervalSince(lastFetch) > 15, let u = try? await PIDRealtime.tripUpdates() { lastUpdates = u; lastFetch = Date() }
            await loadTracked(tripId: t)
        }
        return .ok
    }

    private func buildDepartures() async {
        let q = stopQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let match = await PIDStatic.shared.stopIds(matching: q) else { departures = []; resolvedStop = ""; return }
        resolvedStop = match.name
        let ids = Set(match.ids)
        let now = Date().timeIntervalSince1970, horizon = now + 120 * 60
        var out: [Departure] = []
        let stops = await PIDStatic.shared.stops, routes = await PIDStatic.shared.routes, trips = await PIDStatic.shared.trips
        // jen spoje, které přes zastávku jedou
        let candidates = lastUpdates.filter { tu in tu.stops.contains { ids.contains($0.stopId) } }
        let schedules = await PIDStatic.shared.schedules(for: Set(candidates.map(\.tripId)))
        for tu in candidates {
            guard let idx = tu.stops.firstIndex(where: { ids.contains($0.stopId) }), let sched = schedules[tu.tripId],
                  let ss = sched.first(where: { $0.stopId == tu.stops[idx].stopId }) else { continue }
            guard ss.seq < (sched.last?.seq ?? 0) else { continue } // konečná – neodjíždí
            let delay = tu.stops[idx].delay ?? tu.delay ?? 0
            let t = PIDStatic.serviceDay(tu.startDate).timeIntervalSince1970 + Double(ss.depSec) + Double(delay)
            guard t >= now - 60, t <= horizon else { continue }
            let trip = trips[tu.tripId]
            let route = routes[tu.routeId ?? trip?.routeId ?? ""]
            let headsign = trip?.headsign ?? stops[tu.stops.last?.stopId ?? ""]?.name ?? ""
            out.append(Departure(id: tu.tripId, line: route?.shortName ?? "?", routeType: route?.type ?? -1, headsign: headsign,
                                 scheduled: Date(timeIntervalSince1970: t - Double(delay)), predicted: Date(timeIntervalSince1970: t),
                                 delayMin: Int(delay / 60), platform: stops[tu.stops[idx].stopId]?.platform ?? "", tripId: tu.tripId, stopName: match.name))
        }
        departures = out.sorted { $0.predicted < $1.predicted }
    }

    func track(_ d: Departure) {
        trackedTripId = d.tripId
        tracked = TrackedVehicle(line: d.line, headsign: d.headsign, lastStop: "…", nextStop: d.stopName, delayMin: d.delayMin, speed: nil, updated: Date(), isCanceled: false)
        Task { await loadTracked(tripId: d.tripId) }
    }
    func stopTracking() { trackedTripId = nil; tracked = nil }

    private func loadTracked(tripId: String) async {
        guard let tu = lastUpdates.first(where: { $0.tripId == tripId }) else { tracked?.lastStop = "Spoj už není v datech"; return }
        let vehicles = (try? await PIDRealtime.vehicles()) ?? [:]
        let stops = await PIDStatic.shared.stops
        var last = "Vozidlo zatím nevyjelo", next = stops[tu.stops.first?.stopId ?? ""]?.name ?? "–"
        var updated = Date(), speed: Double? = nil
        if let v = vehicles[tripId] {
            updated = v.timestamp.map { Date(timeIntervalSince1970: Double($0)) } ?? Date()
            speed = v.speed.map { Double($0) * 3.6 }
            let seq = v.stopSequence ?? tu.stops.first(where: { $0.stopId == v.stopId })?.sequence ?? 0
            if let i = tu.stops.firstIndex(where: { $0.sequence == seq }) {
                if v.status == 1 { last = stops[tu.stops[i].stopId]?.name ?? "–"; next = i + 1 < tu.stops.count ? (stops[tu.stops[i + 1].stopId]?.name ?? "–") : L("konečná") } // STOPPED_AT
                else { next = stops[tu.stops[i].stopId]?.name ?? "–"; last = i > 0 ? (stops[tu.stops[i - 1].stopId]?.name ?? "–") : L("výchozí") }
            }
        } else {
            // bez polohy odhadneme podle jízdního řádu + zpoždění
            let sched = await PIDStatic.shared.schedules(for: [tripId])[tripId] ?? []
            let day = PIDStatic.serviceDay(tu.startDate).timeIntervalSince1970, nowT = Date().timeIntervalSince1970
            if let i = sched.lastIndex(where: { s in day + Double(s.depSec) + Double(tu.stops.first(where: { $0.stopId == s.stopId })?.delay ?? 0) <= nowT }) {
                last = stops[sched[i].stopId]?.name ?? "–"; next = i + 1 < sched.count ? (stops[sched[i + 1].stopId]?.name ?? "–") : L("konečná")
            }
        }
        tracked = TrackedVehicle(line: tracked?.line ?? "", headsign: tracked?.headsign ?? "", lastStop: last, nextStop: next,
                                 delayMin: Int((tu.delay ?? tu.stops.first(where: { ($0.time ?? 0) > Int64(Date().timeIntervalSince1970) })?.delay ?? 0) / 60),
                                 speed: speed, updated: updated, isCanceled: false)
    }
}
