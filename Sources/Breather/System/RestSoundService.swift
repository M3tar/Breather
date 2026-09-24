import AppKit
import AVFoundation

@MainActor
final class RestSoundService {
    private var activeSounds: [NSSound] = []

    func play(_ effect: RestSoundEffect) {
        if let fileName = effect.bundledSoundFileName {
            playBundledSound(fileName: fileName)
            return
        }

        guard let name = effect.systemSoundName else { return }
        playSystemSound(named: name)
    }

    func stop() {
        activeSounds.forEach { $0.stop() }
        activeSounds.removeAll()
    }

    private func playBundledSound(fileName: String) {
        guard let soundURL = bundledSoundURL(fileName: fileName),
              let sound = NSSound(contentsOf: soundURL, byReference: false) else {
            return
        }

        play(sound)
    }

    private func playSystemSound(named name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            return
        }

        play(sound)
    }

    private func play(_ sound: NSSound) {
        activeSounds.append(sound)
        sound.play()
        let duration = max(sound.duration, 1)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) { [weak self, weak sound] in
            guard let sound else { return }
            self?.activeSounds.removeAll { $0 === sound }
        }
    }

    private func bundledSoundURL(fileName: String) -> URL? {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = Bundle.module
        #else
        bundle = Bundle.main
        #endif

        return bundle.url(forResource: fileName, withExtension: nil, subdirectory: "Sounds")
            ?? bundle.url(forResource: fileName, withExtension: nil)
    }
}

@MainActor
protocol RestAmbientSoundPlaying: AnyObject {
    func playRain()
    func stop()
}

/// A separate long-form player so ambience can loop and fade independently of
/// the short start/end notification sounds.
@MainActor
final class RestAmbientSoundService: RestAmbientSoundPlaying {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func playRain() {
        stopTask?.cancel()
        stopTask = nil
        if let player, player.isPlaying {
            player.setVolume(0.28, fadeDuration: 0.35)
            return
        }

        guard let url = bundledRainURL(),
              let nextPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        nextPlayer.numberOfLoops = -1
        nextPlayer.volume = 0
        nextPlayer.prepareToPlay()
        guard nextPlayer.play() else { return }
        player = nextPlayer
        nextPlayer.setVolume(0.28, fadeDuration: 0.8)
    }

    func stop() {
        stopTask?.cancel()
        guard let activePlayer = player else { return }
        activePlayer.setVolume(0, fadeDuration: 0.35)
        stopTask = Task { @MainActor [weak self, weak activePlayer] in
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled, let self, let activePlayer,
                  self.player === activePlayer else { return }
            activePlayer.stop()
            self.player = nil
            self.stopTask = nil
        }
    }

    private func bundledRainURL() -> URL? {
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = Bundle.module
        #else
        bundle = Bundle.main
        #endif

        return bundle.url(forResource: "rain-ambience", withExtension: "m4a", subdirectory: "Sounds")
            ?? bundle.url(forResource: "rain-ambience", withExtension: "m4a")
    }
}
