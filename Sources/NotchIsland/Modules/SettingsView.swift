import SwiftUI

struct SettingsView: View {
    @ObservedObject var s = AppSettings.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var bkPassword = Keychain.read("bakalariPassword")
    @ObservedObject var bk = BakalariService.shared
    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
              Group {
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
                    note(L("Verze 1.0 · Adam Brož · github.com/brozovec/NotchIsland"))
                }
                section(L("Moduly")) {
                    FlowLayout(spacing: 6) {
                        ForEach(NotchTab.all.filter { $0 != .home }) { tab in
                            let on = !s.disabledTabs.contains(tab.rawValue)
                            Button {
                                if on { s.disabledTabs.append(tab.rawValue) } else { s.disabledTabs.removeAll { $0 == tab.rawValue } }
                            } label: {
                                HStack(spacing: 3) { Image(systemName: tab.icon).font(.system(size: 9, weight: .bold)); Text(tab.title).font(.system(size: 9, weight: .semibold)).lineLimit(1).fixedSize() }
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(on ? Color.white.opacity(0.18) : Color.white.opacity(0.05), in: Capsule())
                                    .foregroundStyle(on ? .white : .white.opacity(0.35))
                            }.buttonStyle(.plain)
                        }
                    }
                    note(L("Kliknutím záložku skryješ nebo zase ukážeš."))
                }
                section(L("Bakaláři (rozvrh)")) {
                    field(L("Server"), $s.bakalariServer)
                    field(L("Jméno"), $s.bakalariUser)
                    HStack {
                        Text(L("Heslo")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).frame(width: 90, alignment: .leading)
                        SecureField("", text: $bkPassword).textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                            .onChange(of: bkPassword) { _, v in Keychain.save(v, "bakalariPassword") }
                    }
                    HStack(spacing: 6) {
                        Button(L("Přihlásit a načíst třídy")) { Task { await BakalariService.shared.loadClasses() } }.font(.system(size: 10)).controlSize(.mini)
                        if bk.loading { ProgressView().controlSize(.mini).tint(.white) }
                        if !bk.classes.isEmpty {
                            Picker("", selection: $s.bakalariClass) { ForEach(bk.classes) { c in Text(c.name).tag(c.id) } }.controlSize(.mini).frame(width: 90)
                                .onChange(of: s.bakalariClass) { _, _ in Task { await BakalariService.shared.refresh(force: true) } }
                        } else if !s.bakalariClass.isEmpty {
                            Text(s.bakalariClass).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        }
                        Picker("", selection: $s.bakalariGroup) { Text(L("vše")).tag(0); Text("1.sk").tag(1); Text("2.sk").tag(2) }.pickerStyle(.segmented).controlSize(.mini).frame(width: 110)
                    }
                    note(bk.status.isEmpty ? L("Heslo je v Klíčence. Po přihlášení vyber třídu a skupinu, rozvrh se obnovuje každých 30 min.") : bk.status)
                }
                section(L("Screenshoty")) {
                    field(L("Složka"), $s.screenshotFolder)
                    note(L("⌘⇧2 oblast · ⌘⇧1 obrazovka · ⌘⇧7 okno · ⌘⇧O text. Poprvé macOS požádá o Nahrávání obrazovky."))
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.9))
            c()
        }.padding(6).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
    private func field(_ label: String, _ b: Binding<String>, secure: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).frame(width: 90, alignment: .leading)
            Group { if secure { SecureField("", text: b) } else { TextField("", text: b) } }
                .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }
    private func note(_ t: String) -> some View { Text(t).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)) }
}


/// Zalamovaná řada (jako CSS flex-wrap).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
