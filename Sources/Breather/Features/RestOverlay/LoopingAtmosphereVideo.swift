import AVFoundation
import AppKit
import SwiftUI

enum AtmosphereVideoAssets {
    static func videoURL(named name: String, extension fileExtension: String) -> URL? {
        resourceBundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Video")
            ?? resourceBundle.url(forResource: name, withExtension: fileExtension)
    }

    static func poster(named name: String) -> NSImage? {
        for fileExtension in ["jpg", "png"] {
            if let url = resourceBundle.url(
                forResource: "\(name)-poster",
                withExtension: fileExtension,
                subdirectory: "Video"
            ) ?? resourceBundle.url(
                forResource: "\(name)-poster",
                withExtension: fileExtension
            ) {
                return NSImage(contentsOf: url)
            }
        }
        return nil
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
}

struct LoopingAtmosphereVideo: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeNSView(context: Context) -> AtmospherePlayerView {
        let view = AtmospherePlayerView()
        view.playerLayer.player = context.coordinator.player
        context.coordinator.player.play()
        return view
    }

    func updateNSView(_ nsView: AtmospherePlayerView, context: Context) {
        nsView.playerLayer.player = context.coordinator.player
        context.coordinator.player.play()
    }

    static func dismantleNSView(_ nsView: AtmospherePlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
        nsView.playerLayer.player = nil
    }

    final class Coordinator {
        let player: AVQueuePlayer
        private var looper: AVPlayerLooper?

        init(url: URL) {
            let item = AVPlayerItem(url: url)
            player = AVQueuePlayer()
            player.isMuted = true
            player.actionAtItemEnd = .none
            looper = AVPlayerLooper(player: player, templateItem: item)
        }
    }
}

final class AtmospherePlayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = playerLayer
        playerLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
