import AVFoundation
import Combine
import MediaPlayer
import Observation
import UIKit

@MainActor @Observable
final class PlayerController {
    let player = AVPlayer()
    private(set) var current: Channel?
    private(set) var queue: [Channel] = []
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var errorMessage: String?
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var externalPlaybackActive = false
    /// True for radio and other streams with no video track.
    private(set) var isAudioOnly = false

    var isPresented = false
    var carMode = false

    @ObservationIgnored weak var store: LibraryStore?
    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private var itemBag = Set<AnyCancellable>()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var didResume = false

    init() {
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    self?.isPlaying = status == .playing
                    self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
                }
            }
            .store(in: &bag)
        player.publisher(for: \.isExternalPlaybackActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in MainActor.assumeIsolated { self?.externalPlaybackActive = active } }
            .store(in: &bag)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        setupRemoteCommands()
    }

    // MARK: State

    var isLive: Bool { !(duration.isFinite && duration > 0) }
    private var index: Int? { current.flatMap { c in queue.firstIndex { $0.key == c.key } } }
    var hasNext: Bool { (index ?? queue.count) < queue.count - 1 }
    var hasPrevious: Bool { (index ?? 0) > 0 }

    // MARK: Commands

    func play(_ channel: Channel, queue newQueue: [Channel]? = nil, present: Bool = true) {
        saveProgress(force: true)
        if let newQueue { queue = newQueue } else if !queue.contains(where: { $0.key == channel.key }) { queue = [channel] }
        current = channel
        errorMessage = nil
        currentTime = 0
        duration = 0
        didResume = false
        isAudioOnly = false

        guard let url = store?.playableURL(for: channel) else {
            errorMessage = "This entry has no playable address."
            return
        }
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        item.externalMetadata = [metadata(.commonIdentifierTitle, channel.name), metadata(.iTunesMetadataTrackSubTitle, channel.group)]
        itemBag = []
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                MainActor.assumeIsolated {
                    guard let self, let item else { return }
                    switch status {
                    case .failed:
                        self.errorMessage = Self.describe(item.error)
                    case .readyToPlay:
                        self.resumeIfNeeded(item)
                    default: break
                    }
                }
            }
            .store(in: &itemBag)
        item.publisher(for: \.status).combineLatest(item.publisher(for: \.presentationSize), item.publisher(for: \.tracks))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status, size, tracks in
                MainActor.assumeIsolated {
                    let hasVideo = tracks.contains { $0.assetTrack?.mediaType == .video }
                    self?.isAudioOnly = status == .readyToPlay && size == .zero && !hasVideo
                }
            }
            .store(in: &itemBag)
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let current = self.current else { return }
                    self.store?.clearPosition(current)
                    if self.hasNext { self.next() }
                }
            }
            .store(in: &itemBag)

        player.replaceCurrentItem(with: item)
        player.play()
        store?.markPlayed(channel)
        updateNowPlaying()
        if present {
            let defaults = UserDefaults.standard
            carMode = defaults.bool(forKey: "openInCarMode") && (defaults.bool(forKey: "isPro") || !Entitlements.carModeIsPro)
            isPresented = true
        }
    }

    func togglePlay() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }

    func next() {
        guard let i = index, i + 1 < queue.count else { return }
        play(queue[i + 1], present: false)
    }

    func previous() {
        guard let i = index, i > 0 else { return }
        play(queue[i - 1], present: false)
    }

    func retry() {
        guard let current else { return }
        play(current, present: false)
    }

    func seek(by seconds: Double) {
        let target = max(0, min(currentTime + seconds, duration.isFinite ? duration : currentTime + seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func stop() {
        saveProgress(force: true)
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemBag = []
        current = nil
        isPresented = false
        carMode = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Internals

    private func tick(_ time: CMTime) {
        currentTime = time.seconds.isFinite ? time.seconds : 0
        let d = player.currentItem?.duration.seconds ?? 0
        duration = d.isFinite ? d : 0
        if Date().timeIntervalSince(lastSave) > 5 { saveProgress(force: false) }
    }

    private func saveProgress(force: Bool) {
        guard let current, !isLive else { return }
        lastSave = Date()
        store?.savePosition(current, seconds: currentTime, duration: duration)
        if force { updateNowPlaying() }
    }

    private func resumeIfNeeded(_ item: AVPlayerItem) {
        guard !didResume, let current else { return }
        didResume = true
        let d = item.duration.seconds
        if d.isFinite, d > 0, let pos = store?.position(for: current), pos.seconds > 5, pos.seconds < d - 15 {
            player.seek(to: CMTime(seconds: pos.seconds, preferredTimescale: 600))
        }
        updateNowPlaying()
    }

    private static func describe(_ error: Error?) -> String {
        guard let error = error as NSError? else { return "The stream could not be played." }
        if error.domain == NSURLErrorDomain { return "The stream is unreachable. Check your connection or the playlist." }
        return "This stream could not be played. It may be offline or use a format iPhone cannot decode. (\(error.localizedDescription))"
    }

    private func metadata(_ id: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = id
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.name,
            MPMediaItemPropertyArtist: current.group,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if !isLive {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.player.play() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.player.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.togglePlay() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.previous() }; return .success }
    }
}
