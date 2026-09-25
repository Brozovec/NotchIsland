import Foundation

/// Statická data PID (GTFS) – stáhne se jednou denně z data.pid.cz (bez klíče), rozbalí jen potřebné soubory.
actor PIDStatic {
    static let shared = PIDStatic()
    struct Stop { let name: String; let platform: String }
    struct Route { let shortName: String; let type: Int }
    struct Trip { let routeId: String; let headsign: String }

    private(set) var stops: [String: Stop] = [:]
    private(set) var stopIdsByName: [String: [String]] = [:]   // normalizovaný název → stop_id
    private(set) var routes: [String: Route] = [:]
    private(set) var trips: [String: Trip] = [:]
    private(set) var loaded = false
    private var loading = false

    private var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NotchIsland/gtfs", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "cs")).lowercased().trimmingCharacters(in: .whitespaces)
    }

    func ensureLoaded() async throws {
        if loaded || loading { return }
        loading = true; defer { loading = false }
        let zip = dir.appendingPathComponent("PID_GTFS.zip")
        let age = (try? FileManager.default.attributesOfItem(atPath: zip.path)[.modificationDate] as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
        if age > 24 * 3600 {
            let (tmp, _) = try await URLSession.shared.download(from: URL(string: "https://data.pid.cz/PID_GTFS.zip")!)
            _ = try? FileManager.default.removeItem(at: zip)
            try FileManager.default.moveItem(at: tmp, to: zip)
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = ["-o", "-q", zip.path, "stops.txt", "routes.txt", "trips.txt", "stop_times.txt", "-d", dir.path]
            try p.run(); p.waitUntilExit()
        }
        try parse()
        loaded = true
    }

    private func parse() throws {
        var s: [String: Stop] = [:], byName: [String: [String]] = [:]
        for r in try Self.csv(dir.appendingPathComponent("stops.txt")) {
            guard let id = r["stop_id"], let name = r["stop_name"] else { continue }
            s[id] = Stop(name: name, platform: r["platform_code"] ?? "")
            byName[Self.normalize(name), default: []].append(id)
        }
        var ro: [String: Route] = [:]
        for r in try Self.csv(dir.appendingPathComponent("routes.txt")) {
            guard let id = r["route_id"] else { continue }
            ro[id] = Route(shortName: r["route_short_name"] ?? "?", type: Int(r["route_type"] ?? "") ?? -1)
        }
        var t: [String: Trip] = [:]
        for r in try Self.csv(dir.appendingPathComponent("trips.txt")) {
            guard let id = r["trip_id"] else { continue }
            t[id] = Trip(routeId: r["route_id"] ?? "", headsign: r["trip_headsign"] ?? "")
        }
        stops = s; stopIdsByName = byName; routes = ro; trips = t
    }

    struct ScheduledStop { let stopId: String; let seq: Int; let depSec: Int }
    private var scheduleCache: [String: [ScheduledStop]] = [:]
    private var lastScan = Date.distantPast

    /// Jízdní řád (stop_times) pro dané spoje. Feed PID posílá jen zpoždění, časy bereme odsud.
    /// Soubor má ~120 MB, proto ho projíždíme proudově a držíme jen aktivní spoje; sken max. 1× za 3 min.
    func schedules(for tripIds: Set<String>) -> [String: [ScheduledStop]] {
        let missing = tripIds.subtracting(scheduleCache.keys)
        if !missing.isEmpty, Date().timeIntervalSince(lastScan) > 180 {
            lastScan = Date()
            scan(wanted: missing)
        }
        return scheduleCache.filter { tripIds.contains($0.key) }
    }

    private func scan(wanted: Set<String>) {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("stop_times.txt"), options: .mappedIfSafe) else { return }
        var found: [String: [ScheduledStop]] = [:]
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            guard let base = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let n = buf.count
            // hlavička → indexy sloupců
            var i = 0
            while i < n, base[i] != 10 { i += 1 }
            let header = String(decoding: UnsafeBufferPointer(start: base, count: i), as: UTF8.self).replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\u{FEFF}", with: "").split(separator: ",").map(String.init)
            guard let cTrip = header.firstIndex(of: "trip_id"), let cDep = header.firstIndex(of: "departure_time"),
                  let cStop = header.firstIndex(of: "stop_id"), let cSeq = header.firstIndex(of: "stop_sequence") else { return }
            i += 1
            var fields = [Range<Int>](repeating: 0..<0, count: header.count)
            while i < n {
                // rozsekat řádek na pole (stop_times nemá uvozovky)
                var f = 0, start = i, j = i
                while j < n, base[j] != 10 {
                    if base[j] == 44 { if f < fields.count { fields[f] = start..<j }; f += 1; start = j + 1 }
                    j += 1
                }
                if f < fields.count { fields[f] = start..<(j > start && base[j - 1] == 13 ? j - 1 : j) }
                let lineEnd = j; i = j + 1
                guard f >= max(cTrip, cDep, cStop, cSeq) else { continue }
                let tr = fields[cTrip]
                let tripId = String(decoding: UnsafeBufferPointer(start: base + tr.lowerBound, count: tr.count), as: UTF8.self)
                guard wanted.contains(tripId) else { continue }
                let d = fields[cDep]
                let dep = String(decoding: UnsafeBufferPointer(start: base + d.lowerBound, count: d.count), as: UTF8.self).split(separator: ":").compactMap { Int($0) }
                let sec = dep.count == 3 ? dep[0] * 3600 + dep[1] * 60 + dep[2] : 0
                let st = fields[cStop], sq = fields[cSeq]
                let stopId = String(decoding: UnsafeBufferPointer(start: base + st.lowerBound, count: st.count), as: UTF8.self)
                let seq = Int(String(decoding: UnsafeBufferPointer(start: base + sq.lowerBound, count: sq.count), as: UTF8.self)) ?? 0
                found[tripId, default: []].append(ScheduledStop(stopId: stopId, seq: seq, depSec: sec))
                _ = lineEnd
            }
        }
        for (k, v) in found { scheduleCache[k] = v.sorted { $0.seq < $1.seq } }
        if scheduleCache.count > 20000 { scheduleCache = scheduleCache.filter { wanted.contains($0.key) } }
    }

    /// Epocha začátku provozního dne (start_date "YYYYMMDD" z feedu).
    nonisolated static func serviceDay(_ yyyymmdd: String?) -> Date {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.timeZone = TimeZone(identifier: "Europe/Prague")
        return yyyymmdd.flatMap { f.date(from: $0) } ?? Calendar.current.startOfDay(for: Date())
    }

    /// Najde zastávky podle názvu (přesná shoda, jinak prefix).
    func stopIds(matching query: String) -> (name: String, ids: [String])? {
        let q = Self.normalize(query); guard !q.isEmpty else { return nil }
        if let ids = stopIdsByName[q], let n = stops[ids[0]]?.name { return (n, ids) }
        if let k = stopIdsByName.keys.filter({ $0.hasPrefix(q) }).sorted(by: { $0.count < $1.count }).first, let ids = stopIdsByName[k], let n = stops[ids[0]]?.name { return (n, ids) }
        return nil
    }

    /// Jednoduchý CSV parser (uvozovky, čárky), vrací řádky jako slovníky.
    nonisolated static func csv(_ url: URL) throws -> [[String: String]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var rows: [[String: String]] = []; var header: [String] = []
        var field = "", record: [String] = [], inQ = false
        var it = text.unicodeScalars.makeIterator()
        func endRecord() {
            record.append(field); field = ""
            if header.isEmpty { header = record.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}\r")) } }
            else if record.count > 1 { rows.append(Dictionary(uniqueKeysWithValues: zip(header, record).map { ($0, $1) })) }
            record = []
        }
        while let c = it.next() {
            if inQ { if c == "\"" { inQ = false } else { field.unicodeScalars.append(c) } }
            else if c == "\"" { inQ = true }
            else if c == "," { record.append(field); field = "" }
            else if c == "\n" { endRecord() }
            else if c != "\r" { field.unicodeScalars.append(c) }
        }
        if !field.isEmpty || !record.isEmpty { endRecord() }
        return rows
    }
}

/// GTFS-Realtime feedy PID (Golemio, veřejné bez tokenu).
enum PIDRealtime {
    struct StopTime { let stopId: String; let sequence: Int; let time: Int64?; let delay: Int64? }
    struct TripUpdate { let tripId: String; let routeId: String?; let startDate: String?; let delay: Int64?; let stops: [StopTime] }
    struct Vehicle { let tripId: String; let stopId: String?; let stopSequence: Int?; let status: Int?; let timestamp: Int64?; let speed: Float? }

    static func tripUpdates() async throws -> [TripUpdate] {
        let (d, _) = try await URLSession.shared.data(from: URL(string: "https://api.golemio.cz/v2/vehiclepositions/gtfsrt/trip_updates.pb")!)
        return PB.parse(d).msgs(2).compactMap { e in
            guard let tu = e.msg(3), let trip = tu.msg(1), let tid = trip.string(1) else { return nil }
            let stops = tu.msgs(2).map { s -> StopTime in
                let ev = s.msg(3) ?? s.msg(2)
                return StopTime(stopId: s.string(4) ?? "", sequence: Int(s.int(1) ?? 0), time: ev?.int(2), delay: ev?.int(1))
            }
            return TripUpdate(tripId: tid, routeId: trip.string(5), startDate: trip.string(3), delay: tu.int(5), stops: stops)
        }
    }

    static func vehicles() async throws -> [String: Vehicle] {
        let (d, _) = try await URLSession.shared.data(from: URL(string: "https://api.golemio.cz/v2/vehiclepositions/gtfsrt/vehicle_positions.pb")!)
        var out: [String: Vehicle] = [:]
        for e in PB.parse(d).msgs(2) {
            guard let v = e.msg(4), let tid = v.msg(1)?.string(1) else { continue }
            out[tid] = Vehicle(tripId: tid, stopId: v.string(7), stopSequence: v.int(3).map(Int.init), status: v.int(4).map(Int.init), timestamp: v.int(5), speed: v.msg(2)?.float(5))
        }
        return out
    }
}
