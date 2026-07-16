import CoreGraphics
import Foundation

final class IdleMonitor {
    private let anyInputEventType = CGEventType(rawValue: UInt32.max)!

    var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInputEventType
        )
    }
}
