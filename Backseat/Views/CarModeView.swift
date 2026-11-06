import SwiftUI

/// Landscape layout for passengers: oversized controls and one-tap channel switching.
struct CarModeView: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 20) {
                ZStack {
                    PlayerLayerView(player: player.player)
                    VisualizerLayer()
                    PlaybackStatusOverlay(large: true)
                    if player.externalPlaybackActive {
                        VStack(spacing: 10) {
                            Image(systemName: "airplayvideo").font(.system(size: 56))
                            Text("Playing on the car screen").font(.title2.bold())
                        }
                        .foregroundStyle(Theme.accent)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture { player.togglePlay() }

                controls
                    .frame(width: max(340, geo.size.width * 0.45))
            }
            .padding(16)
        }
        .onAppear { Orientation.request(.landscape) }
        .onDisappear { Orientation.request(.portrait) }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.name ?? "").font(.system(size: 24, weight: .bold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.6)
                    Text(player.current?.group ?? "").font(.headline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                BigButton(symbol: "xmark", label: "Exit car mode", size: 52) { player.carMode = false }
                AirPlayButton().frame(width: 52, height: 52)
                    .background(Theme.card, in: Circle())
                    .accessibilityLabel("AirPlay")
            }
            HStack(spacing: 10) {
                if !player.isLive {
                    BigButton(symbol: "gobackward.30", label: "Back 30 seconds", size: 46) { player.seek(by: -30) }
                }
                BigButton(symbol: "backward.end.fill", label: "Previous channel", size: 62) { player.previous() }
                    .disabled(!player.hasPrevious)
                BigButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Play",
                          size: 78, prominent: true) { player.togglePlay() }
                BigButton(symbol: "forward.end.fill", label: "Next channel", size: 62) { player.next() }
                    .disabled(!player.hasNext)
                if !player.isLive {
                    BigButton(symbol: "goforward.30", label: "Forward 30 seconds", size: 46) { player.seek(by: 30) }
                }
            }
            .frame(maxWidth: .infinity)

            if !player.isLive {
                Text(timeText).font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            channelStrip
        }
    }

    private var timeText: String {
        func f(_ s: Double) -> String {
            let t = Int(max(0, s))
            return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
        }
        return "\(f(player.currentTime)) / \(f(player.duration))"
    }

    /// Nearby entries only, so a 50,000-channel playlist stays fast.
    private var nearby: [Channel] {
        let q = player.queue
        guard let key = player.current?.key, let i = q.firstIndex(where: { $0.key == key }) else { return Array(q.prefix(40)) }
        return Array(q[max(0, i - 20)..<min(q.count, i + 21)])
    }

    private var channelStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(nearby) { ch in
                        let isCurrent = player.current?.key == ch.key
                        Button { player.play(ch, present: false) } label: {
                            VStack(spacing: 6) {
                                ChannelLogo(url: ch.logoURL, name: ch.name, size: 44)
                                Text(ch.name).font(.callout.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 6)
                            .frame(width: 112, height: 96)
                            .background(isCurrent ? Theme.accent.opacity(0.3) : Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isCurrent ? Theme.accent : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .id(ch.key)
                    }
                }
            }
            .frame(height: 100)
            .onAppear { if let k = player.current?.key { proxy.scrollTo(k, anchor: .center) } }
            .onChange(of: player.current?.key) { _, k in withAnimation { if let k { proxy.scrollTo(k, anchor: .center) } } }
        }
    }
}

struct BigButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 72
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .frame(width: size, height: size)
                .background(prominent ? Theme.accent : Theme.card, in: Circle())
                .foregroundStyle(prominent ? .black : .white)
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
