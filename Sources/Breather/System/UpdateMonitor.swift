import Combine
import Foundation

enum UpdateStatus {
    case idle
    case checking
    case upToDate
    case available(AvailableUpdate)
    case noDownload
    case failed(String)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .idle: "点击检查 GitHub 上发布的版本。"
        case .checking: "正在检查 GitHub Releases…"
        case .upToDate: "当前已是最新版本"
        case let .available(update): "发现新版本 v\(update.version)，可前往 GitHub 手动下载。"
        case .noDownload: "暂时没有已发布的 DMG。"
        case let .failed(message): message
        }
    }
}

@MainActor
final class UpdateMonitor: ObservableObject {
    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var availableUpdate: AvailableUpdate?

    private let userDefaults: UserDefaults
    private let installedVersion: String
    private let now: () -> Date
    private let checkRelease: @MainActor (String) async throws -> UpdateCheckResult
    private var automaticTask: Task<Void, Never>?

    private let lastAttemptKey = "breather.update.lastAttemptAt"
    private let lastResultKey = "breather.update.lastResult"
    private let availableVersionKey = "breather.update.availableVersion"
    private let availableURLKey = "breather.update.availableURL"
    private let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    init(
        userDefaults: UserDefaults = .standard,
        installedVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        now: @escaping () -> Date = Date.init,
        checkRelease: @escaping @MainActor (String) async throws -> UpdateCheckResult = {
            try await UpdateChecker().check(installedVersion: $0)
        }
    ) {
        self.userDefaults = userDefaults
        self.installedVersion = installedVersion
        self.now = now
        self.checkRelease = checkRelease

        if let version = userDefaults.string(forKey: availableVersionKey),
           let versionNumber = AppVersion(version),
           let installedNumber = AppVersion(installedVersion),
           versionNumber > installedNumber,
           let urlString = userDefaults.string(forKey: availableURLKey),
           let url = URL(string: urlString),
           url.host == "github.com" {
            let update = AvailableUpdate(version: version, releaseURL: url)
            availableUpdate = update
            status = .available(update)
        } else {
            switch userDefaults.string(forKey: lastResultKey) {
            case "upToDate": status = .upToDate
            case "noDownload": status = .noDownload
            default: status = .idle
            }
        }
    }

    func startAutomaticChecks() {
        guard automaticTask == nil else { return }
        automaticTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.checkIfDue()
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    func stopAutomaticChecks() {
        automaticTask?.cancel()
        automaticTask = nil
    }

    func checkIfDue() async {
        if let lastAttempt = userDefaults.object(forKey: lastAttemptKey) as? Date,
           now().timeIntervalSince(lastAttempt) < automaticCheckInterval {
            return
        }
        await runCheck(isManual: false)
    }

    func checkNow() async {
        await runCheck(isManual: true)
    }

    private func runCheck(isManual: Bool) async {
        guard !status.isChecking else { return }
        let previousStatus = status
        status = .checking
        userDefaults.set(now(), forKey: lastAttemptKey)

        do {
            let result = try await checkRelease(installedVersion)
            guard !Task.isCancelled else {
                status = previousStatus
                return
            }

            switch result {
            case .upToDate:
                availableUpdate = nil
                status = .upToDate
                userDefaults.set("upToDate", forKey: lastResultKey)
                clearCachedUpdate()
            case let .available(update):
                availableUpdate = update
                status = .available(update)
                userDefaults.set("available", forKey: lastResultKey)
                userDefaults.set(update.version, forKey: availableVersionKey)
                userDefaults.set(update.releaseURL.absoluteString, forKey: availableURLKey)
            case .noDownload:
                availableUpdate = nil
                status = .noDownload
                userDefaults.set("noDownload", forKey: lastResultKey)
                clearCachedUpdate()
            }
        } catch {
            guard !Task.isCancelled else {
                status = previousStatus
                return
            }
            if isManual {
                if case UpdateCheckError.invalidInstalledVersion = error {
                    status = .failed("无法比较当前版本，请从正式安装的应用中检查。")
                } else {
                    status = .failed("检查失败，请确认网络连接后重试。")
                }
            } else {
                status = previousStatus
            }
        }
    }

    private func clearCachedUpdate() {
        userDefaults.removeObject(forKey: availableVersionKey)
        userDefaults.removeObject(forKey: availableURLKey)
    }
}
