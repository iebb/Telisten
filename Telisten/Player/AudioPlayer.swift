@preconcurrency import AVFoundation
import Foundation
@preconcurrency import MediaPlayer
import Observation

@MainActor
@Observable
final class AudioPlayer {
    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var volume: Float = 1 {
        didSet {
            player.volume = volume
            if volume > 0.001 { volumeBeforeMute = volume }
        }
    }

    var isMuted: Bool { volume <= 0.001 }

    var volumeSymbolName: String {
        switch volume {
        case ...0.001: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    var onFinished: (@MainActor @Sendable () -> Void)?
    var onReady: (@MainActor @Sendable (Track) -> Void)?
    var onNext: (@MainActor @Sendable () -> Void)?
    var onPrevious: (@MainActor @Sendable () -> Void)?
    var onError: (@MainActor @Sendable (String) -> Void)?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var streamingResource: StreamingAudioResource?
    private let resourceLoaderQueue = DispatchQueue(label: "ad.neko.player.resource-loader")
    private var wantsPlayback = false
    private var volumeBeforeMute: Float = 1

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        configureAudioSession()
        installTimeObserver()
        installTimeControlObserver()
        installRemoteCommands()
    }

    func beginLoading(_ track: Track) {
        activateAudioSession()
        clearCurrentItem()
        self.track = track
        duration = track.duration
        currentTime = 0
        wantsPlayback = true
        isPlaying = false
        isLoading = true
        updateNowPlaying()
    }

    func load(_ track: Track, from url: URL, autoplay: Bool = true) {
        guard self.track?.id == track.id else { return }
        streamingResource?.cancelAll()
        streamingResource = nil
        install(AVPlayerItem(url: url), track: track, autoplay: autoplay)
    }

    func loadStreaming(
        _ track: Track,
        provider: @escaping AudioByteProvider,
        autoplay: Bool = true
    ) {
        guard self.track?.id == track.id else { return }
        streamingResource?.cancelAll()
        let resource = StreamingAudioResource(fileSize: track.size, mimeType: track.mimeType, provider: provider)
        streamingResource = resource
        let fileExtension = (track.fileName as NSString).pathExtension
        let suffix = fileExtension.isEmpty ? "audio" : fileExtension
        let url = URL(string: "telisten-stream://track/\(track.documentID).\(suffix)")!
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        asset.resourceLoader.setDelegate(resource, queue: resourceLoaderQueue)
        install(AVPlayerItem(asset: asset), track: track, autoplay: autoplay)
    }

    func failLoading() {
        wantsPlayback = false
        player.pause()
        isPlaying = false
        isLoading = false
        updateNowPlaying()
    }

    private func install(_ item: AVPlayerItem, track: Track, autoplay: Bool) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        statusObservation = nil
        self.track = track
        duration = track.duration
        currentTime = 0
        wantsPlayback = autoplay
        isLoading = autoplay
        item.preferredForwardBufferDuration = 2
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.player.currentItem === item, self.track?.id == track.id else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    if self.wantsPlayback {
                        self.player.play()
                        self.isPlaying = true
                    }
                    self.updateNowPlaying()
                    self.onReady?(track)
                case .failed:
                    let reason = item.error?.localizedDescription ?? "The audio format is not supported on this device."
                    self.failLoading()
                    self.onError?("This track could not be played. \(reason)")
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.wantsPlayback = false
                self?.isPlaying = false
                self?.isLoading = false
                self?.onFinished?()
            }
        }
        updateNowPlaying()
        if autoplay { player.play() }
    }

    func play() {
        guard let item = player.currentItem, item.status != .failed else { return }
        activateAudioSession()
        wantsPlayback = true
        player.play()
        isPlaying = true
        isLoading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        wantsPlayback = false
        isPlaying = false
        isLoading = false
        updateNowPlaying()
    }

    func reset() {
        clearCurrentItem()
        track = nil
        wantsPlayback = false
        isPlaying = false
        isLoading = false
        currentTime = 0
        duration = 0
        updateNowPlaying()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func toggleMute() {
        volume = isMuted ? max(volumeBeforeMute, 0.5) : 0
    }

    func seek(to seconds: TimeInterval) {
        let target = max(0, min(seconds, duration))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
        updateNowPlaying()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    #if DEBUG
    func preview(_ track: Track, at seconds: TimeInterval = 0) {
        self.track = track
        duration = track.duration
        currentTime = seconds
        isPlaying = false
        isLoading = false
        wantsPlayback = false
        updateNowPlaying()
    }
    #endif

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite {
                    self.duration = itemDuration
                }
                self.updateNowPlaying()
            }
        }
    }

    private func installTimeControlObserver() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isLoading = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = self.wantsPlayback
                    self.isLoading = self.wantsPlayback
                case .paused:
                    self.isPlaying = false
                    if !self.wantsPlayback { self.isLoading = false }
                @unknown default:
                    break
                }
                self.updateNowPlaying()
            }
        }
    }

    private func clearCurrentItem() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObservation = nil
        streamingResource?.cancelAll()
        streamingResource = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            // Playback can still work while inactive; the UI reports file errors separately.
        }
        #endif
    }

    private func activateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func installRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onNext?() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPrevious?() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPMediaItemPropertyArtist: track.displayArtist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}
