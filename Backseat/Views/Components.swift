import AVKit
import SwiftUI

enum Theme {
    static let accent = Color.accentColor
    static let card = Color.white.opacity(0.07)
}

struct ChannelLogo: View {
    let url: String?
    let name: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(Theme.card)
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.1)
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var initials: some View {
        Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
            .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

struct ChannelRow: View {
    @Environment(LibraryStore.self) private var store
    @Environment(PlayerController.self) private var player
    let channel: Channel
    var showGroup = true

    var body: some View {
        HStack(spacing: 12) {
            ChannelLogo(url: channel.logoURL, name: channel.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name).font(.body.weight(.medium)).lineLimit(1)
                if showGroup {
                    Text(channel.group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let p = store.position(for: channel) {
                    ProgressView(value: p.progress).tint(Theme.accent).frame(maxWidth: 120)
                }
            }
            Spacer(minLength: 8)
            if player.current?.key == channel.key {
                Image(systemName: "waveform").foregroundStyle(Theme.accent).symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
            }
            Button {
                store.toggleFavorite(channel)
            } label: {
                Image(systemName: store.isFavorite(channel) ? "star.fill" : "star")
                    .foregroundStyle(store.isFavorite(channel) ? Theme.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(store.isFavorite(channel) ? "Remove from favourites" : "Add to favourites")
        }
        .contentShape(Rectangle())
    }
}

struct AirPlayButton: UIViewRepresentable {
    var tint: UIColor = .white

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = tint
        view.activeTintColor = UIColor(named: "AccentColor") ?? .systemOrange
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

final class PlayerLayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// A bare video surface with no controls, used by the mini player and car mode.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let v = PlayerLayerUIView()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = gravity
        return v
    }

    func updateUIView(_ v: PlayerLayerUIView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }

    static func dismantleUIView(_ v: PlayerLayerUIView, coordinator: ()) {
        v.playerLayer.player = nil
    }
}

/// The system player: scrubbing, subtitles and audio tracks, Picture in Picture and AirPlay.
/// `overlay` is drawn between the video and the system controls (used for the audio visualizer).
struct SystemPlayerView<Overlay: View>: UIViewControllerRepresentable {
    let player: AVPlayer
    var overlay: Overlay

    init(player: AVPlayer, @ViewBuilder overlay: () -> Overlay = { EmptyView() }) {
        self.player = player
        self.overlay = overlay()
    }

    final class Coordinator {
        var host: UIHostingController<Overlay>?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.videoGravity = .resizeAspect
        if let container = vc.contentOverlayView {
            let host = UIHostingController(rootView: overlay)
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: container.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            context.coordinator.host = host
        }
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
        context.coordinator.host?.rootView = overlay
    }

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: Coordinator) {
        vc.player = nil
    }
}

struct MiniPlayerBar: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        if let current = player.current, !player.isPresented {
            HStack(spacing: 12) {
                PlayerLayerView(player: player.player, gravity: .resizeAspectFill)
                    .frame(width: 88, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(player.errorMessage == nil ? current.group : "Playback error")
                        .font(.caption).foregroundStyle(player.errorMessage == nil ? Color.secondary : Color.red).lineLimit(1)
                }
                Spacer()
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.stop() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Stop playback")
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture { player.isPresented = true }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

extension View {
    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
    }
}

enum Orientation {
    static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

extension Date {
    var relative: String { formatted(.relative(presentation: .named)) }
}
