import Foundation
import Combine

struct Connection: Identifiable {
    enum Carrier: String { case regiojet = "RegioJet", flixbus = "FlixBus" }
    let id: String
    let carrier: Carrier
    let from: String
    let to: String
    let departure: Date
    let arrival: Date
    let isTrain: Bool
    let transfers: Int
    let price: Double?
    let freeSeats: Int?
    let delayMin: Int?     // RegioJet posílá aktuální zpoždění u jedoucích spojů
    var duration: TimeInterval { arrival.timeIntervalSince(departure) }
}

/// Mini vyhledávač spojení RegioJet + FlixBus (veřejná rozhraní jejich webů, bez klíče).
@MainActor
final class IntercityService: ObservableObject {
    static let shared = IntercityService()
    @Published var from = "Praha"
    @Published var to = "Brno"
    @Published private(set) var results: [Connection] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var tracked: Connection?
    private var trackTimer: Timer?
    private var rjIds: (Int, Int)?
    private var fbIds: (String, String)?

    private struct RJCity { let id: Int; let name: String; let stations: [Int: String] }
    private var rjCities: [RJCity] = []
    private let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private let iso2 = ISO8601DateFormatter()

    private init() {
        Task { await loadRJCities() }
        trackTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, self.tracked != nil else { return }   // bez sledovaného spoje žádná síť
            Task { await self.refreshTracked() }
        }
    }

    /// Našeptávání měst (RegioJet seznam + FlixBus autocomplete).
    func suggest(_ q: String) async {
        let n = PIDStatic.normalize(q)
        guard n.count >= 2 else { suggestions = []; return }
        await loadRJCities()
        Log.w("suggest '\(q)' rjCities=\(rjCities.count)")
        var out = rjCities.map(\.name).filter { PIDStatic.normalize($0).hasPrefix(n) }
        if out.count < 5, let fb = await fbCities(q) { for c in fb where !out.contains(c) { out.append(c) } }
        suggestions = Array(out.prefix(6))
        Log.w("suggestions: \(suggestions)")
    }
    func clearSuggestions() { suggestions = [] }

    func track(_ c: Connection?) { tracked = c }
    private func refreshTracked() async {
        guard let t = tracked else { return }
        if t.arrival < Date().addingTimeInterval(-10 * 60) { tracked = nil; return }
        let rj = await searchRegioJet(from: from, to: to)
        if let n = (rj + (t.carrier == .flixbus ? await searchFlixBus(from: from, to: to) : [])).first(where: { $0.id == t.id }) { tracked = n }
    }

    /// Odkaz na nákup jízdenky u dopravce (předvyplněné vyhledávání).
    func ticketURL(_ c: Connection) -> URL? {
        let df = DateFormatter()
        switch c.carrier {
        case .regiojet:
            guard let ids = rjIds else { return URL(string: "https://regiojet.cz") }
            df.dateFormat = "yyyy-MM-dd"
            return URL(string: "https://regiojet.cz/vyhledavani?fromLocationId=\(ids.0)&fromLocationType=CITY&toLocationId=\(ids.1)&toLocationType=CITY&departureDate=\(df.string(from: c.departure))&tariffs=REGULAR")
        case .flixbus:
            guard let ids = fbIds else { return URL(string: "https://shop.flixbus.cz") }
            df.dateFormat = "dd.MM.yyyy"
            return URL(string: "https://shop.flixbus.cz/search?departureCity=\(ids.0)&arrivalCity=\(ids.1)&rideDate=\(df.string(from: c.departure))&adult=1")
        }
    }
    /// ČD a ostatní dopravci přes IDOS (vlaky, autobusy, vše).
    func idosURL() -> URL? {
        var u = URLComponents(string: "https://idos.cz/vlakyautobusymhdvse/spojeni/vysledky/")!
        u.queryItems = [.init(name: "f", value: from), .init(name: "t", value: to)]
        return u.url
    }

    func search() async {
        let f = from.trimmingCharacters(in: .whitespaces), t = to.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty, !t.isEmpty else { return }
        loading = true; defer { loading = false }
        error = nil
        async let rj = searchRegioJet(from: f, to: t)
        async let fb = searchFlixBus(from: f, to: t)
        let (a, b) = await (rj, fb)
        let now = Date().addingTimeInterval(-30 * 60)
        results = (a + b).filter { $0.departure > now }.sorted { $0.departure < $1.departure }
        if results.isEmpty, error == nil { error = L("Dnes už nic nejede (nebo nezná města)") }
    }

    private func get(_ url: URL, headers: [String: String] = [:]) async throws -> Any {
        var r = URLRequest(url: url); r.timeoutInterval = 20
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        r.setValue("Mozilla/5.0 NotchIsland", forHTTPHeaderField: "User-Agent")
        let (d, _) = try await URLSession.shared.data(for: r)
        return try JSONSerialization.jsonObject(with: d)
    }

    // MARK: RegioJet
    private func loadRJCities() async {
        guard rjCities.isEmpty, let j = try? await get(URL(string: "https://brn-ybus-pubapi.sa.cz/restapi/consts/locations")!) as? [[String: Any]] else { return }
        var out: [RJCity] = []
        for country in j {
            for c in country["cities"] as? [[String: Any]] ?? [] {
                guard let id = c["id"] as? Int, let n = c["name"] as? String else { continue }
                var st: [Int: String] = [:]
                for s in c["stations"] as? [[String: Any]] ?? [] { if let sid = s["id"] as? Int { st[sid] = (s["fullname"] as? String) ?? (s["name"] as? String) ?? n } }
                out.append(RJCity(id: id, name: n, stations: st))
            }
        }
        rjCities = out
    }

    private func rjCity(_ q: String) -> RJCity? {
        let n = PIDStatic.normalize(q)
        return rjCities.first { PIDStatic.normalize($0.name) == n } ?? rjCities.first { PIDStatic.normalize($0.name).hasPrefix(n) }
    }

    private func searchRegioJet(from: String, to: String) async -> [Connection] {
        await loadRJCities()
        guard let a = rjCity(from), let b = rjCity(to) else { return [] }
        rjIds = (a.id, b.id)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        var u = URLComponents(string: "https://brn-ybus-pubapi.sa.cz/restapi/routes/search/simple")!
        u.queryItems = [.init(name: "fromLocationId", value: "\(a.id)"), .init(name: "fromLocationType", value: "CITY"),
                        .init(name: "toLocationId", value: "\(b.id)"), .init(name: "toLocationType", value: "CITY"),
                        .init(name: "departureDate", value: df.string(from: Date())), .init(name: "tariffs", value: "REGULAR")]
        guard let j = try? await get(u.url!, headers: ["X-Currency": "CZK", "X-Lang": "cs"]) as? [String: Any], let routes = j["routes"] as? [[String: Any]] else { return [] }
        let stations = rjCities.reduce(into: [Int: String]()) { $0.merge($1.stations) { x, _ in x } }
        return routes.compactMap { r in
            guard let id = r["id"] as? String, let dep = (r["departureTime"] as? String).flatMap({ iso.date(from: $0) ?? iso2.date(from: $0) }),
                  let arr = (r["arrivalTime"] as? String).flatMap({ iso.date(from: $0) ?? iso2.date(from: $0) }) else { return nil }
            let types = r["vehicleTypes"] as? [String] ?? []
            let price = (r["priceFrom"] as? Double).flatMap { $0 > 0 ? $0 : nil }
            var delay: Int? = nil
            if let d = r["delay"] as? String, let m = Int(d.filter { $0.isNumber }) { delay = m }
            else if let d = r["delay"] as? Int { delay = d }
            return Connection(id: "rj-" + id, carrier: .regiojet,
                              from: stations[r["departureStationId"] as? Int ?? 0] ?? a.name, to: stations[r["arrivalStationId"] as? Int ?? 0] ?? b.name,
                              departure: dep, arrival: arr, isTrain: types.contains("TRAIN") && !types.contains("BUS"),
                              transfers: r["transfersCount"] as? Int ?? 0, price: price, freeSeats: r["freeSeatsCount"] as? Int, delayMin: delay)
        }
    }

    // MARK: FlixBus
    private func fbCity(_ q: String) async -> (id: String, name: String)? {
        var u = URLComponents(string: "https://global.api.flixbus.com/search/autocomplete/cities")!
        u.queryItems = [.init(name: "q", value: q), .init(name: "lang", value: "cs"), .init(name: "country", value: "cz")]
        guard let j = try? await get(u.url!) as? [[String: Any]], let c = j.first, let id = c["id"] as? String else { return nil }
        return (id, c["name"] as? String ?? q)
    }

    private func fbCities(_ q: String) async -> [String]? {
        var u = URLComponents(string: "https://global.api.flixbus.com/search/autocomplete/cities")!
        u.queryItems = [.init(name: "q", value: q), .init(name: "lang", value: "cs"), .init(name: "country", value: "cz")]
        guard let j = try? await get(u.url!) as? [[String: Any]] else { return nil }
        return j.compactMap { $0["name"] as? String }
    }

    private func searchFlixBus(from: String, to: String) async -> [Connection] {
        guard let a = await fbCity(from), let b = await fbCity(to) else { return [] }
        fbIds = (a.id, b.id)
        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
        var u = URLComponents(string: "https://global.api.flixbus.com/search/service/v4/search")!
        u.queryItems = [.init(name: "from_city_id", value: a.id), .init(name: "to_city_id", value: b.id), .init(name: "departure_date", value: df.string(from: Date())),
                        .init(name: "products", value: "{\"adult\":1}"), .init(name: "currency", value: "CZK"), .init(name: "locale", value: "cs"),
                        .init(name: "search_by", value: "cities"), .init(name: "include_after_midnight_rides", value: "1")]
        guard let j = try? await get(u.url!) as? [String: Any], let trips = j["trips"] as? [[String: Any]], let first = trips.first,
              let res = first["results"] as? [String: [String: Any]] else { return [] }
        let stations = (j["stations"] as? [String: [String: Any]]) ?? [:]
        let f = ISO8601DateFormatter()
        return res.compactMap { key, r in
            guard let dep = ((r["departure"] as? [String: Any])?["date"] as? String).flatMap(f.date(from:)),
                  let arr = ((r["arrival"] as? [String: Any])?["date"] as? String).flatMap(f.date(from:)) else { return nil }
            let ds = (r["departure"] as? [String: Any])?["station_id"] as? String ?? "", as_ = (r["arrival"] as? [String: Any])?["station_id"] as? String ?? ""
            let legs = (r["legs"] as? [[String: Any]])?.count ?? 1
            let isTrain = ((r["legs"] as? [[String: Any]])?.first?["means_of_transport"] as? String) == "train"
            let sold = (r["status"] as? String) != "available"
            return Connection(id: "fb-" + key, carrier: .flixbus, from: stations[ds]?["name"] as? String ?? a.name, to: stations[as_]?["name"] as? String ?? b.name,
                              departure: dep, arrival: arr, isTrain: isTrain, transfers: max(0, legs - 1),
                              price: (r["price"] as? [String: Any])?["total"] as? Double, freeSeats: sold ? 0 : nil, delayMin: nil)
        }
    }
}
