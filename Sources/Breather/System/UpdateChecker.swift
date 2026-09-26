import Foundation

struct AppVersion: Comparable {
    let numbers: [Int]
    let prerelease: [String]

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

struct AvailableUpdate {
    let version: String
    let releaseURL: URL
}

enum UpdateCheckResult {
    case upToDate
    case available(AvailableUpdate)
    case noDownload
}

enum UpdateCheckError: Error {
    case invalidInstalledVersion
    case invalidResponse
}

struct UpdateChecker {
    private let releasesURL = URL(
        string: "https://api.github.com/repos/M3tar/Breather/releases?per_page=30"
    )!

    func check(installedVersion: String) async throws -> UpdateCheckResult {
        guard AppVersion(installedVersion) != nil else {
            throw UpdateCheckError.invalidInstalledVersion
        }

        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Breather-update-checker", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw UpdateCheckError.invalidResponse
        }

        return try Self.result(from: data, installedVersion: installedVersion)
    }

    static func result(from data: Data, installedVersion: String) throws -> UpdateCheckResult {
        guard let installed = AppVersion(installedVersion) else {
            throw UpdateCheckError.invalidInstalledVersion
        }

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        let candidates = releases.compactMap { release -> (AppVersion, AvailableUpdate)? in
            guard !release.draft,
                  let version = AppVersion(release.tagName),
                  let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
                  release.htmlURL.host == "github.com",
                  asset.browserDownloadURL.host == "github.com" else { return nil }

            let displayVersion = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst()) : release.tagName
            return (version, AvailableUpdate(
                version: displayVersion,
                releaseURL: release.htmlURL
            ))
        }

        guard let latest = candidates.max(by: { $0.0 < $1.0 }) else {
            return .noDownload
        }
        return latest.0 > installed ? .available(latest.1) : .upToDate
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case assets
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
