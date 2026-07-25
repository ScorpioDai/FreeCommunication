import AVFoundation
import Foundation

@MainActor
final class RecordingAudioPlayer: ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var url: URL?

    private var player: AVPlayer?
    private var timeObserver: Any?

    deinit {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
    }

    func load(url newURL: URL?) {
        guard url != newURL else { return }
        pause()
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        url = newURL
        currentTime = 0
        duration = 0
        guard let newURL else {
            player = nil
            return
        }

        let item = AVPlayerItem(url: newURL)
        let player = AVPlayer(playerItem: item)
        self.player = player
        Task {
            let loadedDuration = try? await item.asset.load(.duration)
            let seconds = CMTimeGetSeconds(loadedDuration ?? .zero)
            if self.url == newURL, seconds.isFinite {
                self.duration = seconds
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = CMTimeGetSeconds(time)
                if let item = self?.player?.currentItem {
                    let itemDuration = CMTimeGetSeconds(item.duration)
                    if itemDuration.isFinite {
                        self?.duration = itemDuration
                    }
                }
            }
        }
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    func seek(to seconds: TimeInterval) {
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
    }
}
