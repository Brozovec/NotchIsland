import AppKit
import Combine
import UniformTypeIdentifiers

/// Odkladiště souborů – kopie souborů žijí v Application Support, dají se odsud táhnout dál.
@MainActor
final class ShelfService: ObservableObject {
    static let shared = ShelfService()
    @Published private(set) var items: [URL] = []
    let folder: URL

    private init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchIsland/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        items = urls.sorted { (a, b) in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
    }

    func add(_ url: URL) {
        var dest = folder.appendingPathComponent(url.lastPathComponent)
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(n).\(url.pathExtension)")
            n += 1
        }
        try? FileManager.default.copyItem(at: url, to: dest)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: dest.path)
        reload()
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                var url: URL?
                if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                if let url { Task { @MainActor in self.add(url) } }
            }
        }
        return handled
    }

    func remove(_ url: URL) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil); reload() }
    func clear() { items.forEach { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) }; reload() }
}
