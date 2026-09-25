import AppKit
import SwiftUI
import Combine

enum CompactMode: Equatable { case none, music, call }

@MainActor
final class NotchState: ObservableObject {
    /// Aktuální stav pro služby (obnovují data jen, když je to vidět).
    static var isExpanded = false
    static var visibleTab: NotchTab = .home
    static func isVisible(_ tab: NotchTab) -> Bool { isExpanded && visibleTab == tab }
    @Published var isExpanded = false { didSet { NotchState.isExpanded = isExpanded } }
    @Published var selectedTab: NotchTab = .home { didSet { NotchState.visibleTab = selectedTab } }
    @Published var compact: CompactMode = .none
    let geometry: NotchGeometry
    private var bag = Set<AnyCancellable>()

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        MusicService.shared.$now.combineLatest(CallsService.shared.$micInUse, CallsService.shared.$running)
            .map { now, mic, apps -> CompactMode in
                if mic && !apps.isEmpty { return .call }
                if let n = now, n.isPlaying { return .music }
                return .none
            }
            .removeDuplicates()
            .sink { [weak self] m in withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { self?.compact = m } }
            .store(in: &bag)
    }

    /// Šířka křídel po stranách notche ve sbaleném stavu.
    var wingWidth: CGFloat { compact == .none ? 0 : 74 }
    var collapsedSize: CGSize { CGSize(width: geometry.notchSize.width + 2 * wingWidth, height: geometry.notchSize.height) }
    var collapsedRect: CGRect { geometry.collapsedRect.insetBy(dx: -wingWidth, dy: 0) }
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home, files, transit, calls, shot, notes, clipboard, settings
    var id: String { rawValue }
    /// Záložky zobrazené jako pilulky (nastavení má vlastní ikonu vpravo).
    static let all: [NotchTab] = [.home, .files, .transit, .calls, .shot, .notes, .clipboard]
    static var pills: [NotchTab] { all.filter { $0 == .home || !AppSettings.shared.disabledTabs.contains($0.rawValue) } }
    var icon: String {
        switch self {
        case .home: return "house.fill"; case .files: return "tray.full.fill"; case .transit: return "tram.fill"
        case .calls: return "phone.fill"; case .shot: return "camera.fill"; case .notes: return "note.text"; case .clipboard: return "doc.on.clipboard"; case .settings: return "gearshape.fill"
        }
    }
    var title: String {
        switch self {
        case .home: return L("Island"); case .files: return L("Tray"); case .transit: return L("Doprava")
        case .calls: return L("Hovory"); case .shot: return L("Shot"); case .notes: return L("Poznámky"); case .clipboard: return L("Schránka"); case .settings: return L("Nastavení")
        }
    }
}

@MainActor
final class NotchController {
    private let geometry = NotchGeometry.detect()
    private let state: NotchState
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var collapseWork: DispatchWorkItem?
    private var pollTimer: Timer?
    private let cursorOverlay = NotchCursorOverlay()
    private var bag = Set<AnyCancellable>()

    init() {
        state = NotchState(geometry: geometry)
        panel = NotchPanel(frame: geometry.windowFrame)
        panel.contentView = FirstMouseHostingView(rootView: NotchRootView().environmentObject(state))
        panel.contentView?.addSubview(cursorOverlay, positioned: .above, relativeTo: nil)
        panel.acceptsMouseMovedEvents = true
        // Při změně křídel (hudba / hovor): okno nejdřív roztáhnout na větší z obou velikostí,
        // nechat doběhnout animaci a teprve pak zmenšit – jinak se animace usekne.
        state.$compact.dropFirst().removeDuplicates().sink { [weak self] _ in
            guard let self, !self.state.isExpanded else { return }
            let big = self.collapsedWindowFrame(wing: 74)
            self.panel.setFrame(big, display: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                guard let self, !self.state.isExpanded else { return }
                self.syncWindowFrame(); self.updateCursorZone()
            }
        }.store(in: &bag)
        installMouseMonitors()
        // rozběhnout služby
        _ = ShelfService.shared; _ = TransitService.shared; _ = IntercityService.shared; _ = WeatherService.shared
        _ = CalendarService.shared; _ = ScreenshotService.shared; _ = DiscordRPC.shared; _ = ClipboardService.shared
    }

    /// Otevře panel na dané záložce (globální zkratka).
    func open(tab: NotchTab) {
        state.selectedTab = tab
        if !state.isExpanded { setExpanded(true) }
        collapseWork?.cancel(); collapseWork = nil
    }

    func show() {
        syncWindowFrame()
        panel.orderFrontRegardless()
        updateCursorZone()
    }

    /// Sbaleno: okno je jen tak velké jako černý pruh, aby neblokovalo kliknutí do aplikací pod ním.
    /// Rozbaleno: okno má plnou velikost pro panel.
    private func syncWindowFrame(expanded: Bool? = nil) {
        let target: CGRect
        if expanded ?? state.isExpanded {
            target = geometry.windowFrame
        } else {
            target = collapsedWindowFrame(wing: state.wingWidth)
        }
        if panel.frame != target { panel.setFrame(target, display: true) }
    }

    private func collapsedWindowFrame(wing: CGFloat) -> CGRect {
        let r = geometry.collapsedRect.insetBy(dx: -wing, dy: 0)
        return CGRect(x: r.minX - 8, y: r.minY - 8, width: r.width + 16, height: r.height + 8) // rezerva na oušky a stín
    }

    /// Sbalený stav: celý černý pruh včetně křídel. Rozbalený stav: jen samotný výřez, aby šlo klikat na obsah.
    private func updateCursorZone() {
        cursorOverlay.setZone(state.isExpanded ? geometry.collapsedRect : state.collapsedRect)
    }

    private func installMouseMonitors() {
        // Polohu myši čteme přímo (30×/s) – události mouseMoved v oblasti výřezu nechodí spolehlivě
        // (kurzor pod kamerou macOS schovává), takže se panel dřív sbaloval, když jsi najel pod kameru.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handleMouseMoved() }
        }
        let down: (NSEvent) -> Void = { [weak self] _ in Task { @MainActor in self?.handleMouseDown() } }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: down) { monitors.append(m) }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] e in
            if let self, self.state.isExpanded, self.geometry.expandedRect.contains(NSEvent.mouseLocation) { self.panel.makeKeyAndOrderFront(nil) }
            return e
        } as Any)
    }

    private func handleMouseMoved() {
        let p = NSEvent.mouseLocation
        var hotRect = state.isExpanded ? geometry.expandedRect.insetBy(dx: -24, dy: -24) : state.collapsedRect.insetBy(dx: -6, dy: -2)
        // Nahoru bez limitu: pod kamerou / nad horní hranou se poloha hlásí nespolehlivě, ale pořád jsme "uvnitř".
        hotRect.size.height += 200
        if hotRect.contains(p) {
            collapseWork?.cancel(); collapseWork = nil
            if !state.isExpanded { setExpanded(true) }
        } else if state.isExpanded, collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in self?.collapseWork = nil; self?.setExpanded(false) }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func handleMouseDown() {
        if state.isExpanded, !geometry.expandedRect.contains(NSEvent.mouseLocation) { setExpanded(false) }
    }

    private func setExpanded(_ expanded: Bool) {
        if expanded {
            // Nejdřív zvětšit okno a nechat proběhnout layout – jinak SwiftUI animuje i posun středu
            // z malého okna do velkého a panel "přijede zleva".
            syncWindowFrame(expanded: true)
            panel.contentView?.layoutSubtreeIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { self.state.isExpanded = true }
                self.updateCursorZone()
            }
            return
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { state.isExpanded = false }
        do {
            panel.resignKey()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, !self.state.isExpanded else { return }
                self.syncWindowFrame(); self.updateCursorZone()
            }
        }
    }
}

/// Hosting view, které přijme první klik i když panel není aktivní (jinak by první klik jen "probudil" okno).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

/// Průhledný nonaktivující panel, který sedí přes výřez nad všemi okny.
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
