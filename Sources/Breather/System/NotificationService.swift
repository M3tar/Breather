import Foundation
import UserNotifications

enum NotificationPermissionStatus: Equatable {
    case authorized
    case provisional
    case denied
    case notDetermined
    case unavailable

    var title: String {
        switch self {
        case .authorized: "已授权"
        case .provisional: "临时授权"
        case .denied: "未授权"
        case .notDetermined: "未请求"
        case .unavailable: "不可用"
        }
    }

    var canSendNotifications: Bool {
        self == .authorized || self == .provisional
    }
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    private var canUseUserNotifications: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    func requestAuthorization() async -> NotificationPermissionStatus {
        guard canUseUserNotifications else { return .unavailable }

        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return await authorizationStatus()
        }

        return await authorizationStatus()
    }

    func authorizationStatus() async -> NotificationPermissionStatus {
        guard canUseUserNotifications else { return .unavailable }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        case .ephemeral:
            return .provisional
        @unknown default:
            return .unavailable
        }
    }

    func sendPreBreakNotification(playSound: Bool, soundEffect: RestSoundEffect) {
        Task {
            await sendNotification(
                title: "快到休息时间了",
                body: "准备喘口气，看看远处。",
                identifierPrefix: "breather.prebreak",
                playSound: playSound,
                soundEffect: soundEffect
            )
        }
    }

    func sendPreviewNotification(playSound: Bool, soundEffect: RestSoundEffect) async -> Bool {
        await sendNotification(
            title: "Breather 通知预览",
            body: "这是一条预览通知。休息前，Breather 会用这种方式提醒你。",
            identifierPrefix: "breather.preview",
            playSound: playSound,
            soundEffect: soundEffect,
            deliverAfter: 1
        )
    }

    @discardableResult
    private func sendNotification(
        title: String,
        body: String,
        identifierPrefix: String,
        playSound: Bool,
        soundEffect: RestSoundEffect,
        deliverAfter: TimeInterval? = nil
    ) async -> Bool {
        guard canUseUserNotifications else { return false }
        guard (await authorizationStatus()).canSendNotifications else { return false }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if playSound, let notificationSound = notificationSound(for: soundEffect) {
            content.sound = notificationSound
        }

        let trigger: UNNotificationTrigger?
        if let deliverAfter {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: deliverAfter, repeats: false)
        } else {
            trigger = nil
        }

        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix).\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    private func notificationSound(for effect: RestSoundEffect) -> UNNotificationSound? {
        switch effect {
        case .none:
            return nil
        default:
            break
        }

        guard let fileName = effect.bundledSoundFileName else {
            return .default
        }

        installNotificationSoundIfNeeded(fileName: fileName)
        return UNNotificationSound(named: UNNotificationSoundName(fileName))
    }

    private func installNotificationSoundIfNeeded(fileName: String) {
        guard let sourceURL = bundledSoundURL(fileName: fileName),
              let soundsDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Sounds", isDirectory: true) else {
            return
        }

        let destinationURL = soundsDirectory.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else { return }

        do {
            try FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            return
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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil {
            options.insert(.sound)
        }
        return options
    }
}
