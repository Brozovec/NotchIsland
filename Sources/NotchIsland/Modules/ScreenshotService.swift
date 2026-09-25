import AppKit
import Carbon
import Combine
import Vision
import SwiftUI

struct Shot: Identifiable { let id = UUID(); let url: URL; let image: NSImage; let taken: Date }

/// Screenshoty ve stylu Shottr.
/// Globální zkratky: ⌘⇧1 celá obrazovka, ⌘⇧2 výběr oblasti, ⌘⇧7 okno, ⌘⇧O rozpoznat text (OCR) z oblasti.
/// Po snímku se otevře editor (jako v Shottru), snímek je ve schránce a v historii v notchi.
@MainActor
final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()
    @Published private(set) var shots: [Shot] = []
    @Published private(set) var capturing = false
    @Published private(set) var lastOCR = ""
    private var hotKeys: [EventHotKeyRef?] = []
    private var pins: [PinWindow] = []
    private var editors: [AnnotationWindow] = []
    private var hud: HUDWindow?

    enum Mode: UInt32 { case screen = 1, area = 2, window = 3, ocr = 4, clipboard = 5 }
    static let bindings: [(Mode, UInt32, String)] = [
        (.screen, UInt32(kVK_ANSI_1), "⌘⇧1"), (.area, UInt32(kVK_ANSI_2), "⌘⇧2"),
        (.window, UInt32(kVK_ANSI_7), "⌘⇧7"), (.ocr, UInt32(kVK_ANSI_O), "⌘⇧O"), (.clipboard, UInt32(kVK_ANSI_V), "⌘⇧V"),
    ]

    private init() {
        registerHotKeys()
        // ladicí spouštěč: `distnoted` zpráva cz.adambroz.notchisland.capture s objektem "area|screen|window|ocr"
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("cz.adambroz.notchisland.capture"), object: nil, queue: .main) { [weak self] n in
            let m: Mode = ["screen": .screen, "window": .window, "ocr": .ocr][n.object as? String ?? "area"] ?? .area
            Task { @MainActor in self?.capture(mode: m) }
        }
    }

    var folder: URL {
        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/NotchIsland", isDirectory: true)
        let raw = AppSettings.shared.screenshotFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = raw.isEmpty ? fallback : URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        do { try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u }
        catch {
            Log.w("složka \(u.path) nejde vytvořit (\(error.localizedDescription)) – používám \(fallback.path)")
            AppSettings.shared.screenshotFolder = fallback.path
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
    }

    /// Bez oprávnění Nahrávání obrazovky screencapture vrací prázdný snímek. Vyžádáme ho a otevřeme správné místo v Nastavení.
    private func ensureScreenAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        _ = CGRequestScreenCaptureAccess()
        showHUD(L("Povol NotchIsland v Nahrávání obrazovky"), icon: "exclamationmark.shield")
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        return false
    }

    private func registerHotKeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let st = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let raw = id.id
            Task { @MainActor in if let m = Mode(rawValue: raw) { ScreenshotService.shared.capture(mode: m) } }
            return noErr
        }, 1, &eventType, nil, nil)
        Log.w("hotkey handler installed status=\(st)")
        for (mode, key, label) in Self.bindings {
            var ref: EventHotKeyRef?
            let r = RegisterEventHotKey(key, UInt32(cmdKey | shiftKey), EventHotKeyID(signature: OSType(0x4E544348), id: mode.rawValue), GetApplicationEventTarget(), 0, &ref)
            Log.w("register \(label) (\(mode)) status=\(r)")
            hotKeys.append(ref)
        }
    }

    /// Volá se při ⌘⇧V – otevře historii schránky v notchi.
    var openClipboard: (() -> Void)?

    func capture(mode: Mode) {
        if mode == .clipboard { openClipboard?(); return }
        Log.w("capture(\(mode)) capturing=\(capturing) screenAccess=\(CGPreflightScreenCaptureAccess())")
        guard !capturing, ensureScreenAccess() else { return }
        capturing = true
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'v' HH.mm.ss"
        let isOCR = mode == .ocr
        let url = isOCR ? FileManager.default.temporaryDirectory.appendingPathComponent("notchisland-ocr.png")
                        : folder.appendingPathComponent("Snímek \(f.string(from: Date())).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var args = ["-x"]
        switch mode { case .area, .ocr: args.append("-i"); case .window: args += ["-i", "-W"]; case .screen, .clipboard: break }
        args.append(url.path)
        p.arguments = args
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.capturing = false
                Log.w("screencapture exit=\(proc.terminationStatus) file=\(FileManager.default.fileExists(atPath: url.path)) \(url.lastPathComponent)")
                guard let img = NSImage(contentsOf: url) else { Log.w("no image"); return }
                if isOCR { self?.recognizeText(img) } else { self?.didCapture(img, url: url) }
            }
        }
        do { try p.run(); Log.w("screencapture started args=\(args)") } catch { capturing = false; Log.w("screencapture failed to start: \(error)") }
    }

    private func didCapture(_ img: NSImage, url: URL) {
        let shot = Shot(url: url, image: img, taken: Date())
        shots.insert(shot, at: 0)
        if shots.count > 12 { shots.removeLast() }
        copy(img, fileURL: url)
        showHUD(L("Zkopírováno do schránky"), icon: "doc.on.clipboard.fill")
    }

    private func recognizeText(_ img: NSImage) {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let req = VNRecognizeTextRequest { [weak self] r, _ in
            let lines = (r.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
            let text = lines.joined(separator: "\n")
            Task { @MainActor in
                self?.lastOCR = text
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                self?.showHUD(text.isEmpty ? L("Žádný text nenalezen") : String(format: L("Text zkopírován (%d ř.)"), lines.count), icon: "text.viewfinder")
            }
        }
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["cs-CZ", "en-US"]
        req.usesLanguageCorrection = true
        DispatchQueue.global(qos: .userInitiated).async { try? VNImageRequestHandler(cgImage: cg).perform([req]) }
    }

    func showHUD(_ text: String, icon: String) {
        hud?.close()
        let h = HUDWindow(text: text, icon: icon); hud = h; h.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.hud?.close(); self?.hud = nil }
    }

    /// Do schránky dáme PNG i TIFF (a u snímku i soubor), aby ⌘V fungovalo v Discordu, Safari, Finderu i Slacku.
    func copy(_ img: NSImage, fileURL: URL? = nil) {
        let pb = NSPasteboard.general
        pb.clearContents()
        var item = NSPasteboardItem()
        if let tiff = img.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
            if let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { item.setData(png, forType: .png) }
        }
        pb.writeObjects([item])
        if let fileURL { item = NSPasteboardItem(); pb.writeObjects([fileURL as NSURL]) }
    }
    func pin(_ image: NSImage) { let w = PinWindow(image: image); pins.append(w); w.makeKeyAndOrderFront(nil) }
    func annotate(_ shot: Shot) { let w = AnnotationWindow(shot: shot); editors.append(w); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func reveal(_ shot: Shot) { NSWorkspace.shared.activateFileViewerSelecting([shot.url]) }
    func delete(_ shot: Shot) { try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil); shots.removeAll { $0.id == shot.id } }
}

/// Malá potvrzovací bublina pod notchem.
final class HUDWindow: NSPanel {
    init(text: String, icon: String) {
        let scr = NSScreen.main?.frame ?? .zero
        super.init(contentRect: CGRect(x: scr.midX - 130, y: scr.maxY - 90, width: 260, height: 34), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar; isOpaque = false; backgroundColor = .clear; hasShadow = true; isReleasedWhenClosed = false
        contentView = NSHostingView(rootView:
            HStack(spacing: 6) { Image(systemName: icon); Text(text).lineLimit(1) }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 34).frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.9), in: Capsule()))
    }
}

/// Plovoucí připnutý obrázek: táhnutí myší, dvojklik nebo Esc zavře, ⌘C zkopíruje, kolečko mění velikost.
final class PinWindow: NSPanel {
    private let image: NSImage
    init(image: NSImage) {
        self.image = image
        let screen = NSScreen.main?.visibleFrame ?? .zero
        var size = image.size
        let k = min(1, screen.width * 0.4 / size.width, screen.height * 0.4 / size.height)
        size = CGSize(width: size.width * k, height: size.height * k)
        let mouse = NSEvent.mouseLocation
        super.init(contentRect: CGRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2, width: size.width, height: size.height),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        level = .floating; isMovableByWindowBackground = true; hasShadow = true; backgroundColor = .clear; isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = NSImageView(image: image); v.imageScaling = .scaleProportionallyUpOrDown
        v.wantsLayer = true; v.layer?.cornerRadius = 8; v.layer?.masksToBounds = true
        v.layer?.borderWidth = 1; v.layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        contentView = v; isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { true }
    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { close() }
        else if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "c" { let i = image; Task { @MainActor in ScreenshotService.shared.copy(i) } }
        else { super.keyDown(with: e) }
    }
    override func mouseDown(with e: NSEvent) { if e.clickCount == 2 { close() } else { super.mouseDown(with: e) } }
    override func scrollWheel(with e: NSEvent) {
        let k = 1 + e.scrollingDeltaY * 0.01
        var f = frame; let c = CGPoint(x: f.midX, y: f.midY)
        f.size.width = max(80, f.width * k); f.size.height = max(60, f.height * k)
        f.origin = CGPoint(x: c.x - f.width / 2, y: c.y - f.height / 2)
        setFrame(f, display: true)
    }
}
