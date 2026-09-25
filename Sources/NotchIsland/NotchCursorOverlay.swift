import AppKit

/// Překrytí nad černou oblastí výřezu. Když je nad ním myš, nastaví průhledný (neviditelný) kurzor,
/// při odjetí vrátí šipku. Funguje přes tracking area i když appka není aktivní – jako NotchNook.
final class NotchCursorOverlay: NSView {
    static let blankCursor: NSCursor = {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus(); NSColor.clear.set(); NSRect(x: 0, y: 0, width: 1, height: 1).fill(); img.unlockFocus()
        return NSCursor(image: img, hotSpot: .zero)
    }()
    private var inside = false

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func cursorUpdate(with event: NSEvent) { Self.blankCursor.set() }
    override func mouseEntered(with event: NSEvent) { inside = true; Self.blankCursor.set() }
    override func mouseExited(with event: NSEvent) { inside = false; NSCursor.arrow.set() }
    override func mouseMoved(with event: NSEvent) { if inside { Self.blankCursor.set() } }

    /// Kliknutí propouštíme dál na obsah pod překrytím.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Nastaví oblast (v souřadnicích obrazovky) a znovu vyhodnotí kurzor podle aktuální polohy myši.
    func setZone(_ screenRect: CGRect) {
        guard let win = window else { return }
        var r = screenRect
        r.origin.x -= win.frame.origin.x
        r.origin.y -= win.frame.origin.y
        r.size.height += 100 // až nad horní hranu obrazovky – pod kamerou se poloha hlásí nespolehlivě
        frame = r
        updateTrackingAreas()
        let nowInside = r.contains(win.mouseLocationOutsideOfEventStream)
        if nowInside != inside { inside = nowInside; (inside ? Self.blankCursor : NSCursor.arrow).set() }
    }
}
