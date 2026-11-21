import AVFoundation
import Foundation

/// Plays the catchiest part of a song for each Wrapped slide, crossfading between them.
@MainActor
final class WrappedAudio {
    private var players: [AVAudioPlayer] = []
    private(set) var currentID: Int?
    private var paused = false

    var muted = false {
        didSet { players.last?.setVolume(muted ? 0 : 1, fadeDuration: 0.3) }
    }

    func play(_ entry: LibraryEntry?) {
        guard let e = entry else { fadeOutAll(); currentID = nil; return }
        guard e.id != currentID else { return }
        currentID = e.id
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let p = try? AVAudioPlayer(contentsOf: e.fileURL) else { return }
        let end = e.trimEnd ?? p.duration
        let start = e.highlightStart ?? max(e.trimStart, end * 0.3)
        p.currentTime = min(max(e.trimStart, start), max(0, end - 25))
        p.volume = 0
        p.numberOfLoops = 0
        p.prepareToPlay()
        if !paused { p.play() }
        p.setVolume(muted ? 0 : 1, fadeDuration: 1.2)
        fadeOutAll()
        players.append(p)
    }

    func setPaused(_ on: Bool) {
        paused = on
        if on { players.last?.pause() } else { players.last?.play() }
    }

    func stop() {
        fadeOutAll()
        currentID = nil
    }

    private func fadeOutAll() {
        let old = players
        players.removeAll()
        for p in old { p.setVolume(0, fadeDuration: 1.0) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            for p in old { p.stop() }
        }
    }
}
