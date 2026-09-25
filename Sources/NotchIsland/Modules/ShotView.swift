import SwiftUI

struct ShotView: View {
    @ObservedObject var s = ScreenshotService.shared
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                btn(L("Oblast"), "crop", "⌘⇧2") { s.capture(mode: .area) }
                btn(L("Obrazovka"), "rectangle.dashed", "⌘⇧1") { s.capture(mode: .screen) }
                btn(L("Okno"), "macwindow", "⌘⇧7") { s.capture(mode: .window) }
                btn(L("Text (OCR)"), "text.viewfinder", "⌘⇧O") { s.capture(mode: .ocr) }
            }
            .frame(width: 150)
            if s.shots.isEmpty {
                Placeholder(icon: "camera.viewfinder", title: L("Zatím žádné snímky"), text: L("Po snímku se otevře editor, snímek je ve schránce"))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(s.shots) { shot in ShotThumb(shot: shot) } }.padding(.vertical, 2)
                }
            }
        }
    }
    private func btn(_ t: String, _ i: String, _ k: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            HStack(spacing: 5) {
                Image(systemName: i).frame(width: 12); Text(t); Spacer(); Text(k).opacity(0.45)
            }
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).disabled(s.capturing)
    }
}

struct ShotThumb: View {
    let shot: Shot
    @ObservedObject var s = ScreenshotService.shared
    @State private var hover = false
    var body: some View {
        Image(nsImage: shot.image).resizable().aspectRatio(contentMode: .fill)
            .frame(width: 130, height: 88).clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2)))
            .overlay(alignment: .bottom) {
                if hover {
                    HStack(spacing: 5) {
                        act("doc.on.doc", "Kopírovat") { s.copy(shot.image) }
                        act("pin", "Připnout") { s.pin(shot.image) }
                        act("pencil.tip.crop.circle", "Upravit") { s.annotate(shot) }
                        act("folder", "Ve Finderu") { s.reveal(shot) }
                        act("trash", "Smazat") { s.delete(shot) }
                    }.padding(4).background(.black.opacity(0.7), in: Capsule()).padding(.bottom, 4)
                } else {
                    Text(shot.taken, style: .time).font(.system(size: 9)).foregroundStyle(.white).padding(3).background(.black.opacity(0.5), in: Capsule()).padding(4)
                }
            }
            .onDrag { NSItemProvider(object: shot.url as NSURL) }
            .onTapGesture(count: 2) { s.annotate(shot) }
            .onHover { hover = $0 }
    }
    private func act(_ i: String, _ h: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: i).font(.system(size: 10)).foregroundStyle(.white).frame(width: 16, height: 16) }.buttonStyle(.plain).help(h)
    }
}
