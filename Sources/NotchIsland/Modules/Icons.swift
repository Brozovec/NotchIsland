import SwiftUI
import CoreText

/// Font Awesome 6 Free (Brands + Solid) – registrace fontů z bundle a pohodlné ikony.
enum FA {
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else { return }
        for f in ["fa-brands-400.ttf", "fa-solid-900.ttf"] {
            CTFontManagerRegisterFontsForURL(dir.appendingPathComponent(f) as CFURL, .process, nil)
        }
    }
    // Brands
    static let spotify = "\u{f1bc}", apple = "\u{f179}", discord = "\u{f392}", youtube = "\u{f167}", slack = "\u{f198}"
    static let microsoft = "\u{f3ca}", google = "\u{f1a0}", chrome = "\u{f268}", github = "\u{f09b}", telegram = "\u{f2c6}", whatsapp = "\u{f232}"
    // Solid
    static let bus = "\u{f207}", train = "\u{f238}", tram = "\u{f7da}", subway = "\u{f239}", ship = "\u{e4ea}", video = "\u{f03d}"
    static let phone = "\u{f095}", cloud = "\u{f0c2}", sun = "\u{f185}", snow = "\u{f2dc}", bolt = "\u{f0e7}", rain = "\u{f73d}"
}

struct FAIcon: View {
    let glyph: String
    var size: CGFloat = 12
    var brand = true
    init(_ glyph: String, size: CGFloat = 12, brand: Bool = true) { self.glyph = glyph; self.size = size; self.brand = brand }
    var body: some View {
        Text(glyph).font(.custom(brand ? "Font Awesome 6 Brands" : "Font Awesome 6 Free Solid", size: size))
    }
}

/// Barevná značka dopravce / aplikace.
struct BrandBadge: View {
    let glyph: String; let color: Color; var size: CGFloat = 18; var brand = true
    var body: some View {
        FAIcon(glyph, size: size * 0.55, brand: brand).foregroundStyle(.white)
            .frame(width: size, height: size).background(color, in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}
