import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var loadedURL: URL?

    private var player: AVAudioPlayer?

    func toggle(url: URL) throws {
        if loadedURL != url {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            loadedURL = url
        }

        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
