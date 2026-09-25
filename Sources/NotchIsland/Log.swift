import Foundation

/// Jednoduchý log do ~/Library/Logs/NotchIsland.log (pro ladění bez Xcode).
enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NotchIsland.log")
    private static let q = DispatchQueue(label: "notch.log")
    private static let f: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
    static func w(_ s: String) {
        let line = "\(f.string(from: Date())) \(s)\n"
        q.async {
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
            else { try? line.write(to: url, atomically: true, encoding: .utf8) }
        }
    }
}
