import AppKit
import SwiftUI

/// Editor ve stylu Shottr. Nástroje písmeny: A šipka, R obdélník, O ovál, P pero, T text, B rozmazání, C počítadlo.
/// ⌘C kopírovat, ⌘S uložit, ⌘P připnout, ⌘Z zpět, ⌘⇧Z znovu, Esc zavřít.
final class AnnotationWindow: NSWindow {
    init(shot: Shot) {
        let s = shot.image.size
        let scr = NSScreen.main?.visibleFrame ?? .zero
        let k = min(1, (scr.width - 120) / s.width, (scr.height - 160) / s.height)
        super.init(contentRect: CGRect(x: 0, y: 0, width: max(560, s.width * k + 40), height: s.height * k + 92),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        title = shot.url.lastPathComponent
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        center()
        contentView = NSHostingView(rootView: AnnotationEditor(shot: shot, close: { [weak self] in self?.close() }))
    }
    override func cancelOperation(_ sender: Any?) { close() }
}

enum Tool: String, CaseIterable {
    case arrow, rect, oval, pen, text, blur, counter
    var icon: String {
        switch self { case .arrow: return "arrow.up.right"; case .rect: return "rectangle"; case .oval: return "oval"; case .pen: return "pencil.tip"
        case .text: return "textformat"; case .blur: return "eye.slash"; case .counter: return "1.circle" }
    }
    var key: KeyEquivalent { switch self { case .arrow: return "a"; case .rect: return "r"; case .oval: return "o"; case .pen: return "p"; case .text: return "t"; case .blur: return "b"; case .counter: return "c" } }
    var name: String { switch self { case .arrow: return L("Šipka"); case .rect: return L("Obdélník"); case .oval: return L("Ovál"); case .pen: return L("Pero"); case .text: return L("Text"); case .blur: return L("Rozmazat"); case .counter: return L("Počítadlo") } }
}
struct Stroke: Identifiable { let id = UUID(); var tool: Tool; var points: [CGPoint]; var color: Color; var text: String = ""; var number = 0 }

struct AnnotationEditor: View {
    let shot: Shot
    let close: () -> Void
    @State private var tool: Tool = .arrow
    @State private var color: Color = .red
    @State private var strokes: [Stroke] = []
    @State private var redo: [Stroke] = []
    @State private var current: Stroke?
    @State private var textInput = ""
    @State private var textPoint: CGPoint?
    @State private var toast = ""
    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .white, .black]
    private var counterNext: Int { (strokes.filter { $0.tool == .counter }.map(\.number).max() ?? 0) + 1 }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ForEach(Tool.allCases, id: \.self) { t in
                    Button { tool = t } label: { Image(systemName: t.icon).frame(width: 24, height: 20) }
                        .buttonStyle(.bordered).tint(tool == t ? .accentColor : .secondary)
                        .keyboardShortcut(t.key, modifiers: []).help("\(t.name) (\(String(t.key.character).uppercased()))")
                }
                Divider().frame(height: 18)
                ForEach(colors, id: \.self) { c in
                    Circle().fill(c).frame(width: 14, height: 14).overlay(Circle().stroke(Color.primary.opacity(color == c ? 0.9 : 0.15), lineWidth: 2)).onTapGesture { color = c }
                }
                Divider().frame(height: 18)
                Button { if let s = strokes.popLast() { redo.append(s) } } label: { Image(systemName: "arrow.uturn.backward") }.keyboardShortcut("z", modifiers: .command).disabled(strokes.isEmpty).help(L("Zpět ⌘Z"))
                Button { if let s = redo.popLast() { strokes.append(s) } } label: { Image(systemName: "arrow.uturn.forward") }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(redo.isEmpty).help(L("Znovu ⌘⇧Z"))
                Spacer()
                Text(toast).font(.caption).foregroundStyle(.secondary)
                Button(L("Kopírovat")) { if let i = render() { ScreenshotService.shared.copy(i); toast = "Zkopírováno" } }.keyboardShortcut("c", modifiers: .command)
                Button(L("Připnout")) { if let i = render() { ScreenshotService.shared.pin(i); close() } }.keyboardShortcut("p", modifiers: .command)
                Button(L("Uložit")) { save() }.keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12).padding(.top, 26)
            GeometryReader { g in
                let fit = fitRect(in: g.size)
                canvas.frame(width: fit.width, height: fit.height).position(x: fit.midX, y: fit.midY)
            }
            .padding(.horizontal, 12).padding(.bottom, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func fitRect(in size: CGSize) -> CGRect {
        let s = shot.image.size
        let k = min(size.width / s.width, size.height / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private var canvas: some View {
        GeometryReader { g in
            let sz = g.size
            ZStack {
                Image(nsImage: shot.image).resizable()
                Canvas { ctx, _ in for s in strokes + (current.map { [$0] } ?? []) { draw(s, in: &ctx, size: sz) } }
                if let p = textPoint {
                    TextField(L("Text…"), text: $textInput, onCommit: {
                        if !textInput.isEmpty { strokes.append(Stroke(tool: .text, points: [p], color: color, text: textInput)) }
                        textInput = ""; textPoint = nil
                    })
                    .textFieldStyle(.roundedBorder).frame(width: 180).position(x: p.x * sz.width + 90, y: p.y * sz.height)
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let p = CGPoint(x: v.location.x / sz.width, y: v.location.y / sz.height)
                if tool == .text || tool == .counter { return }
                if current == nil { current = Stroke(tool: tool, points: [p], color: color) }
                else if tool == .pen { current?.points.append(p) } else { current?.points = [current!.points[0], p] }
            }.onEnded { v in
                let p = CGPoint(x: v.location.x / sz.width, y: v.location.y / sz.height)
                if tool == .text { textPoint = p; return }
                if tool == .counter { strokes.append(Stroke(tool: .counter, points: [p], color: color, number: counterNext)); redo = []; return }
                if let c = current, c.points.count > 1 { strokes.append(c); redo = [] }
                current = nil
            })
        }
    }

    private func draw(_ s: Stroke, in ctx: inout GraphicsContext, size: CGSize) {
        let pts = s.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let lw = max(2, size.width / 300)
        func box() -> CGRect? { guard pts.count == 2 else { return nil }; return CGRect(x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y), width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y)) }
        switch s.tool {
        case .pen:
            var p = Path(); p.addLines(pts); ctx.stroke(p, with: .color(s.color), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        case .rect:
            guard let r = box() else { return }; ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(s.color), lineWidth: lw)
        case .oval:
            guard let r = box() else { return }; ctx.stroke(Path(ellipseIn: r), with: .color(s.color), lineWidth: lw)
        case .blur:
            guard let r = box(), let pix = pixelated(rect: CGRect(x: r.minX / size.width, y: r.minY / size.height, width: r.width / size.width, height: r.height / size.height)) else { return }
            ctx.draw(Image(nsImage: pix).interpolation(.none), in: r)
        case .arrow:
            guard pts.count == 2 else { return }
            var p = Path(); p.move(to: pts[0]); p.addLine(to: pts[1])
            let a = atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x), hl = lw * 5
            p.move(to: pts[1]); p.addLine(to: CGPoint(x: pts[1].x - hl * cos(a - .pi / 6), y: pts[1].y - hl * sin(a - .pi / 6)))
            p.move(to: pts[1]); p.addLine(to: CGPoint(x: pts[1].x - hl * cos(a + .pi / 6), y: pts[1].y - hl * sin(a + .pi / 6)))
            ctx.stroke(p, with: .color(s.color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        case .text:
            guard let p = pts.first else { return }
            ctx.draw(ctx.resolve(Text(s.text).font(.system(size: max(12, size.width / 40), weight: .bold)).foregroundColor(s.color)), at: p, anchor: .leading)
        case .counter:
            guard let p = pts.first else { return }
            let r = lw * 5
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(s.color))
            ctx.draw(ctx.resolve(Text("\(s.number)").font(.system(size: r * 1.2, weight: .bold)).foregroundColor(.white)), at: p)
        }
    }

    /// Výřez originálu (souřadnice 0…1) zmenšený na hrubé bloky – pixelizace.
    private func pixelated(rect: CGRect) -> NSImage? {
        guard let cg = shot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let px = CGRect(x: rect.minX * CGFloat(cg.width), y: rect.minY * CGFloat(cg.height), width: rect.width * CGFloat(cg.width), height: rect.height * CGFloat(cg.height)).integral
        guard px.width >= 1, px.height >= 1, let crop = cg.cropping(to: px) else { return nil }
        let bw = max(1, Int(px.width / 14)), bh = max(1, Int(px.height / 14))
        guard let c = CGContext(data: nil, width: bw, height: bh, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.interpolationQuality = .low
        c.draw(crop, in: CGRect(x: 0, y: 0, width: bw, height: bh))
        guard let small = c.makeImage() else { return nil }
        return NSImage(cgImage: small, size: NSSize(width: bw, height: bh))
    }

    @MainActor private func render() -> NSImage? {
        let size = shot.image.size
        let view = ZStack {
            Image(nsImage: shot.image).resizable()
            Canvas { ctx, _ in for s in strokes { draw(s, in: &ctx, size: size) } }
        }.frame(width: size.width, height: size.height)
        let r = ImageRenderer(content: view)
        r.scale = shot.image.representations.first.map { CGFloat($0.pixelsWide) / size.width } ?? 2
        return r.nsImage
    }

    private func save() {
        guard let img = render(), let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let url = strokes.isEmpty ? shot.url : shot.url.deletingPathExtension().appendingPathExtension("anotace.png")
        try? png.write(to: url)
        toast = "Uloženo: \(url.lastPathComponent)"
        ScreenshotService.shared.showHUD(L("Uloženo"), icon: "checkmark.circle.fill")
        close()
    }
}
