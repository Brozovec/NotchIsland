import SwiftUI

/// Rychlé poznámky: jeden zápisník, ukládá se průběžně do Application Support, ⌘⇧C zkopíruje vše.
@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()
    @Published var text: String { didSet { scheduleSave() } }
    private let url: URL
    private var saveWork: DispatchWorkItem?
    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NotchIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("notes.txt")
        text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [url, text] in try? text.write(to: url, atomically: true, encoding: .utf8) }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }
}

struct NotesView: View {
    @ObservedObject var notes = NotesStore.shared
    @State private var copied = false
    var body: some View {
        ZStack(alignment: .topTrailing) {
            TextEditor(text: $notes.text)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            if notes.text.isEmpty {
                Text(L("Rychlá poznámka… ukládá se sama")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.35)).padding(.top, 11).padding(.leading, 11)
                    .frame(maxWidth: .infinity, alignment: .leading).allowsHitTesting(false)
            }
            HStack(spacing: 6) {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(notes.text, forType: .string); copied = true
                         DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false } } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }.buttonStyle(.plain).help(L("Zkopírovat vše"))
                Button { notes.text = "" } label: { Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)) }.buttonStyle(.plain).help(L("Smazat"))
            }.padding(8)
        }
    }
}
