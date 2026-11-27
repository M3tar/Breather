import Foundation
import OSLog

struct AppVersion: Comparable {
    let numbers: [Int]
    let prerelease: [String]

    static var installedString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    init?(_ value: String) {
        let tag = value.hasPrefix("v") ? String(value.dropFirst()) : value
        guard let coreAndPrerelease = tag.split(separator: "+", maxSplits: 1).first else {
            return nil
        }
        let withoutBuild = String(coreAndPrerelease)
        let parts = withoutBuild.split(
            separator: "-", maxSplits: 1, omittingEmptySubsequences: false
        )
        guard let core = parts.first else { return nil }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false)
        let parsed = numbers.compactMap { Int($0) }
        guard numbers.count == 3,
              parsed.count == 3,
              parsed.allSatisfy({ $0 >= 0 }) else { return nil }

        self.numbers = parsed
        if parts.count == 2 {
            guard !parts[1].isEmpty else { return nil }
            let identifiers = parts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.contains(where: { $0.isEmpty }) else { return nil }
            prerelease = identifiers.map(String.init)
        } else {
            prerelease = []
        }
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for (left, right) in zip(lhs.numbers, rhs.numbers) where left != right {
            return left < right
        }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (Int(left), Int(right)) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct AvailableUpdate: Sendable {
    let version: String
    let releaseURL: URL
}

enum UpdateCheckResult: Sendable {
    case upToDate
    case available(AvailableUpdate)
    case noDownload
}

struct UpdateCheckResponse: Sendable {
    enum Source { case api, manifest }

    let result: UpdateCheckResult
    let source: Source

    init(_ result: UpdateCheckResult, source: Source = .api) {
        self.result = result
        self.source = source
    }
}

enum UpdateCheckError: Error {
    case invalidInstalledVersion
    case invalidResponse
    case invalidManifest
    case httpStatus(Int)
}

struct UpdateChecker {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let releasesURL = URL(string: "https://api.github.com/repos/M3tar/Breather/releases?per_page=30")!
    static let manifestURL = URL(string: "https://github.com/M3tar/Breather/releases/latest/download/update.json")!
    static let cooldownKey = "breather.update.apiRetryAfter"
    private static let logger = Logger(subsystem: "com.mercury.breather", category: "UpdateChecker")

    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let transport: Transport
    private let apiTimeout: TimeInterval
    private let manifestTimeout: TimeInterval
    private let totalTimeout: TimeInterval

    init(
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        apiTimeout: TimeInterval = 5,
        manifestTimeout: TimeInterval = 10,
        totalTimeout: TimeInterval = 15,
        transport: @escaping Transport = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw UpdateCheckError.invalidResponse
            }
            return (data, response)
        }
    ) {
        self.userDefaults = userDefaults
        self.now = now
        self.transport = transport
        self.apiTimeout = apiTimeout
        self.manifestTimeout = manifestTimeout
        self.totalTimeout = totalTimeout
    }

    @MainActor
    func check(installedVersion: String) async throws -> UpdateCheckResponse {
        try Task.checkCancellation()
        guard AppVersion(installedVersion) != nil else {
            throw UpdateCheckError.invalidInstalledVersion
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(totalTimeout))
        let retryAfter = userDefaults.object(forKey: Self.cooldownKey) as? Date
        if retryAfter.map({ $0 > now() }) != true {
            do {
                let (data, response) = try await Self.fetch(
                    Self.releasesURL, source: "api", timeout: min(apiTimeout, secondsUntil(deadline)), transport: transport
                )
                if let retryDate = Self.retryDate(response: response, data: data, now: now()) {
                    userDefaults.set(retryDate, forKey: Self.cooldownKey)
                }
                guard response.statusCode == 200 else {
                    throw UpdateCheckError.httpStatus(response.statusCode)
                }
                userDefaults.removeObject(forKey: Self.cooldownKey)
                let result = try Self.result(from: data, installedVersion: installedVersion)
                if case .noDownload = result {
                    Self.logger.info("API has no eligible stable DMG; trying manifest")
                } else {
                    return UpdateCheckResponse(result)
                }
            } catch {
                try Self.rethrowCancellation(error)
                Self.logger.notice("API check failed; trying manifest: \(String(describing: error), privacy: .private)")
            }
        } else {
            Self.logger.info("API cooldown active; using manifest")
        }

        try Task.checkCancellation()
        let (data, response) = try await Self.fetch(
            Self.manifestURL, source: "manifest", timeout: min(manifestTimeout, secondsUntil(deadline)), transport: transport
        )
        do {
            guard response.statusCode == 200 else {
                throw UpdateCheckError.httpStatus(response.statusCode)
            }
            return try UpdateCheckResponse(Self.manifestResult(from: data, installedVersion: installedVersion), source: .manifest)
        } catch {
            Self.logger.notice("Manifest check failed: \(String(describing: error), privacy: .private)")
            throw error
        }
    }

    private func secondsUntil(_ deadline: ContinuousClock.Instant) -> TimeInterval {
        let parts = ContinuousClock().now.duration(to: deadline).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    // The timeout covers redirects and the complete response, not just socket inactivity.
    // Cancelling the losing task also cancels URLSession's async request.
    private static func fetch(_ url: URL, source: String, timeout: TimeInterval, transport: @escaping Transport) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        guard timeout > 0 else { throw URLError(.timedOut) }
        var request = URLRequest(url: url)
        request.setValue(source == "api" ? "application/vnd.github+json" : "application/json", forHTTPHeaderField: "Accept")
        request.setValue("Breather-update-checker", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let outgoingRequest = request
        let started = ContinuousClock().now
        do {
            let response = try await withThrowingTaskGroup(of: (Data, HTTPURLResponse).self) { group in
                defer { group.cancelAll() }
                group.addTask { try await transport(outgoingRequest) }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw URLError(.timedOut)
                }
                return try await group.next()!
            }
            try Task.checkCancellation()
            let elapsed = String(describing: started.duration(to: ContinuousClock().now))
            Self.logger.info("Update source=\(source, privacy: .public) status=\(response.1.statusCode) duration=\(elapsed, privacy: .public)")
            return response
        } catch {
            let elapsed = String(describing: started.duration(to: ContinuousClock().now))
            Self.logger.notice("Update source=\(source, privacy: .public) duration=\(elapsed, privacy: .public) failed: \(String(describing: error), privacy: .private)")
            throw error
        }
    }

    private static func rethrowCancellation(_ error: Error) throws {
        try Task.checkCancellation()
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            throw CancellationError()
        }
    }

    static func retryDate(response: HTTPURLResponse, data: Data, now: Date) -> Date? {
        guard response.statusCode == 403 || response.statusCode == 429 else { return nil }
        let message = (try? JSONDecoder().decode(GitHubError.self, from: data))?.message.lowercased() ?? ""
        let limited = response.statusCode == 429
            || response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
            || message.contains("api rate limit exceeded") || message.contains("secondary rate limit")
        let retryHeader = response.value(forHTTPHeaderField: "Retry-After")
        guard limited || retryHeader != nil else { return nil }
        var dates: [Date] = []
        if let retryHeader {
            if let seconds = TimeInterval(retryHeader), seconds.isFinite, seconds >= 0 {
                dates.append(now.addingTimeInterval(seconds))
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                if let date = formatter.date(from: retryHeader) { dates.append(date) }
            }
        }
        if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
           let header = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let epoch = TimeInterval(header), epoch.isFinite {
            dates.append(Date(timeIntervalSince1970: epoch))
        }
        return dates.filter { $0 > now }.max() ?? now.addingTimeInterval(60)
    }

    static func isStableVersion(_ version: String) -> Bool {
        version.range(of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil
            && AppVersion(version) != nil
    }

    static func isReleaseURL(_ url: URL, tag: String) -> Bool {
        isGitHubURL(url, path: "/M3tar/Breather/releases/tag/\(tag)")
    }

    private static func isGitHubURL(_ url: URL, path: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.port == nil
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
            && url.path == path
    }

    private static func candidate(tag: String, releaseURL: URL, name: String, downloadURL: URL) -> AvailableUpdate? {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isStableVersion(version), isReleaseURL(releaseURL, tag: tag),
              name.lowercased().hasSuffix(".dmg"), !name.contains("/"), !name.contains("\\"),
              isGitHubURL(downloadURL, path: "/M3tar/Breather/releases/download/\(tag)/\(name)") else { return nil }
        return AvailableUpdate(version: version, releaseURL: releaseURL)
    }

    private static func compare(_ update: AvailableUpdate, installedVersion: String) throws -> UpdateCheckResult {
        guard let installed = AppVersion(installedVersion), let latest = AppVersion(update.version) else {
            throw UpdateCheckError.invalidInstalledVersion
        }
        return latest > installed ? .available(update) : .upToDate
    }

    static func result(from data: Data, installedVersion: String) throws -> UpdateCheckResult {
        guard AppVersion(installedVersion) != nil else { throw UpdateCheckError.invalidInstalledVersion }
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        let candidates = releases.compactMap { release -> AvailableUpdate? in
            guard !release.draft, !release.prerelease else { return nil }
            return release.assets.lazy.compactMap {
                candidate(tag: release.tagName, releaseURL: release.htmlURL, name: $0.name, downloadURL: $0.browserDownloadURL)
            }.first
        }
        guard let latest = candidates.max(by: { AppVersion($0.version)! < AppVersion($1.version)! }) else {
            return .noDownload
        }
        return try compare(latest, installedVersion: installedVersion)
    }

    static func manifestResult(from data: Data, installedVersion: String) throws -> UpdateCheckResult {
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        guard manifest.schemaVersion == 1, manifest.channel == "stable",
              isStableVersion(manifest.version),
              manifest.asset.name == "Breather-\(manifest.version).dmg",
              manifest.asset.sha256.range(of: #"\A[0-9a-f]{64}\z"#, options: .regularExpression) != nil,
              let update = candidate(tag: "v\(manifest.version)", releaseURL: manifest.releaseURL,
                                     name: manifest.asset.name, downloadURL: manifest.asset.downloadURL) else {
            throw UpdateCheckError.invalidManifest
        }
        return try compare(update, installedVersion: installedVersion)
    }
}

private struct GitHubError: Decodable {
    let message: String
}

private struct UpdateManifest: Decodable {
    let schemaVersion: Int
    let version: String
    let channel: String
    let releaseURL: URL
    let asset: Asset

    struct Asset: Decodable {
        let name: String
        let downloadURL: URL
        let sha256: String
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease, assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
