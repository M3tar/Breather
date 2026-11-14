import UserNotifications
import XCTest
@testable import Breather

@MainActor
final class NotificationPermissionDetectionTests: XCTestCase {
    func testAuthorizedWithDesktopDisabledMatchesRealMacSettings() {
        // Captured from Breather Debug: allow notifications on, all display
        // locations off, sound on. alertSetting remains enabled.
        let status = NotificationPermissionStatus.resolve(
            authorization: .authorized, alertSetting: .enabled, alertStyle: .none
        )
        XCTAssertEqual(status, .alertsDisabled)
        XCTAssertTrue(status.canScheduleNotifications, "Sound-only notifications remain allowed")
        XCTAssertFalse(status.canPresentNotifications)
    }

    func testTemporaryAndPersistentDesktopAlertsRemainAuthorized() {
        for style in [UNAlertStyle.banner, .alert] {
            let status = NotificationPermissionStatus.resolve(
                authorization: .authorized, alertSetting: .enabled, alertStyle: style
            )
            XCTAssertEqual(status, .authorized)
            XCTAssertTrue(status.canPresentNotifications)
        }
    }

    func testDisabledAlertPermissionOverridesRetainedStyle() {
        let status = NotificationPermissionStatus.resolve(
            authorization: .authorized, alertSetting: .disabled, alertStyle: .banner
        )
        XCTAssertEqual(status, .alertsDisabled)
    }

    func testMissingAuthorizationTakesPriorityOverDesktopStyle() {
        XCTAssertEqual(NotificationPermissionStatus.resolve(
            authorization: .denied, alertSetting: .enabled, alertStyle: .none
        ), .denied)
        XCTAssertEqual(NotificationPermissionStatus.resolve(
            authorization: .notDetermined, alertSetting: .disabled, alertStyle: .none
        ), .notDetermined)
    }

    func testProvisionalPermissionAlsoChecksDesktopStyle() {
        XCTAssertEqual(NotificationPermissionStatus.resolve(
            authorization: .provisional, alertSetting: .enabled, alertStyle: .none
        ), .alertsDisabled)
        XCTAssertEqual(NotificationPermissionStatus.resolve(
            authorization: .provisional, alertSetting: .enabled, alertStyle: .banner
        ), .provisional)
    }

    func testFirstSettingsVisitRequestsAuthorizationAndReturnsUserDecision() async {
        for decision in [NotificationPermissionStatus.authorized, .denied] {
            let service = NotificationSettingsPreparationStub(status: .notDetermined, decision: decision)
            let status = await service.prepareToOpenSettings()
            XCTAssertEqual(status, decision)
            XCTAssertEqual(service.calls, ["check", "request"])

            service.calls = []
            _ = await service.prepareToOpenSettings()
            XCTAssertEqual(service.calls, ["check"], "Reopening settings must not request permission again")
        }
    }

    func testExistingPermissionOpensSettingsWithoutRequestingAgain() async {
        for current in [NotificationPermissionStatus.authorized, .denied, .alertsDisabled, .unavailable] {
            let service = NotificationSettingsPreparationStub(status: current, decision: .authorized)
            let status = await service.prepareToOpenSettings()
            XCTAssertEqual(status, current)
            XCTAssertEqual(service.calls, ["check"])
        }
    }
}

@MainActor
private final class NotificationSettingsPreparationStub: NotificationSettingsServicing {
    var status: NotificationPermissionStatus
    let decision: NotificationPermissionStatus
    var calls: [String] = []

    init(status: NotificationPermissionStatus, decision: NotificationPermissionStatus) {
        self.status = status
        self.decision = decision
    }

    func authorizationStatus() async -> NotificationPermissionStatus {
        calls.append("check")
        return status
    }

    func requestAuthorization() async -> NotificationPermissionStatus {
        calls.append("request")
        status = decision
        return decision
    }

    func sendPreviewNotification(playSound: Bool, soundEffect: RestSoundEffect) async -> NotificationPreviewResult {
        .failed
    }
}
