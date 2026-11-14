import Foundation
import XCTest
@testable import Breather

private actor UpdateHTTPStub {
    struct Reply: Sendable {
        var status = 200
        var body = ""
        var headers: [String: String] = [:]
        var delay: TimeInterval = 0
        var error: URLError.Code?
    }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    private(set) var cancellations = 0

    init(_ replies: [Reply]) { self.replies = replies }

    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let reply = replies.removeFirst()
        do {
            if reply.delay > 0 { try await Task.sleep(for: .seconds(reply.delay)) }
            try Task.checkCancellation()
        } catch {
            cancellations += 1
            throw error
        }
        if let error = reply.error { throw URLError(error) }
        return (Data(reply.body.utf8), HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/2", headerFields: reply.headers
        )!)
    }
}

@MainActor
final class UpdateFallbackTests: XCTestCase {
    private let suite = "UpdateFallbackTests.\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUp() async throws { defaults = UserDefaults(suiteName: suite)! }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: suite) }

    private static let api = """
    [{"tag_name":"v0.6.0","html_url":"https://github.com/M3tar/Breather/releases/tag/v0.6.0",
    "draft":false,"prerelease":false,"assets":[{"name":"Breather-0.6.0.dmg",
    "browser_download_url":"https://github.com/M3tar/Breather/releases/download/v0.6.0/Breather-0.6.0.dmg"}]}]
    """
    private static let manifest = """
    {"schemaVersion":1,"channel":"stable","version":"0.6.0",
    "releaseURL":"https://github.com/M3tar/Breather/releases/tag/v0.6.0",
    "asset":{"name":"Breather-0.6.0.dmg",
    "downloadURL":"https://github.com/M3tar/Breather/releases/download/v0.6.0/Breather-0.6.0.dmg",
    "sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}
    """

    private func checker(_ stub: UpdateHTTPStub, apiTimeout: Double = 5, totalTimeout: Double = 15,
                         now: @escaping () -> Date = Date.init) -> UpdateChecker {
        UpdateChecker(userDefaults: defaults, now: now, apiTimeout: apiTimeout, totalTimeout: totalTimeout,
                      transport: { try await stub.load($0) })
    }

    private func assertAvailable(_ response: UpdateCheckResponse, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .available(update) = response.result else { return XCTFail("Expected update", file: file, line: line) }
        XCTAssertEqual(update.version, "0.6.0", file: file, line: line)
    }

    func testAPISuccessDoesNotRequestFallback() async throws {
        let stub = UpdateHTTPStub([.init(body: Self.api)])
        let response = try await checker(stub).check(installedVersion: "0.5.0")
        assertAvailable(response)
        XCTAssertEqual(response.source, .api)
        let requests = await stub.requests
        XCTAssertEqual(requests.map(\.url), [UpdateChecker.releasesURL])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "User-Agent"), "Breather-update-checker")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
    }

    func testAPIErrorsAndNoCandidateFallBackExactlyOnce() async throws {
        let failures: [UpdateHTTPStub.Reply] = [
            .init(status: 403), .init(status: 429), .init(status: 500), .init(status: 404),
            .init(body: "not json"), .init(body: "[]"), .init(error: .timedOut),
            .init(body: Self.api.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true"))
        ]
        for failure in failures {
            defaults.removeObject(forKey: UpdateChecker.cooldownKey)
            let stub = UpdateHTTPStub([failure, .init(body: Self.manifest)])
            let response = try await checker(stub).check(installedVersion: "0.5.0")
            assertAvailable(response)
            XCTAssertEqual(response.source, .manifest)
            let requests = await stub.requests
            XCTAssertEqual(requests.map(\.url), [UpdateChecker.releasesURL, UpdateChecker.manifestURL])
        }
    }

    func testRateLimitPersistsAcrossCheckersAndExpires() async throws {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = date.addingTimeInterval(120)
        let stub = UpdateHTTPStub([
            .init(status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(reset.timeIntervalSince1970)"]),
            .init(body: Self.manifest), .init(body: Self.manifest), .init(body: Self.api)
        ])
        assertAvailable(try await checker(stub, now: { date }).check(installedVersion: "0.5.0"))
        XCTAssertEqual(defaults.object(forKey: UpdateChecker.cooldownKey) as? Date, reset)
        date.addTimeInterval(60)
        assertAvailable(try await checker(stub, now: { date }).check(installedVersion: "0.5.0"))
        date.addTimeInterval(61)
        assertAvailable(try await checker(stub, now: { date }).check(installedVersion: "0.5.0"))
        let urls = await stub.requests.map(\.url)
        XCTAssertEqual(urls, [UpdateChecker.releasesURL, UpdateChecker.manifestURL, UpdateChecker.manifestURL, UpdateChecker.releasesURL])
    }

    func testOrdinary403DoesNotSetCooldown() async throws {
        let stub = UpdateHTTPStub([.init(status: 403), .init(body: Self.manifest)])
        _ = try await checker(stub).check(installedVersion: "0.5.0")
        XCTAssertNil(defaults.object(forKey: UpdateChecker.cooldownKey))
    }

    func testRetryAfterSupportsSecondsHTTPDateAndSecondaryLimits() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func date(_ status: Int, _ headers: [String: String], body: String = "") -> Date? {
            UpdateChecker.retryDate(response: HTTPURLResponse(url: UpdateChecker.releasesURL, statusCode: status,
                httpVersion: nil, headerFields: headers)!, data: Data(body.utf8), now: now)
        }
        XCTAssertEqual(date(429, ["Retry-After": "90"]), now.addingTimeInterval(90))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        XCTAssertEqual(date(403, ["Retry-After": formatter.string(from: now.addingTimeInterval(180))]), now.addingTimeInterval(180))
        XCTAssertEqual(date(403, [:], body: "{\"message\":\"You have exceeded a secondary rate limit.\"}"), now.addingTimeInterval(60))
        XCTAssertNil(date(403, [:], body: "{\"message\":\"Forbidden\"}"))
        XCTAssertNil(date(200, ["X-RateLimit-Remaining": "0"]))
    }

    func testPerSourceTimeoutCancelsRequestAndFallsBack() async throws {
        let stub = UpdateHTTPStub([.init(body: Self.api, delay: 5), .init(body: Self.manifest)])
        assertAvailable(try await checker(stub, apiTimeout: 0.03).check(installedVersion: "0.5.0"))
        let cancellations = await stub.cancellations
        XCTAssertEqual(cancellations, 1)
    }

    func testOverallDeadlineBoundsSlowFallback() async throws {
        let stub = UpdateHTTPStub([.init(delay: 5), .init(delay: 5)])
        let start = ContinuousClock().now
        do {
            _ = try await checker(stub, apiTimeout: 0.03, totalTimeout: 0.08).check(installedVersion: "0.5.0")
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertLessThan(start.duration(to: ContinuousClock().now), .seconds(1))
        let requests = await stub.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertLessThan(requests[1].timeoutInterval, 0.08)
        let cancellations = await stub.cancellations
        XCTAssertEqual(cancellations, 2)
    }

    func testCancellationDoesNotStartFallback() async throws {
        let stub = UpdateHTTPStub([.init(delay: 5)])
        let checker = checker(stub)
        let task = Task { try await checker.check(installedVersion: "0.5.0") }
        while await stub.requests.isEmpty { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        let requests = await stub.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testInvalidInstalledVersionDoesNotRequestAnything() async {
        let stub = UpdateHTTPStub([])
        do { _ = try await checker(stub).check(installedVersion: "invalid"); XCTFail("Expected failure") }
        catch { guard case UpdateCheckError.invalidInstalledVersion = error else { return XCTFail("Wrong error") } }
        let requests = await stub.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testBothSourcesFailWithoutReportingUpToDate() async {
        for reply in [UpdateHTTPStub.Reply(status: 404), .init(body: "{}"), .init(error: .notConnectedToInternet)] {
            let stub = UpdateHTTPStub([.init(status: 503), reply])
            do { _ = try await checker(stub).check(installedVersion: "0.5.0"); XCTFail("Expected failure") }
            catch { }
            let requests = await stub.requests
            XCTAssertEqual(requests.count, 2)
        }
    }

    func testManifestValidationAndVersionComparison() throws {
        for version in ["0.6.0", "0.7.0"] {
            guard case .upToDate = try UpdateChecker.manifestResult(from: Data(Self.manifest.utf8), installedVersion: version) else {
                return XCTFail("Must not recommend downgrade")
            }
        }
        let invalid = [
            Self.manifest.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
            Self.manifest.replacingOccurrences(of: "\"stable\"", with: "\"beta\""),
            Self.manifest.replacingOccurrences(of: "0.6.0", with: "0.6.0-beta.1"),
            Self.manifest.replacingOccurrences(of: "0.6.0", with: "00.6.0"),
            Self.manifest.replacingOccurrences(of: "https://", with: "http://"),
            Self.manifest.replacingOccurrences(of: "M3tar/Breather", with: "someone/Other"),
            Self.manifest.replacingOccurrences(of: "github.com/", with: "github.com.evil.example/"),
            Self.manifest.replacingOccurrences(of: "Breather-0.6.0.dmg", with: "other.dmg"),
            Self.manifest.replacingOccurrences(of: String(repeating: "a", count: 64), with: "bad"),
            Self.manifest.replacingOccurrences(of: String(repeating: "a", count: 64), with: String(repeating: "a", count: 64) + "\\n")
        ]
        for text in invalid {
            XCTAssertThrowsError(try UpdateChecker.manifestResult(from: Data(text.utf8), installedVersion: "0.5.0"))
        }
    }

    func testOlderFallbackPreservesKnownUpdateAcrossRestartAndRetriesAfterOneHour() async throws {
        // Cover both "up to date" and a lower-but-still-newer available result.
        for manifestVersion in ["0.4.0", "0.5.0", "0.5.1"] {
            defaults.removePersistentDomain(forName: suite)
            var date = Date(timeIntervalSince1970: 1_800_000_000)
            let stub = UpdateHTTPStub([
                .init(body: Self.api), .init(status: 403),
                .init(body: Self.manifest.replacingOccurrences(of: "0.6.0", with: manifestVersion)),
                .init(body: Self.api.replacingOccurrences(of: "0.6.0", with: "0.7.0"))
            ])
            let checker = checker(stub, now: { date })
            func monitor() -> UpdateMonitor {
                UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0", now: { date },
                              checkRelease: { try await checker.check(installedVersion: $0) })
            }
            await monitor().checkNow()
            let lastSuccess = defaults.object(forKey: "breather.update.lastSuccessAt") as? Date
            date.addTimeInterval(1)
            let reloaded = monitor()
            await reloaded.checkNow()
            XCTAssertEqual(reloaded.availableUpdate?.version, "0.6.0")
            guard case let .available(update) = reloaded.status else { return XCTFail("Keep the known update") }
            XCTAssertEqual(update.version, "0.6.0")
            XCTAssertEqual(defaults.string(forKey: "breather.update.availableVersion"), "0.6.0")
            XCTAssertEqual(defaults.object(forKey: "breather.update.lastSuccessAt") as? Date, lastSuccess)
            XCTAssertEqual(defaults.object(forKey: "breather.update.nextCheckAt") as? Date, date.addingTimeInterval(3600))
            date.addTimeInterval(3599)
            await reloaded.checkIfDue()
            let beforeRetry = await stub.requests.count
            XCTAssertEqual(beforeRetry, 3)
            date.addTimeInterval(1)
            await reloaded.checkIfDue()
            XCTAssertEqual(reloaded.availableUpdate?.version, "0.7.0")
            XCTAssertEqual(defaults.object(forKey: "breather.update.nextCheckAt") as? Date, date.addingTimeInterval(86400))
        }
    }

    func testEqualOrNewerManifestIsSuccessful() async throws {
        for version in ["0.6.0", "0.7.0"] {
            defaults.removePersistentDomain(forName: suite)
            var date = Date(timeIntervalSince1970: 1_800_000_000)
            let stub = UpdateHTTPStub([.init(body: Self.api), .init(status: 403),
                .init(body: Self.manifest.replacingOccurrences(of: "0.6.0", with: version))])
            let checker = checker(stub)
            let monitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0", now: { date },
                                        checkRelease: { try await checker.check(installedVersion: $0) })
            await monitor.checkNow()
            date.addTimeInterval(1)
            await monitor.checkNow()
            XCTAssertEqual(monitor.availableUpdate?.version, version)
            XCTAssertEqual(defaults.object(forKey: "breather.update.lastSuccessAt") as? Date, date)
            XCTAssertEqual(defaults.object(forKey: "breather.update.nextCheckAt") as? Date, date.addingTimeInterval(86400))
        }
    }

    func testAPICanInvalidateWithdrawnUpdateAndUpgradeClearsCache() async throws {
        let stub = UpdateHTTPStub([.init(body: Self.api),
            .init(body: Self.api.replacingOccurrences(of: "0.6.0", with: "0.5.0"))])
        let checker = checker(stub)
        let monitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0",
                                    checkRelease: { try await checker.check(installedVersion: $0) })
        await monitor.checkNow()
        XCTAssertEqual(monitor.availableUpdate?.version, "0.6.0")
        await monitor.checkNow()
        guard case .upToDate = monitor.status else { return XCTFail("API can invalidate a withdrawn update") }
        XCTAssertNil(monitor.availableUpdate)
        XCTAssertNil(defaults.string(forKey: "breather.update.availableVersion"))

        defaults.set("0.6.0", forKey: "breather.update.availableVersion")
        defaults.set("https://github.com/M3tar/Breather/releases/tag/v0.6.0", forKey: "breather.update.availableURL")
        let upgraded = UpdateMonitor(userDefaults: defaults, installedVersion: "0.6.0")
        XCTAssertNil(upgraded.availableUpdate)
        XCTAssertNil(defaults.string(forKey: "breather.update.availableVersion"))
    }
}

@MainActor
final class UpdateRetryTests: XCTestCase {
    func testFailureRetriesAfterOneHourAndSuccessAfterOneDay() async throws {
        let suite = "UpdateRetryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        var calls = 0
        let monitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0", now: { date }) { _ in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return UpdateCheckResponse(.upToDate)
        }
        await monitor.checkIfDue()
        guard case .failed = monitor.status else { return XCTFail("Failure is not up to date") }
        date.addTimeInterval(3599)
        await monitor.checkIfDue()
        XCTAssertEqual(calls, 1)
        date.addTimeInterval(1)
        await monitor.checkIfDue()
        XCTAssertEqual(calls, 2)
        date.addTimeInterval(3600)
        await monitor.checkIfDue()
        XCTAssertEqual(calls, 2)
        await monitor.checkNow()
        XCTAssertEqual(calls, 3)
    }

    func testFailedAutomaticCheckDoesNotKeepUpToDateStatus() async throws {
        let suite = "UpdateStaleStatusTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var fail = false
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let monitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0", now: { date }) { _ in
            if fail { throw URLError(.timedOut) }
            return UpdateCheckResponse(.upToDate)
        }
        await monitor.checkNow()
        guard case .upToDate = monitor.status else { return XCTFail("Expected success") }
        let reloaded = UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0")
        guard case .idle = reloaded.status else { return XCTFail("Cached success is not a fresh check") }
        fail = true
        date.addTimeInterval(86400)
        await monitor.checkIfDue()
        guard case .failed = monitor.status else { return XCTFail("Must invalidate stale success") }
    }

    func testMigrationDiscardsCachedPrerelease() {
        let suite = "UpdateStableCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("0.6.0-beta.1", forKey: "breather.update.availableVersion")
        defaults.set("https://github.com/M3tar/Breather/releases/tag/v0.6.0-beta.1", forKey: "breather.update.availableURL")
        let monitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0")
        XCTAssertNil(monitor.availableUpdate)
        guard case .idle = monitor.status else { return XCTFail("Must not restore prerelease") }
        XCTAssertNil(defaults.string(forKey: "breather.update.availableVersion"))
    }

    func testCancellationDoesNotScheduleFailureRetry() async {
        let suite = "UpdateCancelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = UpdateMonitor(userDefaults: defaults, installedVersion: "0.5.0", checkRelease: { _ in throw CancellationError() })
        await monitor.checkNow()
        guard case .idle = monitor.status else { return XCTFail("Cancelled check should restore state") }
        XCTAssertNil(defaults.object(forKey: "breather.update.nextCheckAt"))
    }
}
