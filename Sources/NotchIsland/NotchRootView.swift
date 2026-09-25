import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        let g = state.geometry
        let size = state.isExpanded ? g.expandedSize : state.collapsedSize
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(bottomRadius: state.isExpanded ? 26 : (state.compact == .none ? 12 : 16), topRadius: state.isExpanded ? 12 : 6)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(state.isExpanded || state.compact != .none ? 0.45 : 0), radius: 14, y: 6)
                if state.isExpanded {
                    ExpandedContent()
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else if state.compact != .none {
                    CompactContent(mode: state.compact, notchWidth: g.notchSize.width, wing: state.wingWidth)
                        .frame(width: size.width, height: size.height)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.6)).animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.12)),
                                                removal: .opacity.combined(with: .scale(scale: 0.7)).animation(.easeOut(duration: 0.18))))
                }
            }
            .frame(width: size.width, height: size.height)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: state.compact)
            .contentShape(Rectangle())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Sbalený stav s "křídly" vedle kamery – hraje hudba / probíhá hovor.
struct CompactContent: View {
    let mode: CompactMode
    let notchWidth: CGFloat
    let wing: CGFloat
    @ObservedObject var music = MusicService.shared
    @ObservedObject var calls = CallsService.shared
    var body: some View {
        HStack(spacing: 0) {
            Group {
                switch mode {
                case .music:
                    Artwork(image: music.artwork, size: 22).padding(.leading, 12)
                        .id(music.artwork).transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .animation(.easeInOut(duration: 0.25), value: music.artwork)
                case .call:
                    Group {
                        if let g = calls.running.first?.fa { FAIcon(g, size: 12) } else { Image(systemName: "phone.fill") }
                    }.foregroundStyle(.green).padding(.leading, 14)
                case .none: EmptyView()
                }
            }.frame(width: wing, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            Group {
                switch mode {
                case .music: EqualizerView(active: music.now?.isPlaying ?? false, bars: 4, color: .green).frame(width: 18, height: 16).padding(.trailing, 14)
                case .call:
                    HStack(spacing: 4) {
                        Circle().fill(calls.micInUse ? Color.green : .red).frame(width: 6, height: 6)
                        Text(calls.running.first?.name ?? "").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    }.padding(.trailing, 12)
                case .none: EmptyView()
                }
            }.frame(width: wing, alignment: .trailing)
        }
    }
}

/// Tvar notche: navrch přisátý k hraně obrazovky, dole kulatý, s malými "oušky" nahoře.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var topRadius: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set { bottomRadius = newValue.first; topRadius = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX - topRadius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + topRadius), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - bottomRadius))
        p.addQuadCurve(to: CGPoint(x: r.minX + bottomRadius, y: r.maxY), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - bottomRadius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - bottomRadius), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + topRadius))
        p.addQuadCurve(to: CGPoint(x: r.maxX + topRadius, y: r.minY), control: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct ExpandedContent: View {
    @EnvironmentObject var state: NotchState
    @ObservedObject var settings = AppSettings.shared

    private func tabPill(_ tab: NotchTab) -> some View {
        let on = state.selectedTab == tab
        return Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { state.selectedTab = tab } } label: {
            HStack(spacing: 3) {
                Image(systemName: tab.icon).font(.system(size: 10, weight: .bold))
                if on { Text(tab.title).font(.system(size: 10, weight: .semibold)).fixedSize() }
            }
            .padding(.horizontal, on ? 9 : 7).padding(.vertical, 4)
            .background(on ? Color.white.opacity(0.16) : .clear, in: Capsule())
            .foregroundStyle(on ? .white : .white.opacity(0.45))
        }
        .buttonStyle(.plain).help(tab.title)
    }

    var body: some View {
        let wing = (state.geometry.expandedSize.width - state.geometry.notchSize.width) / 2
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                // všechny záložky v levém křídle, pod kamerou nic
                HStack(spacing: 5) { ForEach(NotchTab.pills) { tabPill($0) } }
                    .padding(.leading, 12)
                    .frame(width: wing, alignment: .leading)
                    .clipped()
                Color.clear.frame(width: state.geometry.notchSize.width)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Button { withAnimation(.easeOut(duration: 0.15)) { state.selectedTab = .settings } } label: {
                        Image(systemName: "gearshape.fill").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(state.selectedTab == .settings ? .white : .white.opacity(0.45))
                    }.buttonStyle(.plain)
                }
                .padding(.leading, 14).padding(.trailing, 14)
                .frame(width: wing)
            }
            .padding(.top, 8)
            Group {
                switch state.selectedTab {
                case .home: HomeView()
                case .files: FilesView()
                case .transit: TransitView()
                case .calls: CallsView()
                case .shot: ShotView()
                case .notes: NotesView()
                case .clipboard: ClipboardView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }
}

struct Placeholder: View {
    let icon: String, title: String, text: String
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 18, weight: .light)).foregroundStyle(.white.opacity(0.8))
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            Text(text).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
