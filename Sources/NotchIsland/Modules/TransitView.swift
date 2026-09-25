import SwiftUI

struct TransitView: View {
    enum Mode: String, CaseIterable { case stop = "Zastávka", intercity = "Spojení" }
    @AppStorage("transitMode") private var modeRaw = Mode.stop.rawValue
    private var mode: Mode { Mode(rawValue: modeRaw) ?? .stop }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { modeRaw = m.rawValue } } label: {
                        HStack(spacing: 5) {
                            FAIcon(m == .stop ? FA.tram : FA.bus, size: 9, brand: false)
                            Text(m.rawValue)
                        }
                        .font(.system(size: 10, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(mode == m ? Color.white.opacity(0.16) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(mode == m ? .white : .white.opacity(0.5))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text(mode == .stop ? L("PID · živě") : L("RegioJet · FlixBus")).font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
            }
            .frame(width: 92)
            Group {
                switch mode {
                case .stop: StopBoardView()
                case .intercity: IntercityView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
}

// MARK: - Odjezdy ze zastávky (PID)
struct StopBoardView: View {
    @ObservedObject var t = TransitService.shared
    @ObservedObject var settings = AppSettings.shared
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                TextField(L("Zastávka (Anděl, Hlavní nádraží…)"), text: $t.stopQuery)
                    .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.white)
                    .onSubmit { t.clearSuggestions(); Task { await t.refresh() } }
                    .onChange(of: t.stopQuery) { _, v in Task { await t.suggest(v) } }
                Button { toggleFavorite() } label: {
                    Image(systemName: settings.favoriteStops.contains(t.stopQuery) ? "star.fill" : "star").font(.system(size: 10)).foregroundStyle(.yellow)
                }.buttonStyle(.plain).help(L("Oblíbená zastávka"))
                if t.loading { ProgressView().controlSize(.mini).tint(.white) }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            if !t.suggestions.isEmpty {
                SuggestionList(title: L("Zastávky"), items: t.suggestions) { name in t.clearSuggestions(); t.stopQuery = name; Task { await t.refresh() } }
            } else {
            if !settings.favoriteStops.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(settings.favoriteStops, id: \.self) { st in
                            Button(st) { t.stopQuery = st; Task { await t.refresh() } }
                                .buttonStyle(.plain).font(.system(size: 9, weight: st == t.stopQuery ? .bold : .regular)).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.white.opacity(st == t.stopQuery ? 0.18 : 0.08), in: Capsule()).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                        }
                    }
                }.frame(height: 16)
            }
            if let v = t.tracked { TrackedCard(v: v) { t.stopTracking() } }

            if !t.status.isEmpty {
                VStack(spacing: 3) { ProgressView().controlSize(.small).tint(.white); Text(t.status).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)) }.frame(maxHeight: .infinity)
            } else if let e = t.error, t.departures.isEmpty {
                Text(e).font(.system(size: 9)).foregroundStyle(.orange).multilineTextAlignment(.center).frame(maxHeight: .infinity)
            } else if t.departures.isEmpty {
                Text(t.stopQuery.isEmpty ? L("Zadej zastávku") : (t.resolvedStop.isEmpty ? L("Zastávku neznám") : L("Žádné odjezdy do 2 h"))).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).frame(maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(t.departures) { d in DepartureRow(d: d, tracked: d.tripId == t.trackedTripId) { t.track(d) } }
                    }
                }
            }
            }
        }
    }
    private func toggleFavorite() {
        let s = t.stopQuery.trimmingCharacters(in: .whitespaces); guard !s.isEmpty else { return }
        if let i = settings.favoriteStops.firstIndex(of: s) { settings.favoriteStops.remove(at: i) } else { settings.favoriteStops.append(s) }
    }
}

/// Návrhy při psaní – zobrazují se místo výsledků (překryv by zůstal schovaný pod nativním scrollem).
struct SuggestionList: View {
    let title: String; let items: [String]; let pick: (String) -> Void
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased()).font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.35)).padding(.horizontal, 8).padding(.top, 2)
                ForEach(items, id: \.self) { name in
                    Button { pick(name) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right").font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
                            Text(name).font(.system(size: 11)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct LineBadge: View {
    let line: String; let mode: TransitMode
    var body: some View {
        HStack(spacing: 3) {
            FAIcon(mode.fa, size: 8, brand: false)
            Text(line).font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
        .background(Color(hex: mode.colorHex), in: RoundedRectangle(cornerRadius: 5))
        .frame(minWidth: 46)
    }
}

struct DepartureRow: View {
    let d: Departure; let tracked: Bool; let onTrack: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            LineBadge(line: d.line, mode: d.mode)
            VStack(alignment: .leading, spacing: 0) {
                Text(d.headsign).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 6) {
                    Text(d.scheduled, style: .time)
                    if !d.platform.isEmpty { Text(L("nást.") + " \(d.platform)") }
                }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if d.delayMin > 0 { Text("+\(d.delayMin)′").font(.system(size: 10, weight: .semibold)).foregroundStyle(.red) }
            else { Text(L("včas")).font(.system(size: 9)).foregroundStyle(.green.opacity(0.8)) }
            Text(d.minutes == 0 ? L("teď") : "\(d.minutes) min").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white).frame(width: 44, alignment: .trailing)
            Button(action: onTrack) { Image(systemName: tracked ? "location.fill" : "location").font(.system(size: 10)).foregroundStyle(tracked ? .cyan : .white.opacity(hover ? 0.9 : 0.3)) }
                .buttonStyle(.plain).help(L("Sledovat spoj"))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.white.opacity(hover ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 6))
        .onHover { hover = $0 }
    }
}

struct TrackedCard: View {
    let v: TrackedVehicle; let onStop: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill").font(.system(size: 10)).foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(v.line).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    Text("→ \(v.headsign)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Text("\(v.lastStop)  ▸  \(v.nextStop)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(v.delayMin > 0 ? "+\(v.delayMin) min" : L("včas")).font(.system(size: 10, weight: .semibold)).foregroundStyle(v.delayMin > 0 ? .red : .green)
                HStack(spacing: 4) {
                    if let s = v.speed { Text("\(Int(s)) km/h") }
                    Text(v.updated, style: .relative)
                }.font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
            }
            Button(action: onStop) { Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4).background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Spojení RegioJet / FlixBus (+ ČD přes IDOS)
struct IntercityView: View {
    @ObservedObject var s = IntercityService.shared
    @ObservedObject var settings = AppSettings.shared
    @State private var focus: Field? = nil   // pole, do kterého se naposledy psalo
    enum Field { case from, to }
    private var routeKey: String { "\(s.from.trimmingCharacters(in: .whitespaces))|\(s.to.trimmingCharacters(in: .whitespaces))" }
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                field(L("Odkud"), $s.from, .from)
                Button { let f = s.from; s.from = s.to; s.to = f; Task { await s.search() } } label: { Image(systemName: "arrow.left.arrow.right").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
                field(L("Kam"), $s.to, .to)
                Button { toggleFavorite() } label: {
                    Image(systemName: settings.favoriteRoutes.contains(routeKey) ? "star.fill" : "star").font(.system(size: 10)).foregroundStyle(.yellow)
                }.buttonStyle(.plain).help(L("Oblíbená trasa"))
                Button { Task { await s.search() } } label: {
                    Group { if s.loading { ProgressView().controlSize(.mini).tint(.white) } else { Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .bold)) } }
                        .frame(width: 24, height: 20).background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.white)
                }.buttonStyle(.plain)
                Button { if let u = s.idosURL() { NSWorkspace.shared.open(u) } } label: {
                    Text(L("ČD · IDOS")).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(height: 20).background(Color(hex: 0x0A3D91), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).help(L("Vlaky ČD a všechny spoje na IDOS"))
            }

            if !s.suggestions.isEmpty, focus != nil {
                SuggestionList(title: focus == .from ? L("Odkud") : L("Kam"), items: s.suggestions) { pick($0) }
            } else {
            // oblíbené trasy – jedním klikem
            if !settings.favoriteRoutes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(settings.favoriteRoutes, id: \.self) { r in
                            let p = r.split(separator: "|").map(String.init)
                            if p.count == 2 {
                                Button("\(p[0]) → \(p[1])") { s.from = p[0]; s.to = p[1]; Task { await s.search() } }
                                    .buttonStyle(.plain).font(.system(size: 9, weight: r == routeKey ? .bold : .regular)).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.white.opacity(r == routeKey ? 0.18 : 0.08), in: Capsule()).foregroundStyle(.white.opacity(0.9))
                            }
                        }
                    }
                }.frame(height: 16)
            }
            if let t = s.tracked { TrackedConnectionCard(c: t) { s.track(nil) } }
            if s.results.isEmpty {
                VStack(spacing: 3) {
                    HStack(spacing: 8) { CarrierBadge(carrier: .regiojet, isTrain: false); CarrierBadge(carrier: .flixbus, isTrain: false) }
                    Text(s.error ?? L("Zadej odkud a kam, hledá dnešní spoje")).font(.system(size: 9)).foregroundStyle(s.error == nil ? .white.opacity(0.5) : .orange).multilineTextAlignment(.center)
                }.frame(maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) { ForEach(s.results) { c in ConnectionRow(c: c, tracked: s.tracked?.id == c.id, onTrack: { s.track(c) }, onBuy: { if let u = s.ticketURL(c) { NSWorkspace.shared.open(u) } }) } }
                }
            }
            }
        }
    }
    private func field(_ ph: String, _ b: Binding<String>, _ f: Field) -> some View {
        TextField(ph, text: b).textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.white)
            .onSubmit { focus = nil; s.clearSuggestions(); Task { await s.search() } }
            .onChange(of: b.wrappedValue) { _, v in focus = f; Task { await s.suggest(v) } }
            .padding(.horizontal, 8).padding(.vertical, 3).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    private func pick(_ name: String) {
        s.clearSuggestions()
        if focus == .from { s.from = name; focus = nil } else { s.to = name; focus = nil; Task { await s.search() } }
    }
    private func toggleFavorite() {
        guard !s.from.isEmpty, !s.to.isEmpty else { return }
        if let i = settings.favoriteRoutes.firstIndex(of: routeKey) { settings.favoriteRoutes.remove(at: i) } else { settings.favoriteRoutes.append(routeKey) }
    }
}

/// Sledovaný spoj (sedím v něm): živé zpoždění, zbývající čas do příjezdu.
struct TrackedConnectionCard: View {
    let c: Connection; let onStop: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill").font(.system(size: 10)).foregroundStyle(.cyan)
            CarrierBadge(carrier: c.carrier, isTrain: c.isTrain)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(c.from) → \(c.to)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 4) {
                    Text(L("odj. ")) + Text(c.departure, style: .time)
                    Text(L("· příj. ")) + Text(c.arrival.addingTimeInterval(Double(c.delayMin ?? 0) * 60), style: .time)
                }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text((c.delayMin ?? 0) > 0 ? "+\(c.delayMin!) min" : (c.departure > Date() ? L("před odjezdem") : L("jede včas"))).font(.system(size: 10, weight: .semibold)).foregroundStyle((c.delayMin ?? 0) > 0 ? .red : .green)
                if c.arrival > Date() { Text(L("do cíle ")) .font(.system(size: 8)).foregroundStyle(.white.opacity(0.4)) + Text(c.arrival.addingTimeInterval(Double(c.delayMin ?? 0) * 60), style: .relative).font(.system(size: 8)).foregroundStyle(.white.opacity(0.4)) }
            }
            Button(action: onStop) { Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4).background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CarrierBadge: View {
    let carrier: Connection.Carrier; let isTrain: Bool
    var body: some View {
        HStack(spacing: 3) {
            FAIcon(isTrain ? FA.train : FA.bus, size: 8, brand: false)
            Text(carrier == .regiojet ? "RegioJet" : "FlixBus").font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(carrier == .regiojet ? .black : .white).padding(.horizontal, 5).padding(.vertical, 2)
        .background(carrier == .regiojet ? Color(hex: 0xFFD200) : Color(hex: 0x73D700), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct ConnectionRow: View {
    let c: Connection
    var tracked = false
    var onTrack: () -> Void = {}
    var onBuy: () -> Void = {}
    @State private var hover = false
    private var running: Bool { c.departure <= Date() && c.arrival >= Date() }
    var body: some View {
        HStack(spacing: 8) {
            CarrierBadge(carrier: c.carrier, isTrain: c.isTrain).frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(c.departure, style: .time).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    Text("→").foregroundStyle(.white.opacity(0.4))
                    Text(c.arrival, style: .time).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                    Text(dur).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    if c.transfers > 0 { Text(String(format: L("· %d přestup"), c.transfers)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)) }
                }
                Text("\(c.from) → \(c.to)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                if running {
                    HStack(spacing: 3) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text(c.delayMin.map { $0 > 0 ? "+\($0) min" : L("jede včas") } ?? L("na cestě")).font(.system(size: 9, weight: .semibold)).foregroundStyle(c.delayMin ?? 0 > 0 ? .red : .green)
                    }
                } else if let d = c.delayMin, d > 0 {
                    Text("+\(d) min").font(.system(size: 9, weight: .semibold)).foregroundStyle(.red)
                }
                HStack(spacing: 4) {
                    if let f = c.freeSeats { Text(f == 0 ? L("vyprodáno") : "\(f) míst").foregroundStyle(f == 0 ? .red.opacity(0.9) : .white.opacity(0.5)) }
                    if let p = c.price { Text("\(Int(p)) Kč").foregroundStyle(.white) }
                }.font(.system(size: 9))
            }
            Button(action: onBuy) { Image(systemName: "cart.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(hover ? 0.9 : 0.35)) }.buttonStyle(.plain).help(L("Koupit jízdenku"))
            Button(action: onTrack) { Image(systemName: tracked ? "location.fill" : "location").font(.system(size: 10)).foregroundStyle(tracked ? .cyan : .white.opacity(hover ? 0.9 : 0.35)) }.buttonStyle(.plain).help(L("Sedím v tomhle spoji – sledovat"))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.white.opacity(hover ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 6))
        .onHover { hover = $0 }
    }
    private var dur: String { let m = Int(c.duration / 60); return "\(m / 60):\(String(format: "%02d", m % 60)) h" }
}

extension Color {
    init(hex: UInt) { self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255) }
}
