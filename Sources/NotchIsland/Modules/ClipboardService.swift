import AppKit
import Combine

struct ClipItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case text, image, file }
    let id: UUID
    let kind: Kind
    let text: String          // text / název souboru / popis obrázku
    let date: Date
    var pinned: Bool = false
    var imagePath: String? = nil   // PNG na disku (obrázky)
}

/// Historie schránky (jako Win+V): sleduje NSPasteboard, drží posledních 10 položek, text se ukládá na disk.
@MainActor
final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()
    /// Zavře notch po výběru položky (nastaví controller).
    static var closePanel: (() -> Void)?
    @Published private(set) var items: [ClipItem] = []
    @Published var query = ""
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var suppressNext = false
    private let dir: URL
    private let maxItems = 10   // nejstarší se mažou, připnuté se nepočítají

    private init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NotchIsland/Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: dir.appendingPathComponent("history.json")), let list = try? JSONDecoder().decode([ClipItem].self, from: d) { items = list }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    var filtered: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? items : items.filter { $0.text.lowercased().contains(q) }
        return base.sorted { ($0.pinned ? 1 : 0, $0.date) > ($1.pinned ? 1 : 0, $1.date) }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        if suppressNext { suppressNext = false; return }
        // hesla / citlivý obsah označený správci hesel přeskočit
        if pb.types?.contains(where: { $0.rawValue == "org.nspasteboard.ConcealedType" || $0.rawValue == "org.nspasteboard.TransientType" }) == true { return }
        var item: ClipItem?
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            item = ClipItem(id: UUID(), kind: .file, text: urls.map(\.lastPathComponent).joined(separator: ", "), date: Date(), imagePath: urls.first?.path)
        } else if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item = ClipItem(id: UUID(), kind: .text, text: String(s.prefix(20_000)), date: Date())
        } else if let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let path = dir.appendingPathComponent("\(UUID().uuidString).png")
            try? png.write(to: path)
            item = ClipItem(id: UUID(), kind: .image, text: "Obrázek \(Int(img.size.width))×\(Int(img.size.height))", date: Date(), imagePath: path.path)
        }
        guard let new = item else { return }
        // stejný obsah jako naposledy → jen posunout nahoru
        if let i = items.firstIndex(where: { $0.kind == new.kind && $0.text == new.text }) {
            var e = items.remove(at: i); e = ClipItem(id: e.id, kind: e.kind, text: e.text, date: Date(), pinned: e.pinned, imagePath: e.imagePath); items.insert(e, at: 0)
        } else {
            items.insert(new, at: 0)
        }
        trim(); save()
    }

    private func trim() {
        var keep: [ClipItem] = [], n = 0
        for it in items { if it.pinned || n < maxItems { keep.append(it); if !it.pinned { n += 1 } } else if let p = it.imagePath, it.kind == .image { try? FileManager.default.removeItem(atPath: p) } }
        items = keep
    }

    /// Vloží položku zpět do schránky (a posune ji nahoru).
    func copy(_ it: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch it.kind {
        case .text: pb.setString(it.text, forType: .string)
        case .image: if let p = it.imagePath, let img = NSImage(contentsOfFile: p) { pb.writeObjects([img]) }
        case .file: if let p = it.imagePath { pb.writeObjects([URL(fileURLWithPath: p) as NSURL]) }
        }
        suppressNext = true; lastChange = pb.changeCount
        if let i = items.firstIndex(of: it) { let e = items.remove(at: i); items.insert(ClipItem(id: e.id, kind: e.kind, text: e.text, date: Date(), pinned: e.pinned, imagePath: e.imagePath), at: 0); save() }
    }

    /// Klik = zkopírovat a rovnou vložit do aktivní aplikace (simulované ⌘V, vyžaduje Zpřístupnění).
    func paste(_ it: ClipItem) {
        copy(it)
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        guard trusted else {
            ScreenshotService.shared.showHUD(L("Povol NotchIsland ve Zpřístupnění, pak klik rovnou vkládá"), icon: "hand.raised.fill")
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            return
        }
        Self.closePanel?()
        // panel se zavře a klávesnice se vrátí předchozí aplikaci, pak ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)   // V
            let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }

    func togglePin(_ it: ClipItem) { if let i = items.firstIndex(of: it) { items[i].pinned.toggle(); save() } }
    func remove(_ it: ClipItem) { if it.kind == .image, let p = it.imagePath { try? FileManager.default.removeItem(atPath: p) }; items.removeAll { $0.id == it.id }; save() }
    func clear() { items.filter { !$0.pinned }.forEach { if $0.kind == .image, let p = $0.imagePath { try? FileManager.default.removeItem(atPath: p) } }; items.removeAll { !$0.pinned }; save() }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: dir.appendingPathComponent("history.json"), options: .atomic) }
    }
}
