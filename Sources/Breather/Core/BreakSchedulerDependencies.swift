import Foundation

@MainActor
protocol BreakNotificationSending: AnyObject {
    func sendPreBreakNotification(playSound: Bool, soundEffect: RestSoundEffect)
}

protocol IdleTimeProviding: AnyObject {
    var idleSeconds: TimeInterval { get }
}

extension NotificationService: BreakNotificationSending {}
extension IdleMonitor: IdleTimeProviding {}
