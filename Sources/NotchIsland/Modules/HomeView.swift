import SwiftUI

/// Domovská obrazovka: hudba | posuvný kalendář | počasí (styl Apple Počasí).
struct HomeView: View {
    var body: some View {
        HStack(spacing: 0) {
            MusicPane().frame(width: 270)
            divider
            CalendarPane().frame(maxWidth: .infinity)
            divider
            WeatherTile().frame(width: 150)
        }
    }
    private var divider: some View { Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1).padding(.vertical, 6).padding(.horizontal, 6) }
}

// MARK: - Hudba
struct MusicPane: View {
    @ObservedObject var music = MusicService.shared
    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Artwork(image: music.artwork, size: 78)
                    .id(music.artwork)
                    .transition(.opacity)
                if let n = music.now {
                    BrandBadge(glyph: n.source == .spotify ? FA.spotify : (n.source == .web ? (n.siteName.contains("YouTube") ? FA.youtube : (n.siteName.contains("Spotify") ? FA.spotify : FA.chrome)) : FA.apple),
                               color: n.source == .spotify || n.siteName.contains("Spotify") ? Color(hex: 0x1DB954) : (n.siteName.contains("YouTube") ? Color(hex: 0xFF0000) : (n.source == .web ? Color(hex: 0x4285F4) : Color(hex: 0xFC3C44))), size: 20)
                        .offset(x: 5, y: 5)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: music.artwork)
            VStack(alignment: .leading, spacing: 2) {
                if let n = music.now {
                    Text(n.title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                        .contentTransition(.opacity)
                    Text(n.album).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    Text(n.artist).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    HStack(spacing: 14) {
                        ctl("backward.end.fill", 9) { music.previous() }
                        ctl(n.isPlaying ? "pause.fill" : "play.fill", 12) { music.playPause() }
                        ctl("forward.end.fill", 9) { music.next() }
                        Spacer()
                        EqualizerView(active: n.isPlaying, bars: 4, color: .white.opacity(0.8)).frame(width: 16, height: 12)
                    }.padding(.top, 4)
                } else {
                    Text(L("Nic nehraje")).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    HStack(spacing: 6) {
                        FAIcon(FA.spotify, size: 11).foregroundStyle(Color(hex: 0x1DB954))
                        FAIcon(FA.apple, size: 11).foregroundStyle(.white.opacity(0.7))
                        Text(L("Spotify / Hudba")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(.leading, 4)
    }
    private func ctl(_ s: String, _ size: CGFloat, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: s).font(.system(size: size, weight: .bold)).foregroundStyle(.white) }.buttonStyle(.plain)
    }
}

// MARK: - Kalendář (týdny posouvatelné dvěma prsty / tažením, den kliknutím)
struct CalendarPane: View {
    @ObservedObject var cal = CalendarService.shared
    @State private var weekOffset: Int? = 0
    @State private var selected: Date = Calendar.current.startOfDay(for: Date())
    private let weeks = Array(-26...26)

    private func weekStart(_ offset: Int) -> Date {
        let c = Calendar.current
        let todayWeek = c.dateInterval(of: .weekOfYear, for: Date())!.start
        return c.date(byAdding: .weekOfYear, value: offset, to: todayWeek)!
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selected, format: .dateTime.month(.abbreviated)).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { weekOffset = 0; selected = Calendar.current.startOfDay(for: Date()) } }
                WeekPager(weekOffset: Binding(get: { weekOffset ?? 0 }, set: { weekOffset = $0 }), selected: $selected, weekStart: weekStart)
                .frame(height: 26)
            }
            if Calendar.current.isDateInToday(selected), BakalariService.shared.isConfigured, let line = nextLessonLine() {
                HStack(spacing: 5) {
                    Image(systemName: "graduationcap.fill").font(.system(size: 9)).foregroundStyle(.cyan)
                    Text(line).font(.system(size: 10, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                }
            }
            let list = cal.events(on: selected)
            if list.isEmpty {
                VStack(spacing: 2) {
                    Image(systemName: cal.hasAccess ? "calendar.badge.checkmark" : "calendar.badge.exclamationmark").font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
                    Text(cal.hasAccess ? (Calendar.current.isDateInToday(selected) ? L("Nic na dnešek") : L("Žádné události")) : L("Bez přístupu ke kalendáři"))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxHeight: .infinity).transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                VStack(spacing: 2) {
                    ForEach(list.prefix(2)) { e in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 1).fill(e.color.map { Color(cgColor: $0) } ?? .white).frame(width: 2, height: 12)
                            Text(e.title).font(.system(size: 10, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Text(e.allDay ? L("celý den") : e.start.formatted(date: .omitted, time: .shortened)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    if list.count > 2 { Text(String(format: L("+%d další"), list.count - 2)).font(.system(size: 8)).foregroundStyle(.white.opacity(0.4)) }
                }
                .frame(maxHeight: .infinity).id(selected).transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selected)
        .onChange(of: weekOffset) { _, w in
            guard let w else { return }
            // při přejetí na jiný týden vybrat stejný den v týdnu (nebo dnešek v aktuálním)
            let c = Calendar.current
            let target = w == 0 ? c.startOfDay(for: Date()) : c.date(byAdding: .day, value: c.component(.weekday, from: selected) - c.firstWeekday + 7 % 7, to: weekStart(w))!
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selected = c.startOfDay(for: target) }
        }
        .padding(.horizontal, 4)
    }
}

/// Pásek dnů: tažením (nebo dvěma prsty) se plynule posouvá a mění vybraný den – jako scrubování.
extension CalendarPane {
    func nextLessonLine() -> String? {
        let c = BakalariService.shared.current()
        let f = DateFormatter(); f.dateFormat = "H:mm"
        if let n = c.now { return "\(n.lesson.subjectAbbrev) · \(n.lesson.roomAbbrev ?? "") · " + L("do") + " \(f.string(from: n.end))" + (c.next.map { " → \($0.lesson.subjectAbbrev)" } ?? "") }
        if let n = c.next { let m = Int(n.start.timeIntervalSinceNow / 60); return L("Další:") + " \(n.lesson.subjectAbbrev) · \(n.lesson.roomAbbrev ?? "") · " + (m < 60 ? String(format: L("za %d min"), m) : f.string(from: n.start)) }
        return nil
    }
}

struct WeekPager: View {
    @Binding var weekOffset: Int      // ponecháno kvůli rozhraní, nepoužívá se
    @Binding var selected: Date
    let weekStart: (Int) -> Date
    @State private var drag: CGFloat = 0
    @State private var acc: CGFloat = 0
    private let visible = 7, span = 15
    var body: some View {
        GeometryReader { g in
            let dw = g.size.width / CGFloat(visible)
            let center = CGFloat(visible / 2)
            HStack(spacing: 0) {
                ForEach(-span...span, id: \.self) { i in
                    let d = Calendar.current.date(byAdding: .day, value: i, to: selected)!
                    DayCell(date: d, isSel: i == 0, width: dw) { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = d } }
                }
            }
            .offset(x: -CGFloat(span) * dw + center * dw + drag)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3)
                .onChanged { v in
                    let delta = v.translation.width - acc
                    drag += delta; acc = v.translation.width
                    // každých dw bodů = jeden den
                    while drag <= -dw { drag += dw; shift(1) }
                    while drag >= dw { drag -= dw; shift(-1) }
                }
                .onEnded { _ in acc = 0; withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = 0 } })
            .background(ScrollWheelCatcher { dx in
                drag += dx
                while drag <= -dw { drag += dw; shift(1) }
                while drag >= dw { drag -= dw; shift(-1) }
            } onEnd: { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = 0 } })
        }
        .frame(height: 26)
        .clipped()
    }
    private func shift(_ days: Int) {
        // posun výběru bez animace offsetu (pásek už je tažením na místě), zvýraznění se přelije animací
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { selected = Calendar.current.date(byAdding: .day, value: days, to: selected)! }
    }
}

/// Zachytí horizontální scroll (dva prsty) nad pásem dnů, kliky nechává projít.
struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    let onEnd: () -> Void
    func makeNSView(context: Context) -> V { let v = V(); v.onScroll = onScroll; v.onEnd = onEnd; return v }
    func updateNSView(_ v: V, context: Context) { v.onScroll = onScroll; v.onEnd = onEnd }
    final class V: NSView {
        var onScroll: ((CGFloat) -> Void)?; var onEnd: (() -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
                guard let self, let win = self.window, e.window == win else { return e }
                let p = self.convert(e.locationInWindow, from: nil)
                guard self.bounds.contains(p), abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) else { return e }
                self.onScroll?(e.scrollingDeltaX)
                if e.phase == .ended || e.momentumPhase == .ended { self.onEnd?() }
                return nil
            }
        }
    }
}

struct DayCell: View {
    let date: Date; let isSel: Bool; let width: CGFloat; let onTap: () -> Void
    var body: some View {
        let isToday = Calendar.current.isDateInToday(date)
        VStack(spacing: 1) {
            Text(date, format: .dateTime.weekday(.narrow)).font(.system(size: 7, weight: .semibold)).foregroundStyle(.white.opacity(isSel ? 0.9 : 0.35))
            Text(date, format: .dateTime.day(.twoDigits)).font(.system(size: isSel ? 13 : 11, weight: isSel ? .bold : .medium))
                .foregroundStyle(isSel ? (isToday ? Color(hex: 0x3B82F6) : .white) : .white.opacity(isToday ? 0.9 : 0.5))
        }
        .frame(width: width)
        .padding(.vertical, 1)
        .background(isSel ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSel)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct WeekStrip: View {
    let start: Date
    @Binding var selected: Date
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let d = Calendar.current.date(byAdding: .day, value: i, to: start)!
                let isToday = Calendar.current.isDateInToday(d)
                let isSel = Calendar.current.isDate(d, inSameDayAs: selected)
                VStack(spacing: 1) {
                    Text(d, format: .dateTime.weekday(.narrow)).font(.system(size: 7, weight: .semibold)).foregroundStyle(.white.opacity(isSel ? 0.9 : 0.35))
                    Text(d, format: .dateTime.day(.twoDigits)).font(.system(size: isSel ? 13 : 11, weight: isSel ? .bold : .medium))
                        .foregroundStyle(isSel ? (isToday ? Color(hex: 0x3B82F6) : .white) : .white.opacity(isToday ? 0.9 : 0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 1)
                .background(isSel ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selected = Calendar.current.startOfDay(for: d) } }
            }
        }
    }
}

// MARK: - Počasí (dlaždice jako widget Apple Počasí)
struct WeatherTile: View {
    @ObservedObject var w = WeatherService.shared
    @State private var showHours = false
    var body: some View {
        let code = w.now?.code ?? 2, isDay = w.now?.isDay ?? true
        let g = WeatherService.gradient(code, isDay: isDay)
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [Color(hex: g[0]), Color(hex: g[1])], startPoint: .top, endPoint: .bottom))
            if let n = w.now {
                if showHours, !w.hours.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(w.hours.prefix(4)) { h in
                            VStack(spacing: 2) {
                                Text(h.date, format: .dateTime.hour()).font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                                Image(systemName: WeatherService.symbol(h.code, isDay: h.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 12))
                                Text("\(Int(h.temp.rounded()))°").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            }.frame(maxWidth: .infinity)
                        }
                    }.padding(.horizontal, 4).transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(n.city.isEmpty ? L("Poloha") : n.city).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                            Spacer()
                            Image(systemName: "location.fill").font(.system(size: 7)).foregroundStyle(.white.opacity(0.7))
                        }
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(Int(n.temp.rounded()))°").font(.system(size: 26, weight: .light)).foregroundStyle(.white)
                                .contentTransition(.numericText())
                            Spacer()
                            Image(systemName: WeatherService.symbol(n.code, isDay: n.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 20)).padding(.top, 4)
                        }
                        Text(WeatherService.text(n.code)).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.95))
                        Text(String(format: L("N:%d° D:%d°"), Int(n.tMax.rounded()), Int(n.tMin.rounded()))).font(.system(size: 9)).foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(9).transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            } else {
                VStack(spacing: 3) {
                    Image(systemName: "location.slash").foregroundStyle(.white.opacity(0.7))
                    Text(w.error == nil ? L("Zjišťuji polohu…") : L("Bez dat")).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showHours)
        .onHover { showHours = $0 }
        .help(w.now.map { "\(WeatherService.text($0.code)), pocitově \(Int($0.feels.rounded()))°, vítr \(Int($0.wind)) km/h" } ?? L("Počasí podle polohy"))
    }
}
