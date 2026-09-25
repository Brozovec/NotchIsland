import SwiftUI

struct CallsView: View {
    @ObservedObject var calls = CallsService.shared
    @ObservedObject var discord = DiscordRPC.shared
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: calls.micInUse ? "mic.fill" : "mic.slash").foregroundStyle(calls.micInUse ? .green : .white.opacity(0.4))
                Text(calls.onCall ? L("Probíhá hovor") : (calls.micInUse ? L("Mikrofon je aktivní") : L("Žádný hovor")))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                if calls.running.isEmpty {
                    Text(L("Žádná hovorová appka neběží")).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                } else {
                    HStack(spacing: 4) {
                        ForEach(calls.running) { app in
                            HStack(spacing: 4) {
                                if let g = app.fa { FAIcon(g, size: 9) } else { Image(systemName: app.icon).font(.system(size: 8)) }
                                Text(app.name)
                            }
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color(hex: app.color).opacity(0.85), in: Capsule())
                        }
                    }
                }
            }
            .frame(width: 190, alignment: .leading).padding(8).frame(maxHeight: .infinity).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 6) {
                HStack {
                    FAIcon(FA.discord, size: 12).foregroundStyle(Color(hex: 0x5865F2))
                    Text(discord.channelName.map { "Discord · \($0)" } ?? "Discord").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    if discord.authorized {
                        Button { discord.toggleMute() } label: { Image(systemName: discord.selfMuted ? "mic.slash.fill" : "mic.fill").foregroundStyle(discord.selfMuted ? .red : .white) }.buttonStyle(.plain)
                        Button { discord.toggleDeaf() } label: { Image(systemName: discord.selfDeaf ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundStyle(discord.selfDeaf ? .red : .white) }.buttonStyle(.plain)
                    }
                }
                if discord.users.isEmpty {
                    Text(discord.status).font(.caption).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(discord.users) { u in
                                VStack(spacing: 3) {
                                    ZStack(alignment: .bottomTrailing) {
                                        AsyncImage(url: u.avatarURL) { $0.resizable() } placeholder: { Circle().fill(Color.white.opacity(0.15)) }
                                            .frame(width: 30, height: 30).clipShape(Circle())
                                        if u.muted || u.deaf {
                                            Image(systemName: u.deaf ? "speaker.slash.fill" : "mic.slash.fill").font(.system(size: 8)).padding(3).background(Color.red, in: Circle()).foregroundStyle(.white)
                                        }
                                    }
                                    Text(u.name).font(.system(size: 9)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                                }.frame(width: 48)
                            }
                        }.padding(.horizontal, 4)
                    }
                }
            }
            .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
