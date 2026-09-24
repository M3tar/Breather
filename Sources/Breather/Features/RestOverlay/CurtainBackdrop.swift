import AVFoundation
import AppKit
import SwiftUI

struct CurtainColors {
    let base: Color
    let deep: Color
    let highlight: Color
    let shadow: Color
    let glow: Color
    let text: Color

    init(palette: CurtainPalette) {
        switch palette {
        case .smokedJade:
            (base, deep, highlight, shadow, glow, text) = (
                Color(hex: 0x22352E), Color(hex: 0x17231F), Color(hex: 0x587266),
                Color(hex: 0x0C1210), Color(hex: 0xB9D4C5), Color(hex: 0xF0F4F1)
            )
        case .warmLinen:
            (base, deep, highlight, shadow, glow, text) = (
                Color(hex: 0x393630), Color(hex: 0x282622), Color(hex: 0x746C61),
                Color(hex: 0x151411), Color(hex: 0xC9BDA8), Color(hex: 0xF3EFE7)
            )
        case .mistBlue:
            (base, deep, highlight, shadow, glow, text) = (
                Color(hex: 0x25333A), Color(hex: 0x182126), Color(hex: 0x58707A),
                Color(hex: 0x0B1114), Color(hex: 0xB5CBD1), Color(hex: 0xEEF3F4)
            )
        case .blackCherry:
            (base, deep, highlight, shadow, glow, text) = (
                Color(hex: 0x3A1C24), Color(hex: 0x211216), Color(hex: 0x75434D),
                Color(hex: 0x11090B), Color(hex: 0xD5AA96), Color(hex: 0xF6EFEC)
            )
        }
    }
}

enum CurtainPhase: Equatable {
    case open
    case closing
    case closed
    case opening
}

enum CurtainTiming {
    static let closingDuration: TimeInterval = 3.07
    static let contentRevealDelay: Duration = .milliseconds(3_070)
    static let thumbnailContentRevealDelay: Duration = .milliseconds(2_200)
    static let openingDuration: Duration = .milliseconds(2_620)
    static let openingHandoffFadeDuration: CFTimeInterval = 0.16
}

enum CurtainPlaybackContinuity {
    static func keepsClosedPoster(phase: CurtainPhase, firstFrameReady: Bool) -> Bool {
        phase == .opening && !firstFrameReady
    }
}

struct CurtainBackdrop: View {
    let palette: CurtainPalette
    let phase: CurtainPhase
    let animated: Bool

    var body: some View {
        Group {
            if let playback {
                CurtainVideoPlayer(
                    url: playback.url,
                    placeholder: playback.placeholder
                )
            } else if phase == .closed || phase == .closing {
                closedPoster
            } else {
                Color.clear
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var playback: CurtainPlayback? {
        guard animated else { return nil }
        switch phase {
        case .closing:
            guard let url = CurtainAssets.videoURL(palette: palette, motion: .closing) else { return nil }
            return CurtainPlayback(url: url, placeholder: nil)
        case .opening:
            guard let url = CurtainAssets.videoURL(palette: palette, motion: .opening) else { return nil }
            return CurtainPlayback(url: url, placeholder: CurtainAssets.poster(palette: palette))
        case .open, .closed:
            return nil
        }
    }

    @ViewBuilder private var closedPoster: some View {
        if let poster = CurtainAssets.poster(palette: palette) {
            Image(nsImage: poster)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            CurtainColors(palette: palette).base
        }
    }
}

private struct CurtainPlayback {
    let url: URL
    let placeholder: NSImage?
}

private enum CurtainMotion: String {
    case closing
    case opening
}

private enum CurtainAssets {
    static func videoURL(palette: CurtainPalette, motion: CurtainMotion) -> URL? {
        let name = "curtain-\(palette.resourceStem)-\(motion.rawValue)"
        return resourceBundle.url(forResource: name, withExtension: "mov", subdirectory: "Video")
            ?? resourceBundle.url(forResource: name, withExtension: "mov")
    }

    static func poster(palette: CurtainPalette) -> NSImage? {
        let name = "curtain-\(palette.resourceStem)-poster"
        guard let url = resourceBundle.url(forResource: name, withExtension: "png", subdirectory: "Video")
                ?? resourceBundle.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
}

private extension CurtainPalette {
    var resourceStem: String {
        switch self {
        case .smokedJade: "smoked-jade"
        case .warmLinen: "warm-linen"
        case .mistBlue: "mist-blue"
        case .blackCherry: "black-cherry"
        }
    }
}

private struct CurtainVideoPlayer: NSViewRepresentable {
    let url: URL
    var placeholder: NSImage? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeNSView(context: Context) -> CurtainPlayerView {
        let view = CurtainPlayerView()
        view.prepareForPlayback(placeholder: placeholder)
        view.playerLayer.player = context.coordinator.player
        context.coordinator.play()
        return view
    }

    func updateNSView(_ nsView: CurtainPlayerView, context: Context) {
        nsView.playerLayer.player = context.coordinator.player
        context.coordinator.replaceItemIfNeeded(url: url) {
            nsView.prepareForPlayback(placeholder: placeholder)
        }
    }

    static func dismantleNSView(_ nsView: CurtainPlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
        nsView.stopWaitingForFirstFrame()
        nsView.playerLayer.player = nil
    }

    final class Coordinator {
        let player = AVPlayer()
        private var url: URL

        init(url: URL) {
            self.url = url
            player.isMuted = true
            player.actionAtItemEnd = .pause
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }

        func play() {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
        }

        func replaceItemIfNeeded(url: URL, beforeReplacement: () -> Void) {
            guard self.url != url else { return }
            beforeReplacement()
            self.url = url
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            play()
        }
    }
}

private final class CurtainPlayerView: NSView {
    let playerLayer = AVPlayerLayer()
    private let backingLayer = CALayer()
    private let placeholderLayer = CALayer()
    private var readinessTimer: Timer?
    private var earliestPlaceholderHide = Date.distantFuture

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = backingLayer
        backingLayer.masksToBounds = true
        placeholderLayer.contentsGravity = .resizeAspectFill
        backingLayer.addSublayer(placeholderLayer)
        backingLayer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        backingLayer.frame = bounds
        placeholderLayer.frame = bounds
        playerLayer.frame = bounds
    }

    func prepareForPlayback(placeholder: NSImage?) {
        readinessTimer?.invalidate()
        guard let placeholder,
              CurtainPlaybackContinuity.keepsClosedPoster(
                phase: .opening,
                firstFrameReady: false
              ) else {
            placeholderLayer.isHidden = true
            placeholderLayer.contents = nil
            return
        }

        placeholderLayer.contents = placeholder.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        )
        placeholderLayer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeholderLayer.isHidden = false
        placeholderLayer.opacity = 1
        CATransaction.commit()
        earliestPlaceholderHide = Date().addingTimeInterval(0.05)
        readinessTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 120,
            target: self,
            selector: #selector(checkFirstFrameReadiness(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    func stopWaitingForFirstFrame() {
        readinessTimer?.invalidate()
        readinessTimer = nil
    }

    @objc private func checkFirstFrameReadiness(_ timer: Timer) {
        guard Date() >= earliestPlaceholderHide,
              playerLayer.isReadyForDisplay else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(CurtainTiming.openingHandoffFadeDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        placeholderLayer.opacity = 0
        CATransaction.commit()
        timer.invalidate()
        readinessTimer = nil
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
