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
        case .idle: L.tr("点击检查 GitHub 上发布的正式版本。")
        case .checking: L.tr("正在检查更新…")
        case .upToDate: L.tr("当前已是最新版本")
        case let .available(update): L.tr("发现新版本 v\(update.version)，可前往 GitHub 手动下载。")
        case .noDownload: L.tr("暂时没有可下载的正式版本。")
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
    private let checkRelease: @MainActor (String) async throws -> UpdateCheckResponse
    private var automaticTask: Task<Void, Never>?

    private let lastAttemptKey = "breather.update.lastAttemptAt"
    private let nextCheckKey = "breather.update.nextCheckAt"
    private let lastSuccessKey = "breather.update.lastSuccessAt"
    private let failedCheckInterval: TimeInterval = 60 * 60
    private let lastResultKey = "breather.update.lastResult"
    private let availableVersionKey = "breather.update.availableVersion"
    private let availableURLKey = "breather.update.availableURL"
    private let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    init(
        userDefaults: UserDefaults = .standard,
        installedVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        now: @escaping () -> Date = Date.init,
        checkRelease: (@MainActor (String) async throws -> UpdateCheckResponse)? = nil
    ) {
        self.userDefaults = userDefaults
        self.installedVersion = installedVersion
        self.now = now
        let checker = UpdateChecker(userDefaults: userDefaults, now: now)
        self.checkRelease = checkRelease ?? { try await checker.check(installedVersion: $0) }

        if let version = userDefaults.string(forKey: availableVersionKey),
           UpdateChecker.isStableVersion(version),
           let versionNumber = AppVersion(version),
           let installedNumber = AppVersion(installedVersion),
           versionNumber > installedNumber,
           let urlString = userDefaults.string(forKey: availableURLKey),
           let url = URL(string: urlString),
           (UpdateChecker.isReleaseURL(url, tag: "v\(version)")
                || UpdateChecker.isReleaseURL(url, tag: version)) {
            let update = AvailableUpdate(version: version, releaseURL: url)
            availableUpdate = update
            status = .available(update)
        } else {
            // A previous "up to date" result is not proof of today's latest version.
            clearCachedUpdate()
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
        if let nextCheck = userDefaults.object(forKey: nextCheckKey) as? Date,
           now() < nextCheck {
            return
        }
        await runCheck(isManual: false)
    }

    func checkNow() async {
        await runCheck(isManual: true)
    }

    private func runCheck(isManual: Bool) async {
        guard !status.isChecking, !Task.isCancelled else { return }
        let previousStatus = status
        status = .checking
        userDefaults.set(now(), forKey: lastAttemptKey)

        do {
            let response = try await checkRelease(installedVersion)
            guard !Task.isCancelled else {
                status = previousStatus
                return
            }

            // The Latest redirect can lag behind the API during publication. Do not
            // let that older snapshot erase an update we have already discovered.
            if response.source == .manifest, let known = availableUpdate,
               manifestIsOlder(response.result, than: known) {
                status = .available(known)
                userDefaults.set(now().addingTimeInterval(failedCheckInterval), forKey: nextCheckKey)
                return
            }

            userDefaults.set(now(), forKey: lastSuccessKey)
            userDefaults.set(now().addingTimeInterval(automaticCheckInterval), forKey: nextCheckKey)

            switch response.result {
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
            guard !Task.isCancelled, !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled else {
                status = previousStatus
                return
            }
            userDefaults.set(now().addingTimeInterval(failedCheckInterval), forKey: nextCheckKey)
            if isManual {
                if case UpdateCheckError.invalidInstalledVersion = error {
                    status = .failed(L.tr("无法比较当前版本，请从正式安装的应用中检查。"))
                } else {
                    status = .failed(L.tr("暂时无法检查更新，请稍后重试。"))
                }
            } else if let update = availableUpdate {
                status = .available(update)
            } else {
                status = .failed(L.tr("暂时无法检查更新，请稍后重试。"))
            }
        }
    }

    private func manifestIsOlder(_ result: UpdateCheckResult, than known: AvailableUpdate) -> Bool {
        switch result {
        case .upToDate, .noDownload:
            return true
        case let .available(update):
            guard let received = AppVersion(update.version), let cached = AppVersion(known.version) else { return false }
            return received < cached
        }
    }

    private func clearCachedUpdate() {
        userDefaults.removeObject(forKey: availableVersionKey)
        userDefaults.removeObject(forKey: availableURLKey)
    }
}
