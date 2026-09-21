import Foundation
import Combine

@MainActor
final class RestOverlayAvailability: ObservableObject {
    @Published var isResting = false
}

/// One presentation, shared by every display. Real remaining time is supplied only
/// by the scheduler; this object never advances a real break on its own.
@MainActor
final class RestOverlaySession: ObservableObject {
    enum Kind { case rest, preview }

    let id = UUID()
    let kind: Kind
    let contentMode: RestOverlayContentMode
    let background: RestOverlayBackground
    let translucent: Bool
    let fadeAnimation: Bool
    let copy: RestOverlayCopy
    let totalSeconds: Int
    let scene: DinosaurSceneModel

    @Published private(set) var remainingSeconds: Int
    @Published private(set) var isDismissing = false
    @Published private(set) var isAnimationPaused = false
    @Published private(set) var sceneStopTime: TimeInterval?

    private let uptime: () -> TimeInterval
    private var anchor: TimeInterval
    private var accumulated: TimeInterval = 0

    init(
        kind: Kind, settings: AppSettings, totalSeconds: Int,
        remainingSeconds: Int? = nil, showsRecoveryNudge: Bool = false,
        seed: UInt64 = UInt64.random(in: 0...UInt64.max),
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.kind = kind
        contentMode = settings.restOverlayContentMode
        background = contentMode == .dinosaur ? .solid : settings.restOverlayBackground
        translucent = contentMode == .classic && settings.restOverlayTranslucentBackground
        fadeAnimation = settings.restOverlayFadeAnimation
        copy = RestOverlayCopy(settings: settings, showsRecoveryNudge: showsRecoveryNudge)
        self.totalSeconds = max(1, totalSeconds)
        self.remainingSeconds = max(0, remainingSeconds ?? totalSeconds)
        scene = DinosaurSceneModel(seed: seed)
        self.uptime = uptime
        anchor = uptime()
        if Double(self.remainingSeconds) <= min(2, Double(self.totalSeconds) * 0.1) {
            sceneStopTime = 0
        }
    }

    var formattedTime: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var progress: Double {
        min(1, max(0, 1 - Double(remainingSeconds) / Double(totalSeconds)))
    }

    var animationElapsed: TimeInterval {
        accumulated + (isAnimationPaused ? 0 : max(0, uptime() - anchor))
    }

    var hasSceneStopped: Bool {
        sceneStopTime.map { animationElapsed >= $0 } ?? false
    }

    func updateRemaining(_ seconds: Int) {
        guard !isDismissing else { return }
        let value = max(0, min(totalSeconds, seconds))
        if sceneStopTime == nil, Double(value) <= min(2, Double(totalSeconds) * 0.1) {
            sceneStopTime = scene.finishTime(after: animationElapsed)
        }
        if value != remainingSeconds { remainingSeconds = value }
    }

    func updatePreview() {
        guard kind == .preview else { return }
        updateRemaining(Int(ceil(max(0, Double(totalSeconds) - animationElapsed))))
    }

    func setAnimationPaused(_ paused: Bool) {
        guard paused != isAnimationPaused, !isDismissing else { return }
        if paused {
            accumulated = animationElapsed
        } else {
            anchor = uptime()
        }
        isAnimationPaused = paused
    }

    func beginDismissal() {
        guard !isDismissing else { return }
        setAnimationPaused(true)
        isDismissing = true
    }
}

struct RestOverlayCopy {
    let prompt: String?
    let subtitle: String?

    init(settings: AppSettings, showsRecoveryNudge: Bool = false) {
        prompt = settings.restOverlayPrompt.resolvedTitle
        subtitle = showsRecoveryNudge
            ? "最近几次休息都被延后或跳过了，这次先把短休完成吧。"
            : settings.restOverlaySubtitle.resolvedTitle
    }
}
