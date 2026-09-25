import Foundation

/// Minimalistický dekodér protobuf wire formátu (stačí pro GTFS-Realtime).
enum PB {
    enum Value { case varint(UInt64), fixed64(UInt64), bytes(Data), fixed32(UInt32) }
    typealias Message = [Int: [Value]]

    static func parse(_ d: Data) -> Message {
        var m = Message(); var i = d.startIndex
        func varint() -> UInt64? {
            var r: UInt64 = 0, s: UInt64 = 0
            while i < d.endIndex { let b = d[i]; i += 1; r |= UInt64(b & 0x7F) << s; if b & 0x80 == 0 { return r }; s += 7; if s > 63 { return nil } }
            return nil
        }
        while i < d.endIndex {
            guard let key = varint() else { break }
            let field = Int(key >> 3), wt = key & 7
            switch wt {
            case 0: guard let v = varint() else { return m }; m[field, default: []].append(.varint(v))
            case 1: guard i + 8 <= d.endIndex else { return m }; m[field, default: []].append(.fixed64(d[i..<i+8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) })); i += 8
            case 2: guard let l = varint(), i + Int(l) <= d.endIndex else { return m }; m[field, default: []].append(.bytes(d[i..<i+Int(l)])); i += Int(l)
            case 5: guard i + 4 <= d.endIndex else { return m }; m[field, default: []].append(.fixed32(d[i..<i+4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })); i += 4
            default: return m
            }
        }
        return m
    }
}

extension PB.Message {
    func int(_ f: Int) -> Int64? { if case .varint(let v)? = self[f]?.first { return Int64(bitPattern: v) }; return nil }
    func string(_ f: Int) -> String? { if case .bytes(let d)? = self[f]?.first { return String(data: d, encoding: .utf8) }; return nil }
    func float(_ f: Int) -> Float? { if case .fixed32(let v)? = self[f]?.first { return Float(bitPattern: v) }; return nil }
    func msg(_ f: Int) -> PB.Message? { if case .bytes(let d)? = self[f]?.first { return PB.parse(d) }; return nil }
    func msgs(_ f: Int) -> [PB.Message] { (self[f] ?? []).compactMap { if case .bytes(let d) = $0 { return PB.parse(d) }; return nil } }
}
