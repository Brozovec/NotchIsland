import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @ObservedObject var shelf = ShelfService.shared
    @State private var hovering = false
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(hovering ? 0.14 : 0.06))
                RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(.white.opacity(hovering ? 0.7 : 0.25))
                if shelf.items.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 18, weight: .light))
                        Text(L("Přetáhni sem soubory")).font(.system(size: 10))
                    }.foregroundStyle(.white.opacity(0.6))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(shelf.items, id: \.self) { url in ShelfItem(url: url) }
                        }.padding(8)
                    }
                }
                if !shelf.items.isEmpty {
                    Button { shelf.clear() } label: { Image(systemName: "xmark.bin").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).padding(5) }
                        .buttonStyle(.plain).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).help(L("Vyčistit"))
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $hovering) { shelf.handleDrop($0) }
        }
    }
}

struct ShelfItem: View {
    let url: URL
    @ObservedObject var shelf = ShelfService.shared
    @State private var hover = false
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 34, height: 34)
            Text(url.lastPathComponent).font(.system(size: 8)).foregroundStyle(.white.opacity(0.8)).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(width: 64, height: 62)
        .background(Color.white.opacity(hover ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { shelf.remove(url) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.8)) }
                    .buttonStyle(.plain).offset(x: 2, y: -2)
            }
        }
        .onHover { hover = $0 }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .help(url.lastPathComponent)
    }
}
