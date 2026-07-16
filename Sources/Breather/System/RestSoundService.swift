import AppKit

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
