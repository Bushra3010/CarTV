import SwiftUI

struct PlayerScreen: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        Group {
            if player.carMode { CarModeView() } else { StandardPlayerView() }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(player.carMode)
    }
}

/// Audio visualizer for streams with no picture.
struct VisualizerLayer: View {
    @Environment(PlayerController.self) private var player
    @Environment(Purchases.self) private var purchases
    @AppStorage("visualizerStyle") private var styleRaw = VisualizerStyle.bars.rawValue

    var body: some View {
        let chosen = VisualizerStyle(rawValue: styleRaw) ?? .bars
        let style = chosen.isPro && !purchases.isPro ? .bars : chosen
        if player.isAudioOnly, style != .off, player.errorMessage == nil {
            AudioVisualizer(style: style, isPlaying: player.isPlaying, title: player.current?.name ?? "")
        }
    }
}

struct PlaybackStatusOverlay: View {
    @Environment(PlayerController.self) private var player
    var large = false

    var body: some View {
        if let error = player.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(large ? .largeTitle : .title2).foregroundStyle(.yellow)
                Text(error).font(large ? .title3 : .callout).multilineTextAlignment(.center)
                HStack {
                    Button("Retry") { player.retry() }.buttonStyle(.borderedProminent)
                    if player.hasNext { Button("Next channel") { player.next() }.buttonStyle(.bordered) }
                }
                .controlSize(large ? .large : .regular)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.75))
        } else if player.isBuffering {
            ProgressView().controlSize(.large).tint(.white).allowsHitTesting(false)
        }
    }
}

struct StandardPlayerView: View {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var store
    @Environment(Purchases.self) private var purchases
    @State private var showPaywall = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 0) {
                if !landscape { topBar }
                ZStack {
                    SystemPlayerView(player: player.player) {
                        VisualizerLayer().environment(player).environment(purchases)
                    }
                    PlaybackStatusOverlay()
                }
                .frame(width: geo.size.width, height: landscape ? geo.size.height : geo.size.width * 9 / 16)
                if !landscape {
                    controls
                    upNext
                }
            }
        }
        .ignoresSafeArea(edges: .horizontal)
        .sheet(isPresented: $showPaywall) { PaywallView(reason: "Car mode is part of Backseat Pro.") }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            Button { player.isPresented = false } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Minimise player")
            Spacer()
            if let current = player.current {
                Button { store.toggleFavorite(current) } label: {
                    Image(systemName: store.isFavorite(current) ? "star.fill" : "star")
                        .foregroundStyle(store.isFavorite(current) ? Theme.accent : .white)
                }
                .accessibilityLabel("Favourite")
            }
            Button {
                if purchases.isPro || !Entitlements.carModeIsPro { player.carMode = true } else { showPaywall = true }
            } label: { Image(systemName: "car.fill") }
                .accessibilityLabel("Car mode")
            AirPlayButton().frame(width: 30, height: 30)
            Button { player.stop() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Stop")
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal)
        .frame(height: 50)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.current?.name ?? "").font(.title3.bold()).lineLimit(2)
                    HStack(spacing: 6) {
                        if player.isLive {
                            Text("LIVE").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.red, in: Capsule())
                        }
                        Text(player.current?.group ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
            }
            if player.externalPlaybackActive {
                Label("Playing on the external screen", systemImage: "airplayvideo").font(.footnote).foregroundStyle(Theme.accent)
            }
            HStack(spacing: 40) {
                Button { player.previous() } label: { Image(systemName: "backward.end.fill") }.disabled(!player.hasPrevious)
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 54))
                }
                Button { player.next() } label: { Image(systemName: "forward.end.fill") }.disabled(!player.hasNext)
            }
            .font(.title)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
        }
        .padding()
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Up next").font(.headline).padding(.horizontal).padding(.bottom, 4)
            ScrollViewReader { proxy in
                List(player.queue) { ch in
                    Button { player.play(ch, present: false) } label: { ChannelRow(channel: ch) }
                        .buttonStyle(.plain)
                        .listRowBackground(player.current?.key == ch.key ? Theme.card : Color.clear)
                        .id(ch.key)
                }
                .listStyle(.plain)
                .onAppear { if let k = player.current?.key { proxy.scrollTo(k, anchor: .center) } }
            }
        }
    }
}
