import Foundation

/// Lokalizace: klíče jsou české texty, překlady v Resources/Localizations/<lang>.lproj/Localizable.strings.
/// Když překlad chybí, zůstane čeština.
@inline(__always) func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}
