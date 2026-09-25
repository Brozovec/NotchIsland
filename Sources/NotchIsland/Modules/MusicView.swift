import SwiftUI

struct MusicView: View {
    @ObservedObject var music = MusicService.shared
    var body: some View {
        if let n = music.now {
            HStack(spacing: 16) {
                Artwork(image: music.artwork, size: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(n.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    Text(n.source.rawValue).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    ProgressBar(progress: n.durationSec > 0 ? n.positionSec / n.durationSec : 0)
                    HStack(spacing: 4) {
                        Text(fmt(n.positionSec)); Spacer(); Text(fmt(n.durationSec))
                    }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    HStack(spacing: 22) {
                        ctl("backward.fill") { music.previous() }
                        ctl(n.isPlaying ? "pause.fill" : "play.fill", size: 20) { music.playPause() }
                        ctl("forward.fill") { music.next() }
                    }.frame(maxWidth: .infinity)
                }
                EqualizerView(active: n.isPlaying, bars: 6).frame(width: 46, height: 60)
            }
            .padding(.horizontal, 6)
        } else {
            Placeholder(icon: "music.note", title: L("Nic nehraje"), text: L("Pusť něco ve Spotify nebo Hudbě"))
        }
    }
    private func ctl(_ s: String, size: CGFloat = 15, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: s).font(.system(size: size, weight: .bold)).foregroundStyle(.white) }.buttonStyle(.plain)
    }
    private func fmt(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

struct Artwork: View {
    let image: NSImage?; let size: CGFloat
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else { ZStack { Color.white.opacity(0.1); Image(systemName: "music.note").foregroundStyle(.white.opacity(0.5)) } }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.18))
    }
}

struct ProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Color.white).frame(width: max(0, min(1, progress)) * g.size.width)
            }
        }.frame(height: 4)
    }
}

/// Animovaný equalizer. Zatím vizualizace synchronizovaná na stav přehrávání (bez reálné analýzy zvuku).
struct EqualizerView: View {
    let active: Bool
    var bars: Int = 5
    var color: Color = .white
    @State private var levels: [CGFloat] = []
    @State private var tick = 0
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule().fill(color)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(y: levels.indices.contains(i) ? levels[i] : 0.15, anchor: .bottom)
            }
        }
        .onAppear { levels = Array(repeating: 0.15, count: bars) }
        .onReceive(timer) { _ in
            guard active || levels.contains(where: { $0 > 0.12 }) else { return }   // v klidu nic nepřekreslovat
            withAnimation(.easeInOut(duration: 0.12)) {
                levels = (0..<bars).map { _ in active ? CGFloat.random(in: 0.15...1.0) : 0.12 }
            }
        }
    }
}
