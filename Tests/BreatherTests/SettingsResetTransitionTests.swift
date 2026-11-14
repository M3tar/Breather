import XCTest
import AppKit
import Metal
@testable import Breather

@MainActor final class SettingsResetTransitionTests: XCTestCase {
    func testIncrementalCaptureHasNoHorizontalSeamsAtFractionalStripBoundaries() async throws {
        let gpu = try ResetHaloGPU()
        // 803 pt produces fractional strip edges with the production pixel budget;
        // 840 pt is the old fixture, whose edges happen to align at 2x.
        for (width, scale): (CGFloat, CGFloat) in [(803, 2), (840, 2), (803, 1)] {
            let host = NSView(frame: CGRect(x: 0, y: 0, width: width, height: 350))
            host.wantsLayer = true
            host.layer!.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.4, blue: 0.9, alpha: 1).cgColor
            let (frame, _) = try await ResetHaloCapture.capture(host: host, gpu: gpu, revision: 0, scale: scale,
                valid: { true }, requiresOpaqueContent: true)
            let image = frame.image, bytes = Array(frame.image.dataProvider!.data! as Data)
            let column = image.width / 2 * 4
            let reference = Array(bytes[(image.bytesPerRow + column)..<(image.bytesPerRow + column + 4)])
            let seams = (1..<(image.height - 1)).filter { y in
                let offset = y * image.bytesPerRow + column
                return Array(bytes[offset..<(offset + 4)]) != reference
            }
            XCTAssertTrue(seams.isEmpty, "Solid content has horizontal seams at rows \(seams), width=\(width), scale=\(scale)")
        }
    }

    func testHaloRevealsNewPixelsOnlyAfterTheArcReachesThem() throws {
        let gpu = try ResetHaloGPU()
        let size = CGSize(width: 256, height: 256)
        func solid(_ color: NSColor) throws -> MTLTexture {
            let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color.cgColor); context.fill(CGRect(origin: .zero, size: size))
            return try gpu.upload(context.makeImage()!)
        }
        let old = try solid(.red), new = try solid(.blue)
        func bytes(_ image: CGImage) -> [UInt8] { Array(image.dataProvider!.data! as Data) }
        let start = try gpu.renderImage(source: old, replacement: new, size: size, progress: 0)
        let end = try gpu.renderImage(source: old, replacement: new, size: size, progress: 1)
        XCTAssertEqual(bytes(start), bytes(try gpu.renderImage(source: old, size: size, progress: 0)))
        XCTAssertEqual(bytes(end), bytes(try gpu.renderImage(source: new, size: size, progress: 0)))
        let mid = try gpu.renderImage(source: old, replacement: new, size: size, progress: 0.1)
        let data = bytes(mid) // BGRA, top-left origin
        let ahead = 10 * mid.bytesPerRow + 10 * 4
        let behind = 240 * mid.bytesPerRow + 240 * 4
        XCTAssertGreaterThan(data[ahead + 2], 240, "The upper-left must still show the old red frame")
        XCTAssertLessThan(data[ahead], 10)
        XCTAssertGreaterThan(data[behind], 220, "The lower-right must reveal the new blue frame")
        XCTAssertLessThan(data[behind + 2], 30)
        XCTAssertEqual(data[ahead + 3], 255)
        XCTAssertEqual(data[behind + 3], 255)
    }

    func testOpaqueCaptureRejectsVisibleMetalButAllowsClippedMetal() async throws {
        let gpu = try ResetHaloGPU()
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        host.wantsLayer = true
        let clipped = CALayer(); clipped.frame = CGRect(x: 0, y: 0, width: 32, height: 32); clipped.masksToBounds = true
        let metal = CAMetalLayer(); metal.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        host.layer!.addSublayer(clipped); clipped.addSublayer(metal)
        do {
            _ = try await ResetHaloCapture.capture(host: host, gpu: gpu, revision: 0, scale: 1,
                valid: { true }, requiresOpaqueContent: true)
            XCTFail("A live hole must not expose already-restored settings ahead of the arc")
        } catch is ResetHaloError {} // Explicit visual fallback, never a transparent old cover.
        metal.isHidden = true
        _ = try await ResetHaloCapture.capture(host: host, gpu: gpu, revision: 0, scale: 1,
            valid: { true }, requiresOpaqueContent: true)
        metal.isHidden = false
        metal.frame.origin.x = 40
        let (frame, _) = try await ResetHaloCapture.capture(host: host, gpu: gpu, revision: 0, scale: 1,
            valid: { true }, requiresOpaqueContent: true)
        XCTAssertEqual(frame.size, host.bounds.size)
    }

    func testNativeMetalSnapshotsMatchTheirLiveShaders() async throws {
        let size = CGSize(width: 64, height: 32)
        let rain = RainGlassMetalView(animated: false)
        let snow = SnowfallMetalView(animated: false)
        let train = CloudTrainMetalView(animated: false)
        rain.drawableSize = size; snow.drawableSize = size; train.drawableSize = size
        let rainFrame = try await rain.captureMetalImage()
        let snowFrame = try await snow.captureMetalImage()
        let trainFrame = try await train.captureMetalImage()
        for frame in [rainFrame, snowFrame, trainFrame] {
            XCTAssertEqual(frame.image.width, 64); XCTAssertEqual(frame.image.height, 32)
            XCTAssertGreaterThan(frame.maximumWorkMS, 0)
        }
        let snowBytes = Array(snowFrame.image.dataProvider!.data! as Data)
        let snowReference = try XCTUnwrap(SnowfallRendering.renderedPixels(width: 64, height: 32,
            time: SnowfallRendering.stillFrameTime, fragmentName: "snowfallFragment"))
        XCTAssertEqual(snowBytes, snowReference, "Snow preserves orientation and premultiplied transparency")
        let rainBytes = Array(rainFrame.image.dataProvider!.data! as Data)
        let rainReference = try XCTUnwrap(RainGlassRendering.renderedPixels(width: 64, height: 32,
            time: RainGlassRendering.stillFrameTime))
        var error = 0.0
        for index in rainBytes.indices where index % 4 != 3 {
            let linear = Double(rainReference[index]) / 255
            let encoded = linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
            error += abs(Double(rainBytes[index]) - encoded * 255)
        }
        XCTAssertLessThan(error / Double(64 * 32 * 3), 2, "Rain uses the live sRGB attachment, without inversion or double gamma")
        let trainBytes = Array(trainFrame.image.dataProvider!.data! as Data)
        XCTAssertGreaterThan(Set(trainBytes).count, 40, "The actual cloud shader produces scene detail")
        let cancelled = Task { try await rain.captureMetalImage() }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("A cancelled snapshot must not publish pixels") }
        catch is CancellationError {}
    }

    func testResetCommitsOnceEvenWhenVisualIsUnavailable() {
        let transition = SettingsResetTransition()
        var commits = 0
        transition.prepareForConfirmation()
        transition.restore { commits += 1 }
        transition.restore { commits += 1 }
        transition.confirmationDismissed()
        XCTAssertEqual(commits, 1)
        XCTAssertEqual(transition.phase, .idle)
        XCTAssertFalse(transition.hasResources)
    }

    func testCancellationAndDetachRejectOldConfirmation() {
        let transition = SettingsResetTransition()
        var commits = 0
        transition.prepareForConfirmation()
        transition.confirmationDismissed()
        transition.restore { commits += 1 }
        transition.prepareForConfirmation()
        transition.detach()
        transition.restore { commits += 1 }
        XCTAssertEqual(commits, 0)
        XCTAssertFalse(transition.hasResources)
    }

    func testVisualInterruptionDoesNotCancelAuthorizedReset() {
        let transition = SettingsResetTransition()
        var commits = 0
        transition.prepareForConfirmation()
        transition.cancel("window-hidden")
        transition.restore { commits += 1 }
        XCTAssertEqual(commits, 1)
        XCTAssertFalse(transition.hasResources)
    }

    func testResetCancelsPendingTimerApplicationAndPreservesCurrentCycle() async throws {
        let suite = "SettingsResetTransitionTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = SettingsStore(userDefaults: UserDefaults(suiteName: suite)!)
        store.rules.workDuration = 25 * 60; store.activateSavedRulesForCurrentCycle()
        store.rules.workDuration = 45 * 60; store.settings.ruleChangeEffect = .immediate
        let application = SettingsRuleApplication()
        var applied = 0
        application.schedule(after: .milliseconds(20)) { applied += 1; store.activateSavedRulesForCurrentCycle() }
        let transition = SettingsResetTransition()
        transition.prepareForConfirmation()
        transition.restore { application.cancel(); store.restoreDefaults(for: .schedule) }
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(applied, 0)
        XCTAssertFalse(application.isWaiting)
        XCTAssertEqual(store.rules.workDuration, 30 * 60)
        XCTAssertEqual(store.currentCycleRules.workDuration, 25 * 60)
        XCTAssertEqual(store.settings.ruleChangeEffect, .nextCycle)
    }
}
