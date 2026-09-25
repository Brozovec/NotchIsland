import Foundation
import Combine

/// Uživatelské nastavení (UserDefaults). Klíče a tokeny zadává uživatel sám v záložce Nastavení.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var golemioToken: String { didSet { d.set(golemioToken, forKey: "golemioToken") } }
    @Published var disabledTabs: [String] { didSet { d.set(disabledTabs, forKey: "disabledTabs") } }
    @Published var favoriteRoutes: [String] { didSet { d.set(favoriteRoutes, forKey: "favoriteRoutes") } }
    @Published var discordClientId: String { didSet { d.set(discordClientId, forKey: "discordClientId") } }
    @Published var discordClientSecret: String { didSet { d.set(discordClientSecret, forKey: "discordClientSecret") } }
    @Published var discordAccessToken: String { didSet { d.set(discordAccessToken, forKey: "discordAccessToken") } }
    @Published var favoriteStops: [String] { didSet { d.set(favoriteStops, forKey: "favoriteStops") } }
    @Published var screenshotFolder: String { didSet { d.set(screenshotFolder, forKey: "screenshotFolder") } }

    private init() {
        golemioToken = d.string(forKey: "golemioToken") ?? ""
        disabledTabs = d.stringArray(forKey: "disabledTabs") ?? []
        favoriteRoutes = d.stringArray(forKey: "favoriteRoutes") ?? ["Praha|Brno"]
        discordClientId = d.string(forKey: "discordClientId") ?? ""
        discordClientSecret = d.string(forKey: "discordClientSecret") ?? ""
        discordAccessToken = d.string(forKey: "discordAccessToken") ?? ""
        favoriteStops = d.stringArray(forKey: "favoriteStops") ?? ["Anděl"]
        screenshotFolder = d.string(forKey: "screenshotFolder") ?? (NSHomeDirectory() + "/Pictures/NotchIsland")
    }
}
