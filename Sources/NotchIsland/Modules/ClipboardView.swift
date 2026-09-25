import SwiftUI

struct ClipboardView: View {
    @ObservedObject var c = ClipboardService.shared
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                TextField(L("Hledat ve schránce…"), text: $c.query).textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.white)
                Text("⌘⇧V").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                if !c.items.isEmpty {
                    Button { c.clear() } label: { Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)) }.buttonStyle(.plain).help(L("Vymazat historii (připnuté zůstanou)"))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 3).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            if c.filtered.isEmpty {
                Placeholder(icon: "doc.on.clipboard", title: L("Historie schránky"), text: L("Cokoli zkopíruješ, objeví se tady. Klik = zkopírovat zpět."))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) { ForEach(c.filtered) { ClipRow(it: $0) } }
                }
            }
        }
    }
}

struct ClipRow: View {
    let it: ClipItem
    @ObservedObject var c = ClipboardService.shared
    @State private var hover = false
    @State private var flash = false
    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch it.kind {
                case .text: Image(systemName: "text.alignleft").foregroundStyle(.white.opacity(0.6))
                case .file: Image(nsImage: NSWorkspace.shared.icon(forFile: it.imagePath ?? "")).resizable().frame(width: 16, height: 16)
                case .image:
                    if let p = it.imagePath, let img = NSImage(contentsOfFile: p) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 28, height: 20).clipShape(RoundedRectangle(cornerRadius: 4)) }
                    else { Image(systemName: "photo") }
                }
            }.font(.system(size: 11)).frame(width: 28)
            Text(it.text.replacingOccurrences(of: "\n", with: " ⏎ ")).font(.system(size: 11)).foregroundStyle(.white).lineLimit(1)
            Spacer()
            Text(it.date, style: .relative).font(.system(size: 8)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
            if hover || it.pinned {
                Button { c.togglePin(it) } label: { Image(systemName: it.pinned ? "pin.fill" : "pin").font(.system(size: 9)).foregroundStyle(it.pinned ? .yellow : .white.opacity(0.6)) }.buttonStyle(.plain).help(L("Připnout"))
            }
            if hover {
                Button { c.remove(it) } label: { Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background((flash ? Color.green.opacity(0.25) : Color.white.opacity(hover ? 0.1 : 0.04)), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            c.copy(it)
            withAnimation(.easeOut(duration: 0.15)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation { flash = false }; ClipboardService.closePanel?() }
        }
        .help(it.text.prefix(300).description)
    }
}
