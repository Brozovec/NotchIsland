import SwiftUI

struct SettingsView: View {
    @ObservedObject var s = AppSettings.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    var body: some View {
        ScrollView(showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
              VStack(spacing: 6) {
                section(L("Doprava")) {
                    field(L("Golemio token"), $s.golemioToken, secure: true)
                    note(L("S tokenem jdou odjezdy PID rychleji přes API, bez něj z veřejných dat (1× denně ~50 MB). RegioJet/FlixBus z jejich webu."))
                }
                section("Discord") {
                    field(L("Client ID"), $s.discordClientId)
                    field(L("Client Secret"), $s.discordClientSecret, secure: true)
                    note(L("discord.com/developers → New Application → OAuth2: přidej redirect http://localhost. Token se uloží automaticky."))
                    if !s.discordAccessToken.isEmpty { Button(L("Odhlásit Discord")) { s.discordAccessToken = "" }.font(.caption) }
                }
              }
              VStack(spacing: 6) {
                section(L("Obecné")) {
                    Toggle(isOn: $launchAtLogin) { Text(L("Spouštět po přihlášení")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)) }
                        .toggleStyle(.switch).controlSize(.mini)
                        .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.set(v); launchAtLogin = LaunchAtLogin.isEnabled }
                    note(L("Verze 1.0 · Adam Brož · github.com/adambroz/NotchIsland"))
                }
                section(L("Screenshoty")) {
                    field(L("Složka"), $s.screenshotFolder)
                    note(L("⌘⇧2 oblast · ⌘⇧1 obrazovka · ⌘⇧7 okno · ⌘⇧O text. Poprvé macOS požádá o Nahrávání obrazovky."))
                }
              }
            }
        }
    }
    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.9))
            c()
        }.padding(6).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
    private func field(_ label: String, _ b: Binding<String>, secure: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).frame(width: 70, alignment: .leading)
            Group { if secure { SecureField("", text: b) } else { TextField("", text: b) } }
                .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }
    private func note(_ t: String) -> some View { Text(t).font(.system(size: 8)).foregroundStyle(.white.opacity(0.45)) }
}
