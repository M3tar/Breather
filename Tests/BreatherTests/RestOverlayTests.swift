import AppKit
import AVFoundation
import MetalKit
import SwiftUI
import Vision
import XCTest
@testable import Breather

@MainActor
final class RestOverlayTests: XCTestCase {
    func testCloudTrainSpeedDefaultsToHalfAndPersistsThroughSettingsStore() throws {
        XCTAssertEqual(AppSettings().cloudTrainPlaybackSpeed, .half)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).cloudTrainPlaybackSpeed, .half)
        let suite = "CloudTrainSpeedTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(userDefaults: defaults)
        for speed in CloudTrainPlaybackSpeed.allCases {
            store.settings.cloudTrainPlaybackSpeed = speed
            let loaded = SettingsStore(userDefaults: defaults).settings
            XCTAssertEqual(loaded.cloudTrainPlaybackSpeed, speed)
            XCTAssertEqual(RestOverlaySession(kind: .preview, settings: loaded, totalSeconds: 30).cloudTrainPlaybackSpeed, speed)
            XCTAssertEqual(RestOverlaySession(kind: .rest, settings: loaded, totalSeconds: 30).cloudTrainPlaybackSpeed, speed)
            XCTAssertEqual(RestThemeThumbnailConfiguration(mode: .cloudTrain, settings: loaded, duration: 30).cloudTrainPlaybackSpeed, speed)
        }
    }

    func testCloudTrainSpeedChangesStayContinuousAndPauseExcludesElapsedTime() {
        var clock = CloudTrainAnimationClock()
        clock.setSpeed(.half, at: 100)
        clock.setAnimated(true, at: 100)
        XCTAssertEqual(clock.time(at: 110), 5)
        clock.setSpeed(.normal, at: 110)
        XCTAssertEqual(clock.time(at: 110), 5)
        XCTAssertEqual(clock.time(at: 120), 15)
        clock.setAnimated(false, at: 120)
        clock.setSpeed(.threeQuarters, at: 130)
        XCTAssertEqual(clock.time(at: 140), 15)
        clock.setAnimated(true, at: 140)
        XCTAssertEqual(clock.time(at: 144), 18)
    }

    func testCloudTrainForegroundSpeedPersistsWithoutChangingOverallSpeed() throws {
        XCTAssertEqual(AppSettings().cloudTrainForegroundSpeed, .threeQuarters)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).cloudTrainForegroundSpeed, .threeQuarters)
        let suite = "CloudTrainForegroundTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(userDefaults: defaults)
        for speed in CloudTrainForegroundSpeed.allCases {
            store.settings.cloudTrainForegroundSpeed = speed
            let loaded = SettingsStore(userDefaults: defaults).settings
            XCTAssertEqual(loaded.cloudTrainForegroundSpeed, speed)
            XCTAssertEqual(loaded.cloudTrainPlaybackSpeed, .half)
            for kind in [RestOverlaySession.Kind.preview, .rest] {
                XCTAssertEqual(RestOverlaySession(kind: kind, settings: loaded, totalSeconds: 30).cloudTrainForegroundSpeed, speed)
            }
            XCTAssertEqual(RestThemeThumbnailConfiguration(mode: .cloudTrain, settings: loaded, duration: 30).cloudTrainForegroundSpeed, speed)
        }
    }

    func testCloudTrainForegroundClockCanChangeRateIndependently() {
        var scene = CloudTrainAnimationClock()
        var clouds = CloudTrainAnimationClock()
        clouds.setRate(0.5, at: 100)
        scene.setAnimated(true, at: 100)
        clouds.setAnimated(true, at: 100)
        XCTAssertEqual(scene.time(at: 110), 10)
        XCTAssertEqual(clouds.time(at: 110), 5)
        clouds.setRate(0.25, at: 110)
        XCTAssertEqual(clouds.time(at: 110), 5)
        XCTAssertEqual(clouds.time(at: 114), 6)
        XCTAssertEqual(scene.time(at: 114), 14)
        clouds.setAnimated(false, at: 114)
        clouds.setRate(0.75, at: 120)
        XCTAssertEqual(clouds.time(at: 130), 6)
        clouds.setAnimated(true, at: 130)
        XCTAssertEqual(clouds.time(at: 134), 9)
    }

    func testSelectedCurtainCardRevealsCountdownBeforeClosingFinishes() {
        XCTAssertEqual(
            RestThemeThumbnail.countdownDelay(mode: .curtain, animated: true),
            .milliseconds(2_200)
        )
        XCTAssertNotEqual(CurtainTiming.thumbnailContentRevealDelay, CurtainTiming.contentRevealDelay)
        XCTAssertNil(RestThemeThumbnail.countdownDelay(mode: .curtain, animated: false))
        XCTAssertNil(RestThemeThumbnail.countdownDelay(mode: .rainy, animated: true))
    }

    func testSelectingStaticMoonlightThemeDoesNotStartThumbnailAnimation() {
        XCTAssertFalse(RestThemePicker.shouldAnimateThumbnail(
            mode: .moonlight,
            isSelected: true,
            allowsAnimation: true
        ))
    }

    func testSelectedSunnyThemeThumbnailCreatesVideoPlayerInSettingsHost() throws {
        var settings = AppSettings()
        settings.restOverlayContentMode = .sunny
        let hostingView = NSHostingView(rootView: RestThemePicker(
            settings: .constant(settings),
            duration: 30,
            isResting: false
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 740, height: 800)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        XCTAssertNotNil(
            findAVPlayerSurface(in: hostingView),
            "The selected sunny theme card must instantiate its animated video surface"
        )
    }

    func testSelectedRainThemeThumbnailCreatesMetalSurfaceInSettingsHost() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        var settings = AppSettings()
        settings.restOverlayContentMode = .rainy
        let hostingView = NSHostingView(rootView: RestThemePicker(
            settings: .constant(settings),
            duration: 30,
            isResting: false
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 740, height: 800)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        let surface = try XCTUnwrap(
            findMetalSurface(in: hostingView),
            "The selected rainy theme card must instantiate its Metal rain surface"
        )
        XCTAssertTrue(surface.isRendererReady, "The rain shader must compile on the active Metal device")
    }

    func testSelectedCloudTrainThemeCreatesCompiledMetalSurface() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        var settings = AppSettings()
        settings.restOverlayContentMode = .cloudTrain
        let hostingView = NSHostingView(rootView: RestThemePicker(
            settings: .constant(settings), duration: 30, isResting: false
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 740, height: 800)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let surface = try XCTUnwrap(findCloudTrainSurface(in: hostingView))
        XCTAssertTrue(surface.isRendererReady, "The cloud train shader must compile on the active Metal device")
    }

    func testSelectedSnowThemeThumbnailCreatesMetalSurfaceInSettingsHost() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        var settings = AppSettings()
        settings.restOverlayContentMode = .snowy
        let hostingView = NSHostingView(rootView: RestThemePicker(
            settings: .constant(settings),
            duration: 30,
            isResting: false
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 740, height: 800)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        let surface = try XCTUnwrap(findSnowfallSurface(in: hostingView))
        XCTAssertTrue(surface.isRendererReady,
                      "The selected snowy theme card must compile its Metal snowfall surface")
    }

    func testSnowDesertBackgroundIsBundledAtScreenResolution() throws {
        let url = try XCTUnwrap(SnowyRestBackground.url)
        let image = try XCTUnwrap(SnowyRestBackground.image)
        XCTAssertGreaterThanOrEqual(image.representations.map(\.pixelsWide).max() ?? 0, 2_000)
        XCTAssertLessThan(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max, 700_000)
        XCTAssertEqual(RestAtmosphere.snowy.styleBackground, .moon)
    }

    func testOpeningKeepsClosedCurtainUntilFirstVideoFrameIsReady() {
        XCTAssertEqual(CurtainTiming.contentRevealDelay, .milliseconds(3_070))
        XCTAssertGreaterThan(CurtainTiming.openingHandoffFadeDuration, 0)
        XCTAssertTrue(CurtainPlaybackContinuity.keepsClosedPoster(
            phase: .opening,
            firstFrameReady: false
        ))
        XCTAssertFalse(CurtainPlaybackContinuity.keepsClosedPoster(
            phase: .opening,
            firstFrameReady: true
        ))
        XCTAssertFalse(CurtainPlaybackContinuity.keepsClosedPoster(
            phase: .closing,
            firstFrameReady: false
        ))
    }

    func testCompactDinosaurPreviewKeepsAnimating() {
        XCTAssertTrue(DinosaurRestContentView.animationEnabled(
            reduceMotion: false,
            compact: true,
            isPaused: false,
            isDismissing: false
        ))
    }

    func testRainUsesAQuietMotionRate() {
        XCTAssertLessThanOrEqual(RainMotion.timeScale, 12)
    }

    func testRainStaysWithinPerformanceBudget() {
        XCTAssertLessThanOrEqual(RainMotion.framesPerSecond, 30)
        XCTAssertLessThanOrEqual(RainMotion.totalDropCount, 200)
        XCTAssertEqual(RainGlassRendering.framesPerSecond, 30)
    }

    func testRainDropsMoveDownTheRenderedMetalSurface() throws {
        let width = 192
        let height = 192
        let early = try XCTUnwrap(RainGlassRendering.motionMask(width: width, height: height, time: 8))
        let later = try XCTUnwrap(RainGlassRendering.motionMask(width: width, height: height, time: 8.12))

        func similarity(at verticalShift: Int) -> Double {
            var sum = 0.0
            for y in 16..<(height - 16) {
                let shiftedY = y + verticalShift
                guard shiftedY >= 0, shiftedY < height else { continue }
                for x in 12..<(width - 12) {
                    let a = Double(early[(y * width + x) * 4]) / 255
                    let b = Double(later[(shiftedY * width + x) * 4]) / 255
                    sum += a * b
                }
            }
            return sum
        }

        let bestShift = (-18...18).max { similarity(at: $0) < similarity(at: $1) }
        XCTAssertGreaterThan(try XCTUnwrap(bestShift), 0,
                             "The actual Metal drop mask must travel toward the bottom of the screen")
    }

    func testRainMetalFrameHasVisibleRange() throws {
        let width = 960
        let height = 540
        let frameTime = Float(ProcessInfo.processInfo.environment["BREATHER_RAIN_TIME"] ?? "12") ?? 12
        let pixels = try XCTUnwrap(RainGlassRendering.renderedPixels(
            width: width, height: height, time: frameTime
        ))
        let luma = stride(from: 0, to: pixels.count, by: 4).map {
            Int(pixels[$0]) + Int(pixels[$0 + 1]) + Int(pixels[$0 + 2])
        }
        XCTAssertGreaterThan(try XCTUnwrap(luma.max()) - XCTUnwrap(luma.min()), 60)

        if let output = ProcessInfo.processInfo.environment["BREATHER_RAIN_PREVIEW"] {
            try writePreview(pixels: pixels, width: width, height: height, to: output)
        }
    }

    func testSnowRenderedFrameHasVisibleFlakes() throws {
        let width = 960
        let height = 540
        let pixels = try XCTUnwrap(SnowfallRendering.renderedPixels(
            width: width, height: height, time: 8,
            fragmentName: "snowfallFragment"
        ))
        if let output = ProcessInfo.processInfo.environment["BREATHER_SNOW_PREVIEW"] {
            let preview = try XCTUnwrap(SnowfallRendering.renderedPixels(
                width: width, height: height, time: 8
            ))
            try writePreview(pixels: preview, width: width, height: height, to: output)
        }
        let visiblePixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0 + 3] >= 20
        }.count
        XCTAssertGreaterThan(visiblePixels, 50, "The original light-snow field must render visible flakes")
        let unpremultipliedPixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] != pixels[$0 + 3]
                || pixels[$0 + 1] != pixels[$0 + 3]
                || pixels[$0 + 2] != pixels[$0 + 3]
        }.count
        XCTAssertEqual(unpremultipliedPixels, 0,
                       "Snow must composite over the existing pale-blue background without whitening it")
    }

    func testSnowflakesMoveDownTheRenderedMetalSurface() throws {
        let width = 320
        let height = 320
        let early = try XCTUnwrap(SnowfallRendering.renderedPixels(
            width: width, height: height, time: 8,
            fragmentName: "snowfallNearLayersMask"
        ))
        let later = try XCTUnwrap(SnowfallRendering.renderedPixels(
            width: width, height: height, time: 8.04,
            fragmentName: "snowfallNearLayersMask"
        ))

        func similarity(at verticalShift: Int) -> Double {
            var sum = 0.0
            for y in 20..<(height - 20) {
                let shiftedY = y + verticalShift
                guard shiftedY >= 0, shiftedY < height else { continue }
                for x in 20..<(width - 20) {
                    let a = Double(early[(y * width + x) * 4]) / 255
                    let b = Double(later[(shiftedY * width + x) * 4]) / 255
                    sum += a * b
                }
            }
            return sum
        }

        let bestShift = (-18...18).max { similarity(at: $0) < similarity(at: $1) }
        XCTAssertGreaterThan(try XCTUnwrap(bestShift), 0,
                             "The actual Metal snowfield must fall toward the bottom of the screen")
    }

    func testRainFramesStayVisibleThroughoutLongBreaks() throws {
        let width = 160
        let height = 90
        for time: Float in [0, 70, 80, 99, 101.9, 102, 600] {
            let pixels = try XCTUnwrap(RainGlassRendering.renderedPixels(
                width: width, height: height, time: time
            ))
            let center = ((height / 2) * width + width / 2) * 4
            let brightness = Int(pixels[center]) + Int(pixels[center + 1]) + Int(pixels[center + 2])
            XCTAssertGreaterThan(brightness, 24,
                                 "The rain glass must remain visible at time \(time)")
        }
    }

    func testRainDropsKeepMovingThroughLongBreaks() throws {
        for time: Float in [28, 70, 80, 100, 101.9, 102, 599] {
            let early = try XCTUnwrap(RainGlassRendering.motionMask(width: 192, height: 192, time: time))
            let later = try XCTUnwrap(RainGlassRendering.motionMask(width: 192, height: 192, time: time + 0.12))
            XCTAssertTrue(early != later, "Production rain droplets freeze at \(time)s")
        }
    }

    func testRainDoesNotRestartAtTheOldLoopBoundary() throws {
        let early = try XCTUnwrap(RainGlassRendering.motionMask(width: 192, height: 192, time: 101.999))
        let later = try XCTUnwrap(RainGlassRendering.motionMask(width: 192, height: 192, time: 102.001))
        let total = zip(early, later).enumerated().reduce(0) { sum, pixel in
            sum + (pixel.offset.isMultiple(of: 4) ? abs(Int(pixel.element.0) - Int(pixel.element.1)) : 0)
        }
        let meanDifference = Double(total) / Double(192 * 192)
        XCTAssertLessThan(meanDifference, 2, "Crossing 102s must not replace the rain field with its first frame")
    }

    func testTransitionSwitchDoesNotStopAtmospherePlayers() throws {
        try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      "Animated surface checks require system Reduce Motion to be off")
        for mode in [RestOverlayContentMode.windowLeaves, .sunny, .rainy, .snowy, .cloudTrain] {
            for fade in [false, true] {
                var now = 0.0
                var settings = AppSettings()
                settings.restOverlayContentMode = mode
                settings.restOverlayFadeAnimation = fade
                let session = RestOverlaySession(kind: .preview, settings: settings, totalSeconds: 30, uptime: { now })
                let host = NSHostingView(rootView: RestOverlayPreviewView(session: session, onClose: {})
                    .frame(width: 640, height: 360))
                host.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.08))
                for elapsed in [0.0, 28, 29] {
                    now = elapsed
                    session.updatePreview()
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.08))
                    if mode == .sunny || mode == .windowLeaves {
                        let player = (findAVPlayerSurface(in: host)?.layer as? AVPlayerLayer)?.player
                        XCTAssertNotNil(player, "Scene video missing for \(mode), transition=\(fade)")
                        XCTAssertEqual(player?.rate, 1, "Scene video paused with \(session.remainingSeconds)s left")
                    } else {
                        let surface = try XCTUnwrap(findAtmosphereMetalSurface(in: host))
                        XCTAssertFalse(surface.isPaused, "Scene paused for \(mode), transition=\(fade)")
                    }
                }
                session.setAnimationPaused(true)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.08))
                if let surface = findAtmosphereMetalSurface(in: host) {
                    XCTAssertTrue(surface.isPaused)
                } else {
                    XCTAssertNil(findAVPlayerSurface(in: host))
                }
                session.setAnimationPaused(false)
                session.beginDismissal()
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.08))
                if let surface = findAtmosphereMetalSurface(in: host) {
                    XCTAssertTrue(surface.isPaused)
                } else {
                    XCTAssertNil(findAVPlayerSurface(in: host))
                }
            }
        }
    }

    func testSunnyVideoKeepsPosterUnderneathUntilPlaybackAppears() {
        let plan = SunnyLeafBackdropPlan.make(animated: true, hasVideo: true, hasPoster: true)
        XCTAssertTrue(plan.showsPoster)
        XCTAssertTrue(plan.showsVideo)
        XCTAssertFalse(plan.showsFallback)
    }

    func testSnowfallUsesOriginalLightSnowLayerCount() {
        XCTAssertEqual(SnowfallRendering.layerCount, 50)
        XCTAssertEqual(SnowfallRendering.depth, 0.5)
        XCTAssertEqual(SnowfallRendering.width, 0.3)
        XCTAssertEqual(SnowfallRendering.speed, 0.6)
        XCTAssertLessThanOrEqual(SnowfallRendering.framesPerSecond, 30)
    }

    func testCurtainOpeningReusesTheExistingPlayerSurface() throws {
        let model = CurtainPhaseTestModel()
        let hostingView = NSHostingView(rootView: CurtainPhaseTestView(model: model))
        hostingView.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let closingSurface = try XCTUnwrap(findCurtainPlayer(in: hostingView))

        model.phase = .opening
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let openingSurface = try XCTUnwrap(findCurtainPlayer(in: hostingView))

        XCTAssertTrue(
            closingSurface === openingSurface,
            "Changing direction must not remove the rendered surface between video items"
        )
    }

    func testCurtainPreviewCountdownBeginsAfterClosingFilm() {
        var now = 100.0
        var settings = AppSettings()
        settings.restOverlayContentMode = .curtain
        settings.restOverlayFadeAnimation = true
        let session = RestOverlaySession(
            kind: .preview,
            settings: settings,
            totalSeconds: 30,
            uptime: { now }
        )

        now = 103
        session.updatePreview()
        XCTAssertEqual(session.remainingSeconds, 30)

        now = 104.1
        session.updatePreview()
        XCTAssertEqual(session.remainingSeconds, 29)
    }

    func testCurtainRestCountdownBeginsAfterClosingFilm() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.settings.restOverlayContentMode = .curtain
        fixture.store.settings.restOverlayFadeAnimation = true
        fixture.store.rules.shortBreakDuration = 30
        fixture.store.activateSavedRulesForCurrentCycle()

        fixture.scheduler.startRestNow()
        fixture.clock.now.addTimeInterval(1)
        fixture.scheduler.tick()
        XCTAssertEqual(fixture.scheduler.remainingSeconds, 30)

        fixture.clock.now.addTimeInterval(2.2)
        fixture.scheduler.tick()
        XCTAssertEqual(fixture.scheduler.remainingSeconds, 29)
    }

    func testMissingAndUnknownContentPreserveOtherSettings() throws {
        XCTAssertEqual(AppSettings().restOverlayBackground, .sun)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).restOverlayBackground, .sun)
        let savedSolid = try JSONDecoder().decode(AppSettings.self,
            from: Data(#"{"restOverlayBackground":"solid","restOverlayTranslucentBackground":true}"#.utf8))
        XCTAssertEqual(savedSolid.restOverlayBackground, .solid)
        XCTAssertTrue(savedSolid.restOverlayTranslucentBackground)
        for payload in [
            #"{"restOverlayBackground":"moon","snoozeDuration":420}"#,
            #"{"restOverlayContentMode":"future","restOverlayBackground":"moon","snoozeDuration":420}"#
        ] {
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(payload.utf8))
            XCTAssertEqual(settings.restOverlayContentMode, .classic)
            XCTAssertEqual(settings.restOverlayBackground, .moon)
            XCTAssertEqual(settings.snoozeDuration, 420)
            XCTAssertTrue(settings.rainAmbienceEnabled)
        }
        var settings = AppSettings()
        settings.restOverlayContentMode = .dinosaur
        settings.restOverlayBackground = .sun
        settings.curtainPalette = .blackCherry
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(settings, decoded)
        XCTAssertEqual(decoded.curtainPalette, .blackCherry)

        let migrated = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"restOverlayContentMode":"sheerLinen","restOverlayBackground":"moon","restOverlayTranslucentBackground":true}"#.utf8)
        )
        XCTAssertEqual(migrated.restOverlayContentMode, .classic)
        XCTAssertEqual(migrated.restOverlayBackground, .linen)
        XCTAssertFalse(migrated.restOverlayTranslucentBackground)
    }

    func testRainPreviewStartsAndStopsAmbientSoundWhileSnowStaysSilent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.settings.restOverlayContentMode = .rainy
        fixture.store.settings.rainAmbienceEnabled = true

        fixture.controller.preview()
        XCTAssertEqual(fixture.ambientSound.playRainCount, 1)
        let stopCountBeforeClose = fixture.ambientSound.stopCount
        fixture.controller.closePresentation(id: try XCTUnwrap(fixture.controller.session?.id))
        XCTAssertGreaterThan(fixture.ambientSound.stopCount, stopCountBeforeClose)

        fixture.store.settings.restOverlayContentMode = .snowy
        fixture.controller.preview()
        XCTAssertEqual(fixture.ambientSound.playRainCount, 1)
    }

    func testRainPreviewRespectsDisabledAmbientSound() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.settings.restOverlayContentMode = .rainy
        fixture.store.settings.rainAmbienceEnabled = false

        fixture.controller.preview()

        XCTAssertEqual(fixture.ambientSound.playRainCount, 0)
    }

    func testSessionFreezesPresentationAndPausesMonotonicAnimationClock() {
        var now = 100.0
        var settings = AppSettings()
        settings.restOverlayContentMode = .dinosaur
        settings.restOverlayBackground = .moon
        settings.restOverlaySubtitle = .random
        let session = RestOverlaySession(kind: .preview, settings: settings, totalSeconds: 60, uptime: { now })
        let subtitle = session.copy.subtitle
        settings.restOverlayContentMode = .classic
        XCTAssertEqual(session.contentMode, .dinosaur)
        XCTAssertEqual(session.background, .solid)
        now = 104
        session.updatePreview()
        XCTAssertEqual(session.remainingSeconds, 56)
        session.setAnimationPaused(true)
        now = 150
        session.updatePreview()
        XCTAssertEqual(session.remainingSeconds, 56)
        session.setAnimationPaused(false)
        now = 151
        session.updatePreview()
        XCTAssertEqual(session.animationElapsed, 5)
        XCTAssertEqual(session.remainingSeconds, 55)
        XCTAssertEqual(session.copy.subtitle, subtitle)
        session.beginDismissal()
        now = 190
        session.updateRemaining(1800)
        XCTAssertEqual(session.formattedTime, "00:55")
        XCTAssertEqual(session.animationElapsed, 5)
    }

    func testDinosaurKeepsMovingThroughFinalSecondsUntilDismissal() {
        var settings = AppSettings()
        settings.restOverlayContentMode = .dinosaur
        for kind in [RestOverlaySession.Kind.rest, .preview] {
            for duration in [10, 30, 60, 600] {
                // At 28s, seed 1 is walking and seed 42 is mid-jump.
                for seed: UInt64 in [1, 42] {
                    var now = 0.0
                    let session = RestOverlaySession(
                        kind: kind, settings: settings, totalSeconds: duration,
                        seed: seed, uptime: { now }
                    )
                    var previous: DinosaurSceneModel.Frame?
                    for step in 0..<30 {
                        now = Double(duration) - 3 + Double(step) / 10
                        if kind == .preview {
                            session.updatePreview()
                        } else {
                            session.updateRemaining(Int(ceil(Double(duration) - now)))
                        }
                        let frame = session.scene.frame(
                            elapsed: session.animationElapsed, animated: true
                        )
                        XCTAssertFalse(session.isDismissing)
                        XCTAssertGreaterThan(session.remainingSeconds, 0)
                        XCTAssertNotEqual(frame.pose, .standing, "Stopped at \(now)s of \(duration)s")
                        if let previous {
                            XCTAssertNotEqual(frame.groundOffset, previous.groundOffset,
                                              "Frozen at \(now)s of \(duration)s")
                        }
                        previous = frame
                    }
                    now = Double(duration)
                    if kind == .preview {
                        session.updatePreview()
                    } else {
                        session.updateRemaining(0)
                    }
                    XCTAssertEqual(session.remainingSeconds, 0)
                    session.beginDismissal()
                    let stoppedElapsed = session.animationElapsed
                    now += 10
                    XCTAssertEqual(session.animationElapsed, stoppedElapsed)
                    XCTAssertFalse(DinosaurRestContentView.animationEnabled(
                        reduceMotion: false, compact: false,
                        isPaused: session.isAnimationPaused, isDismissing: session.isDismissing
                    ))
                }
            }
        }
    }

    func testDinosaurWithOneSecondRemainingStillMoves() {
        var now = 0.0
        var settings = AppSettings()
        settings.restOverlayContentMode = .dinosaur
        let session = RestOverlaySession(
            kind: .rest, settings: settings, totalSeconds: 30,
            remainingSeconds: 1, seed: 1, uptime: { now }
        )
        let before = session.scene.frame(elapsed: session.animationElapsed, animated: true)
        now = 0.1
        session.updateRemaining(1)
        let after = session.scene.frame(elapsed: session.animationElapsed, animated: true)
        XCTAssertNotEqual(after.pose, .standing)
        XCTAssertNotEqual(before.groundOffset, after.groundOffset)
    }

    func testDurationDoesNotStretchStrideOrJumpAndEveryVisibleCrossingClearsCactus() {
        let model = DinosaurSceneModel(seed: 42)
        for duration in [10.0, 30, 60, 600] {
            let peak = model.frame(elapsed: 4, animated: true)
            XCTAssertEqual(peak.pose, .jumping)
            XCTAssertEqual(peak.jumpHeight, 46, accuracy: 0.001)
            let stride = model.frame(elapsed: 1, animated: true)
            XCTAssertEqual(stride.pose, .walkA)
            for elapsed in Swift.stride(from: 0.0, through: duration, by: 1.0 / 60) {
                let frame = model.frame(elapsed: elapsed, animated: true)
                for obstacle in frame.obstacles where obstacle.x < DinosaurSceneModel.dinosaurX + DinosaurSceneModel.dinosaurWidth
                    && obstacle.x + obstacle.width > DinosaurSceneModel.dinosaurX {
                    XCTAssertGreaterThan(frame.jumpHeight, obstacle.height, "Collision at \(elapsed)s of \(duration)s")
                }
            }
            XCTAssertNotEqual(model.frame(elapsed: duration, animated: true).pose, .standing)
        }
        let a = model.frame(elapsed: 1, animated: false)
        let b = model.frame(elapsed: 999, animated: false)
        XCTAssertEqual(a.pose, .standing)
        XCTAssertEqual(a.obstacles, b.obstacles)
        XCTAssertEqual(a.groundOffset, b.groundOffset)
    }

    func testDelayedSchedulerKeepsDinosaurMovingUntilDismissal() {
        var now = 0.0
        var settings = AppSettings()
        settings.restOverlayContentMode = .dinosaur
        let session = RestOverlaySession(kind: .rest, settings: settings, totalSeconds: 30, seed: 42, uptime: { now })
        var previous: DinosaurSceneModel.Frame?
        // Animation time can pass the planned duration while the scheduler still has time remaining.
        for (elapsed, remaining) in [(29.0, 10), (30, 9), (37, 2), (38, 1), (39, 0)] {
            now = elapsed
            session.updateRemaining(remaining)
            let frame = session.scene.frame(elapsed: session.animationElapsed, animated: true)
            XCTAssertEqual(session.remainingSeconds, remaining)
            XCTAssertNotEqual(frame.pose, .standing)
            if let previous { XCTAssertNotEqual(frame.groundOffset, previous.groundOffset) }
            previous = frame
        }
        session.beginDismissal()
        now = 45
        XCTAssertEqual(session.animationElapsed, 39)
    }

    func testDinosaurDismissalStopsImmediatelyDuringJump() {
        var now = 0.0
        var settings = AppSettings()
        settings.restOverlayContentMode = .dinosaur
        let session = RestOverlaySession(kind: .rest, settings: settings, totalSeconds: 30, seed: 42, uptime: { now })
        now = 4
        session.updateRemaining(0)
        let before = session.scene.frame(elapsed: session.animationElapsed, animated: true)
        XCTAssertEqual(before.pose, .jumping)
        XCTAssertEqual(before.jumpHeight, 46, accuracy: 0.001)
        session.beginDismissal()
        XCTAssertTrue(session.isDismissing)
        XCTAssertTrue(session.isAnimationPaused)
        now = 5
        let after = session.scene.frame(elapsed: session.animationElapsed, animated: true)
        XCTAssertEqual(session.animationElapsed, 4)
        XCTAssertEqual(session.remainingSeconds, 0)
        XCTAssertEqual(after.jumpHeight, before.jumpHeight)
        XCTAssertEqual(after.groundOffset, before.groundOffset)
        XCTAssertEqual(after.obstacles, before.obstacles)
    }

    func testPreviewClosesAutomaticallyWithoutChangingScheduler() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.settings.restOverlayContentMode = .dinosaur
        fixture.store.rules.shortBreakDuration = 1
        let remaining = fixture.scheduler.remainingSeconds
        fixture.controller.preview()
        let preview = try XCTUnwrap(fixture.controller.session)
        for _ in 0..<30 where fixture.controller.session != nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(fixture.controller.session)
        XCTAssertTrue(fixture.controller.windows.isEmpty)
        XCTAssertEqual(preview.remainingSeconds, 0)
        XCTAssertTrue(preview.isDismissing)
        XCTAssertEqual(fixture.scheduler.remainingSeconds, remaining)
        XCTAssertEqual(fixture.scheduler.state, .working)
        XCTAssertEqual(fixture.scheduler.consecutiveMissedBreaks, 0)
    }

    func testSnowEntranceWaitsForRenderedFrameWithoutDeferringRestCountdown() async throws {
        let fixture = try Fixture(presentsWindows: true)
        defer { fixture.cleanUp() }
        fixture.screens = [RestOverlayScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600))]
        fixture.store.settings.restOverlayContentMode = .snowy
        fixture.store.settings.restOverlayFadeAnimation = true
        fixture.store.activateSavedRulesForCurrentCycle()
        var readyAt: TimeInterval?
        var hadRenderedFrame = false
        fixture.controller.onDiagnosticChange = { [weak fixture] reason, _ in
            guard reason == "entranceStarted", let fixture else { return }
            readyAt = CACurrentMediaTime()
            hadRenderedFrame = fixture.controller.windows[1]?.contentView.flatMap(self.findSnowfallSurface)?.hasRenderedFirstFrame == true
        }
        fixture.scheduler.startRestNow()
        let panel = try XCTUnwrap(fixture.controller.windows[1])
        fixture.clock.now.addTimeInterval(1)
        fixture.scheduler.tick()
        XCTAssertEqual(fixture.controller.session?.remainingSeconds, 29)
        for _ in 0..<100 where readyAt == nil { try await Task.sleep(for: .milliseconds(10)) }
        let started = try XCTUnwrap(readyAt)
        XCTAssertTrue(hadRenderedFrame, "The real GPU frame must be ready when the visible fade starts")
        try await Task.sleep(for: .milliseconds(220))
        let elapsed = CACurrentMediaTime() - started
        XCTAssertLessThan(elapsed, 0.4)
        XCTAssertGreaterThan(panel.alphaValue, 0.05)
        XCTAssertLessThan(panel.alphaValue, 0.85, "The entrance should retain a visible middle phase")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.01)
    }

    func testSnowEntranceCancellationCannotReviveReplacedPreview() async throws {
        let fixture = try Fixture(presentsWindows: true)
        defer { fixture.cleanUp() }
        fixture.screens = [RestOverlayScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600))]
        fixture.store.settings.restOverlayContentMode = .snowy
        fixture.store.settings.restOverlayFadeAnimation = true
        fixture.controller.preview()
        let first = try XCTUnwrap(fixture.controller.session)
        let oldPanel = try XCTUnwrap(fixture.controller.windows[1])
        XCTAssertTrue(fixture.controller.handleEscape(id: first.id))
        XCTAssertNil(fixture.controller.session)
        fixture.controller.preview()
        let replacement = try XCTUnwrap(fixture.controller.session)
        let newPanel = try XCTUnwrap(fixture.controller.windows[1])
        XCTAssertNotEqual(first.id, replacement.id)
        XCTAssertFalse(oldPanel === newPanel)
        try await Task.sleep(for: .milliseconds(850))
        XCTAssertNil(oldPanel.contentView)
        XCTAssertFalse(oldPanel.isVisible)
        XCTAssertEqual(fixture.controller.session?.id, replacement.id)
        XCTAssertEqual(newPanel.alphaValue, 1, accuracy: 0.01)

        // Also interrupt while the visible fade is in progress.
        fixture.controller.preview()
        let third = try XCTUnwrap(fixture.controller.session)
        let thirdPanel = try XCTUnwrap(fixture.controller.windows[1])
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertTrue(fixture.controller.handleEscape(id: third.id))
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertNil(fixture.controller.session)
        XCTAssertFalse(thirdPanel.isVisible)
        XCTAssertNil(thirdPanel.contentView)
    }

    func testSnowEntranceBypassesFadeWhenDisabledOrMotionIsReduced() async throws {
        for (fade, reducedMotion) in [(false, false), (true, true)] {
            let fixture = try Fixture(reduceMotion: reducedMotion, presentsWindows: true)
            defer { fixture.cleanUp() }
            fixture.screens = [RestOverlayScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600))]
            fixture.store.settings.restOverlayContentMode = .snowy
            fixture.store.settings.restOverlayFadeAnimation = fade
            var entranceCount = 0
            fixture.controller.onDiagnosticChange = { reason, _ in
                if reason == "entranceStarted" { entranceCount += 1 }
            }
            fixture.controller.preview()
            let panel = try XCTUnwrap(fixture.controller.windows[1])
            XCTAssertEqual(panel.alphaValue, 1)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(entranceCount, 0)
            XCTAssertEqual(panel.alphaValue, 1)
            if !reducedMotion {
                XCTAssertFalse(try XCTUnwrap(panel.contentView.flatMap(findSnowfallSurface)).isPaused)
            }
        }
    }

    func testPreviewIsIsolatedAndStaleCloseCannotDismissRealRest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.rules.shortBreakDuration = 60
        let workRemaining = fixture.scheduler.remainingSeconds
        fixture.controller.preview()
        let preview = try XCTUnwrap(fixture.controller.session)
        XCTAssertEqual(preview.remainingSeconds, 60)
        XCTAssertEqual(preview.kind, .preview)
        XCTAssertEqual(fixture.scheduler.state, .working)
        XCTAssertEqual(fixture.scheduler.remainingSeconds, workRemaining)
        XCTAssertEqual(fixture.scheduler.consecutiveMissedBreaks, 0)
        fixture.scheduler.startRestNow()
        let rest = try XCTUnwrap(fixture.controller.session)
        XCTAssertEqual(rest.kind, .rest)
        XCTAssertNotEqual(rest.id, preview.id)
        fixture.controller.closePresentation(id: preview.id)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(fixture.controller.session?.id, rest.id)
        fixture.controller.preview()
        XCTAssertEqual(fixture.controller.session?.id, rest.id)
        XCTAssertTrue(fixture.controller.availability.isResting)
        fixture.scheduler.tick()
        XCTAssertEqual(rest.remainingSeconds, fixture.scheduler.remainingSeconds)
    }

    func testCompletionFreezesZeroAndLivePermissionsGuardOverlayActions() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.settings.restOverlayContentMode = .dinosaur
        fixture.store.rules.shortBreakDuration = 10
        fixture.scheduler.applyCurrentRulesToCurrentCycle()
        fixture.scheduler.startRestNow()
        let rest = try XCTUnwrap(fixture.controller.session)
        fixture.store.settings.strictMode = true
        fixture.controller.snoozeFromOverlay(id: rest.id)
        fixture.controller.skipFromOverlay(id: rest.id)
        XCTAssertEqual(fixture.controller.session?.id, rest.id)
        for _ in 0..<10 { fixture.scheduler.tick() }
        XCTAssertNil(fixture.controller.session)
        XCTAssertEqual(rest.formattedTime, "00:00")
        XCTAssertTrue(rest.isDismissing)
        XCTAssertEqual(fixture.scheduler.state, .working)
        XCTAssertFalse(fixture.controller.availability.isResting)

        fixture.store.settings.strictMode = false
        fixture.scheduler.startRestNow()
        let second = try XCTUnwrap(fixture.controller.session)
        fixture.store.settings.allowSkip = false
        fixture.controller.skipFromOverlay(id: second.id)
        XCTAssertEqual(fixture.scheduler.state, .resting)
        fixture.controller.snoozeFromOverlay(id: second.id)
        XCTAssertEqual(fixture.scheduler.state, .snoozing)
        XCTAssertNil(fixture.controller.session)
        XCTAssertEqual(second.remainingSeconds, 10)
    }

    func testAllThemesFinishWithEitherTransitionSettingAndReducedMotion() throws {
        for mode in RestOverlayContentMode.allCases {
            for fade in [false, true] {
                for reduceMotion in [false, true] {
                    let fixture = try Fixture(reduceMotion: reduceMotion)
                    defer { fixture.cleanUp() }
                    fixture.store.settings.restOverlayContentMode = mode
                    fixture.store.settings.restOverlayFadeAnimation = fade
                    fixture.store.rules.shortBreakDuration = 30
                    fixture.store.activateSavedRulesForCurrentCycle()
                    fixture.scheduler.startRestNow()
                    let session = try XCTUnwrap(fixture.controller.session)
                    for step in 1...30 {
                        fixture.clock.now.addTimeInterval(1)
                        if step == 1 && mode == .curtain && fade && !reduceMotion {
                            fixture.clock.now.addTimeInterval(CurtainTiming.closingDuration)
                        }
                        fixture.scheduler.tick()
                        if step < 30 {
                            XCTAssertEqual(session.remainingSeconds, 30 - step)
                            XCTAssertEqual(fixture.controller.session?.id, session.id)
                            XCTAssertFalse(session.isDismissing)
                        }
                    }
                    XCTAssertEqual(session.remainingSeconds, 0)
                    XCTAssertTrue(session.isDismissing)
                    XCTAssertTrue(session.isAnimationPaused)
                    XCTAssertNil(fixture.controller.session)
                    XCTAssertTrue(fixture.controller.windows.isEmpty)
                    XCTAssertEqual(fixture.scheduler.state, .working)
                }
            }
        }
    }

    func testScreenChangesKeepOneSessionAndReassignOnlyMissingKeyboardScreen() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.scheduler.startRestNow()
        let session = try XCTUnwrap(fixture.controller.session)
        XCTAssertEqual(fixture.controller.keyboardScreenID, 2)
        XCTAssertEqual(fixture.controller.windows.count, 2)
        let primary = fixture.controller.windows[1]
        fixture.screens = [RestOverlayScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1024, height: 768))]
        fixture.controller.reconcileScreens()
        XCTAssertEqual(fixture.controller.keyboardScreenID, 1)
        XCTAssertEqual(fixture.controller.windows.count, 1)
        XCTAssertTrue(fixture.controller.windows[1] === primary)
        XCTAssertEqual(primary?.frame.size.width, 1024)
        fixture.screens.append(RestOverlayScreen(id: 3, frame: CGRect(x: 1024, y: 0, width: 800, height: 600)))
        fixture.controller.reconcileScreens()
        XCTAssertEqual(fixture.controller.keyboardScreenID, 1)
        XCTAssertEqual(fixture.controller.session?.id, session.id)
        XCTAssertEqual(fixture.controller.windows.count, 2)
        fixture.controller.skipFromOverlay(id: session.id)
        XCTAssertTrue(fixture.controller.windows.isEmpty)
        XCTAssertNil(fixture.controller.keyboardScreenID)
        XCTAssertEqual(fixture.scheduler.state, .working)
    }

    func testEveryDisplayUsesTheSameDinosaurSessionAcrossHotPlug() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.settings.restOverlayContentMode = .dinosaur
        fixture.scheduler.startRestNow()
        let session = try XCTUnwrap(fixture.controller.session)
        let originalIDs = Set(fixture.controller.windows.keys)
        XCTAssertEqual(originalIDs, [1, 2])

        func displayedSessions() throws -> [RestOverlaySession] {
            try fixture.controller.windows.values.map { panel in
                let hosting = try XCTUnwrap(panel.contentView as? NSHostingView<RestOverlayScreenView>)
                return hosting.rootView.session
            }
        }

        // Neither screen receives an animation opt-out. Both actual hosting roots
        // share the clock, scene seed, countdown, pause and dismissal state.
        for displayed in try displayedSessions() {
            XCTAssertTrue(displayed === session)
            XCTAssertEqual(displayed.contentMode, .dinosaur)
            XCTAssertFalse(displayed.isAnimationPaused)
        }
        let before = session.animationElapsed
        fixture.screens.removeAll { $0.id == 2 }
        fixture.controller.reconcileScreens()
        fixture.screens.append(RestOverlayScreen(id: 2, frame: CGRect(x: 1024, y: 0, width: 1920, height: 1080)))
        fixture.controller.reconcileScreens()
        XCTAssertEqual(Set(fixture.controller.windows.keys), originalIDs)
        XCTAssertGreaterThanOrEqual(session.animationElapsed, before)
        session.setAnimationPaused(true)
        for displayed in try displayedSessions() {
            XCTAssertTrue(displayed === session)
            XCTAssertTrue(displayed.isAnimationPaused)
            XCTAssertEqual(displayed.animationElapsed, session.animationElapsed)
        }
        session.setAnimationPaused(false)
        let displayed = try displayedSessions()
        fixture.controller.closePresentation(id: session.id)
        XCTAssertTrue(displayed.allSatisfy(\.isDismissing))
        XCTAssertTrue(fixture.controller.windows.isEmpty)
    }

    func testSettingsSnapshotAndImmediatelyAppliedRulesStartNewPresentation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.settings.restOverlayContentMode = .dinosaur
        fixture.scheduler.startRestNow()
        let session = try XCTUnwrap(fixture.controller.session)
        fixture.store.settings.restOverlayContentMode = .classic
        fixture.store.rules.shortBreakDuration = 60
        XCTAssertEqual(session.contentMode, .dinosaur)
        XCTAssertEqual(session.totalSeconds, 30)
        fixture.scheduler.applyCurrentRulesToCurrentCycle()
        XCTAssertNotEqual(fixture.controller.session?.id, session.id)
        XCTAssertEqual(fixture.controller.session?.totalSeconds, 60)
        XCTAssertEqual(fixture.controller.session?.contentMode, .classic)
    }

    func testManualResultClosesBothReminderPanels() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.settings.restOverlayContentMode = .classic
        fixture.store.settings.restOverlayFadeAnimation = false
        fixture.store.settings.allowSkip = true
        var results: [RestEvent] = []
        fixture.scheduler.onResult = { results.append($0) }
        fixture.scheduler.startRestNow()
        XCTAssertEqual(fixture.controller.windows.count, 2)
        let panel = try XCTUnwrap(fixture.controller.windows[1])
        let view = try XCTUnwrap(panel.contentView)
        if ProcessInfo.processInfo.environment["BREATHER_HISTORY_EVIDENCE"] != nil {
            panel.orderFront(nil)
            try await Task.sleep(for: .milliseconds(400))
            try captureHistoryWindow(view, named: "fullscreen")
        }
        let id = try XCTUnwrap(fixture.scheduler.restSessionID)
        fixture.scheduler.confirmRecentRest(id)
        fixture.scheduler.confirmRecentRest(id)
        XCTAssertEqual(results.map(\.source), [.manual])
        XCTAssertTrue(fixture.controller.windows.isEmpty)
    }

    func testEscapeRespectsLivePermissionsAndPreviewAlwaysCloses() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.store.settings.strictMode = true
        fixture.store.settings.allowSkip = false
        fixture.store.settings.allowEscToSkip = false
        fixture.controller.preview()
        let preview = try XCTUnwrap(fixture.controller.session)
        XCTAssertFalse(fixture.controller.handleEscape(id: UUID()))
        XCTAssertTrue(fixture.controller.handleEscape(id: preview.id))
        XCTAssertNil(fixture.controller.session)

        fixture.scheduler.startRestNow()
        let rest = try XCTUnwrap(fixture.controller.session)
        XCTAssertFalse(fixture.controller.handleEscape(id: rest.id))
        fixture.store.settings.strictMode = false
        fixture.store.settings.allowSkip = true
        XCTAssertFalse(fixture.controller.handleEscape(id: rest.id))
        fixture.store.settings.allowEscToSkip = true
        XCTAssertTrue(fixture.controller.handleEscape(id: rest.id))
        XCTAssertNil(fixture.controller.session)
        XCTAssertEqual(fixture.scheduler.state, .working)
        XCTAssertFalse(fixture.controller.handleEscape(id: rest.id))
    }

    func testCancelledPreviewReleasesSessionAndWindowContent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        weak var releasedSession: RestOverlaySession?
        fixture.controller.preview()
        releasedSession = fixture.controller.session
        let panels = Array(fixture.controller.windows.values)
        fixture.controller.shutdown()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(releasedSession)
        XCTAssertTrue(panels.allSatisfy { $0.contentView == nil })
        XCTAssertTrue(fixture.controller.windows.isEmpty)
    }

    func testShellRendersLightDarkCompactWideAndClassicBackgrounds() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BreatherRestVisualAudit")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, width, height) in [("desktop", 1440.0, 900.0), ("compact", 800, 600), ("wide", 2560, 1080)] {
            for dark in [false, true] {
                var settings = AppSettings()
                settings.restOverlayContentMode = .dinosaur
                settings.restOverlaySubtitle = .leaveScreen
                let session = RestOverlaySession(kind: .rest, settings: settings, totalSeconds: 60, remainingSeconds: 24)
                session.setAnimationPaused(true)
                let view = RestOverlayShell(session: session,
                                            actions: .rest(snoozeDuration: 180, canSnooze: true, canSkip: true, onSnooze: {}, onSkip: {}, onRecent: {}))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .frame(width: width, height: height)
                try render(view, to: directory.appendingPathComponent("dinosaur-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        for background in RestOverlayBackground.allCases {
            var settings = AppSettings()
            settings.restOverlayBackground = background
            settings.restOverlaySubtitle = .leaveScreen
            let session = RestOverlaySession(kind: .preview, settings: settings, totalSeconds: 60)
            try render(RestOverlayPreviewView(session: session, onClose: {})
                .frame(width: 1440, height: 900), to: directory.appendingPathComponent("classic-\(background.rawValue).png"))
        }
        for palette in CurtainPalette.allCases {
            for dark in [false, true] {
                var settings = AppSettings()
                settings.restOverlayContentMode = .curtain
                settings.curtainPalette = palette
                settings.restOverlayFadeAnimation = false
                settings.restOverlaySubtitle = .leaveScreen
                let session = RestOverlaySession(
                    kind: .preview,
                    settings: settings,
                    totalSeconds: 60,
                    remainingSeconds: 24
                )
                try render(
                    RestOverlayPreviewView(session: session, onClose: {})
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .frame(width: 1440, height: 900),
                    to: directory.appendingPathComponent("curtain-\(palette.rawValue)-\(dark ? "dark" : "light").png")
                )
            }
        }
        for mode in [RestOverlayContentMode.moonlight, .windowLeaves, .sunny, .rainy, .snowy] {
            for dark in [false, true] {
                var settings = AppSettings()
                settings.restOverlayContentMode = mode
                settings.restOverlayFadeAnimation = false
                settings.restOverlaySubtitle = .leaveScreen
                let session = RestOverlaySession(
                    kind: .preview,
                    settings: settings,
                    totalSeconds: 60,
                    remainingSeconds: 24
                )
                try render(
                    RestOverlayPreviewView(session: session, onClose: {})
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .frame(width: 1440, height: 900),
                    to: directory.appendingPathComponent("\(mode.rawValue)-\(dark ? "dark" : "light").png")
                )
            }
        }
    }

    func testLocalizedCompactRestOverlayRenders() throws {
        let previousLanguage = UserDefaults.standard.string(forKey: AppLanguage.preferenceKey)
        defer {
            if let previousLanguage {
                UserDefaults.standard.set(previousLanguage, forKey: AppLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey)
            }
            LocalizationRefresh.shared.refresh()
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BreatherRestVisualAudit")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var settings = AppSettings()
        settings.restOverlayContentMode = .classic
        settings.restOverlayPrompt = .lookFar
        settings.restOverlaySubtitle = .leaveScreen
        let session = RestOverlaySession(kind: .rest, settings: settings, totalSeconds: 60, remainingSeconds: 24)

        for language in [AppLanguage.simplifiedChinese, .traditionalChinese, .english] {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            LocalizationRefresh.shared.refresh()
            let view = RestOverlayShell(session: session, actions: .rest(
                snoozeDuration: 180, canSnooze: true, canSkip: true,
                onSnooze: {}, onSkip: {}, onRecent: {}
            ))
            .frame(width: 800, height: 600)
            try render(view, to: directory.appendingPathComponent("localized-\(language.rawValue).png"))
        }
    }

    func testSettingsThemePickerAtOneAndTwoTimesScale() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BreatherRestVisualAudit")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scale in [1.0, 2.0] {
            for dark in [false, true] {
                var settings = AppSettings()
                settings.restOverlayContentMode = .dinosaur
                try render(RestThemePicker(settings: .constant(settings), duration: 60, isResting: false)
                    .padding(20)
                    .background(dark ? Color(white: 0.12) : .white)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.displayScale, scale)
                    .frame(width: 740, height: 610),
                           to: directory.appendingPathComponent("settings-\(dark ? "dark" : "light")-\(Int(scale))x.png"), scale: scale)
            }
        }
    }

    func testThemeThumbnailUsesSavedBackgroundAndDurationWithoutChangingSettings() throws {
        var settings = AppSettings()
        settings.restOverlayBackground = .moon
        settings.restOverlayTranslucentBackground = true
        let original = settings
        let classic = RestThemeThumbnailConfiguration(mode: .classic, settings: settings, duration: 600)
        XCTAssertEqual(classic.background, .moon)
        XCTAssertTrue(classic.translucent)
        XCTAssertEqual(classic.formattedTime, "10:00")
        XCTAssertEqual(classic, RestThemeThumbnailConfiguration(mode: .classic, settings: settings, duration: 600))
        let dinosaur = RestThemeThumbnailConfiguration(mode: .dinosaur, settings: settings, duration: 10)
        XCTAssertEqual(dinosaur.background, .solid)
        XCTAssertFalse(dinosaur.translucent)
        XCTAssertEqual(dinosaur.formattedTime, "00:10")
        XCTAssertEqual(settings, original)
        // Rename only display copy, never the persisted identities.
        XCTAssertEqual(RestOverlayContentMode.classic.rawValue, "classic")
        XCTAssertEqual(RestOverlayContentMode.dinosaur.rawValue, "dinosaur")
        XCTAssertEqual(RestOverlayContentMode.curtain.rawValue, "curtain")
        XCTAssertEqual(RestOverlayContentMode.moonlight.rawValue, "moonlight")
        XCTAssertEqual(RestOverlayContentMode.windowLeaves.rawValue, "windowLeaves")
        XCTAssertEqual(RestOverlayContentMode.sunny.rawValue, "sunny")
        XCTAssertEqual(RestOverlayContentMode.rainy.rawValue, "rainy")
        XCTAssertEqual(RestOverlayContentMode.snowy.rawValue, "snowy")
        XCTAssertEqual(RestOverlayContentMode.cloudTrain.rawValue, "cloudTrain")
        XCTAssertEqual(RestOverlayContentMode.classic.title, "此刻留白")
        XCTAssertEqual(RestOverlayContentMode.dinosaur.title, "像素漫游")
        XCTAssertEqual(RestOverlayContentMode.curtain.title, "幕间休息")
        XCTAssertEqual(RestOverlayContentMode.moonlight.title, "月夜静栖")
        XCTAssertEqual(RestOverlayContentMode.windowLeaves.title, "窗边叶影")
        XCTAssertEqual(RestOverlayContentMode.sunny.title, "晴日叶舞")
        XCTAssertEqual(RestOverlayContentMode.rainy.title, "窗前听雨")
        XCTAssertEqual(RestOverlayContentMode.snowy.title, "雪落无声")
        XCTAssertEqual(RestOverlayContentMode.cloudTrain.title, "云海列车")
        XCTAssertEqual(
            RestThemePicker.displayModes,
            [.classic, .moonlight, .dinosaur, .curtain, .windowLeaves, .sunny, .rainy, .snowy, .cloudTrain]
        )
        XCTAssertEqual(CurtainPalette.allCases.count, 4)
    }

    func testThemePickerRendersNarrowAndWideWithSavedBackgrounds() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BreatherRestVisualAudit")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for background in RestOverlayBackgroundSetting.allCases {
            for dark in [false, true] {
                var settings = AppSettings()
                background.apply(to: &settings)
                settings.restOverlayContentMode = .classic
                for width in [320.0, 520.0, 740.0] {
                    try render(RestThemePicker(settings: .constant(settings), duration: 30, isResting: false)
                        .padding(20)
                        .background(dark ? Color(white: 0.12) : .white)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .frame(width: width, height: width < 400 ? 1500 : width < 700 ? 820 : 610),
                               to: directory.appendingPathComponent("themes-\(background.rawValue)-\(dark ? "dark" : "light")-\(Int(width)).png"))
                }
            }
        }
    }

    func testPreviewBadgesFollowBackgroundAndPreserveExistingThemeBadges() {
        var settings = AppSettings()
        for setting in RestOverlayBackgroundSetting.allCases {
            setting.apply(to: &settings)
            let configuration = RestThemeThumbnailConfiguration(mode: .classic, settings: settings, duration: 30)
            XCTAssertEqual(configuration.badgeTitle, setting == .translucentSolid ? L.tr("半透明") : nil)
        }
        settings.restOverlayTranslucentBackground = true
        for mode in RestThemePicker.displayModes where mode != .classic {
            let configuration = RestThemeThumbnailConfiguration(mode: mode, settings: settings, duration: 30)
            XCTAssertEqual(configuration.badgeTitle,
                           mode == .moonlight ? nil : L.tr(mode == .curtain ? "转场" : "动态"))
        }
        XCTAssertEqual(L.tr("半透明", language: .simplifiedChinese), "半透明")
        XCTAssertEqual(L.tr("半透明", language: .traditionalChinese), "半透明")
        XCTAssertEqual(L.tr("半透明", language: .english), "Translucent")
    }

    func testTranslucentPreviewIndicatorsKeepBackgroundsPlainAndOpacityUnchanged() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BREATHER_WINDOW_TEST"] == "1",
                          "Native glass badges need a window-backed snapshot.")
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/review/rest-background-preview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let style = RestOverlayStyle(background: .solid, colorScheme: scheme)
            XCTAssertEqual(NSColor(style.solidBackground(translucent: true)).alphaComponent,
                           scheme == .dark ? 0.88 : 0.90, accuracy: 0.001,
                           "Preview improvements must not change the real overlay opacity")
            for scale in [1.0, 2.0] {
                for large in [false, true] {
                    for translucent in [false, true] {
                        var settings = AppSettings()
                        settings.restOverlayBackground = .solid
                        settings.restOverlayTranslucentBackground = translucent
                        let view: AnyView
                        if large {
                            view = AnyView(RestThemeThumbnail(configuration:
                                RestThemeThumbnailConfiguration(mode: .classic, settings: settings, duration: 30))
                                .frame(width: 230))
                        } else {
                            view = AnyView(RestBackgroundStyleSwatch(setting: translucent ? .translucentSolid : .solid)
                                .frame(width: 62, height: 34))
                        }
                        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
                        renderer.scale = scale
                        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                        // The old window illustration must be absent, including behind the countdown.
                        func sample(_ x: Double, _ y: Double) throws -> NSColor {
                            try XCTUnwrap(bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * x),
                                                        y: Int(Double(bitmap.pixelsHigh) * y))?.usingColorSpace(.deviceRGB))
                        }
                        let bright = try sample(0.16, 0.50)
                        let dark = try sample(0.80, 0.70)
                        let difference = abs(bright.redComponent - dark.redComponent)
                        XCTAssertLessThan(difference, 0.01, "Both preview backgrounds must stay plain")
                        if translucent && !large {
                            let symbol = try sample(0.50, 0.50)
                            XCTAssertGreaterThan(abs(symbol.redComponent - bright.redComponent), 0.025,
                                                 "The overlapping panes must be visible in \(scheme) at \(scale)x")
                        }
                        let configuration = RestThemeThumbnailConfiguration(mode: .classic, settings: settings, duration: 30)
                        XCTAssertEqual(configuration.badgeTitle, translucent ? L.tr("半透明") : nil)
                    }
                }
            }

            try render(
                RestBackgroundStylePicker(selection: .constant(.translucentSolid))
                    .padding(20)
                    .background(scheme == .dark ? Color(white: 0.14) : Color(white: 0.97))
                    .environment(\.colorScheme, scheme),
                to: directory.appendingPathComponent("panes-\(scheme == .dark ? "dark" : "light").png"),
                scale: 2
            )

            let comparison = VStack(alignment: .leading, spacing: 20) {
                Text(scheme == .dark ? "深色模式" : "浅色模式").font(.headline)
                HStack(alignment: .top, spacing: 24) {
                    ForEach([RestOverlayBackgroundSetting.solid, .translucentSolid]) { setting in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(setting.title).font(.body)
                            RestBackgroundStyleSwatch(setting: setting)
                                .frame(width: 62, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(setting == .translucentSolid ? Color.accentColor : Color.secondary.opacity(0.28),
                                                  lineWidth: setting == .translucentSolid ? 2 : 1))
                                .overlay(alignment: .topTrailing) {
                                    if setting == .translucentSolid {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.accentColor)
                                            .padding(3)
                                    }
                                }
                            RestContentOption(mode: .classic, isSelected: setting == .translucentSolid, thumbnail: {
                                var settings = AppSettings()
                                setting.apply(to: &settings)
                                return RestThemeThumbnailConfiguration(mode: .classic, settings: settings, duration: 30)
                            }(), onSelect: {})
                            .frame(width: 230)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(24)
            .foregroundStyle(.primary)
            .background(scheme == .dark ? Color(white: 0.12) : Color.white)
            .environment(\.colorScheme, scheme)
            // Window-backed snapshots preserve badge glyphs and layout. AppKit's bitmap
            // cache still omits compositor glass, so these images are layout diagnostics.
            let host = NSHostingView(rootView: comparison)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil); window.contentView = nil; window.close() }
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = ["zh-Hans", "en-US"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), options: [:]).perform([recognition])
            let labels = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            XCTAssertTrue(labels.contains(L.tr("半透明")), "The badge text must be present in the layout: \(labels)")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("comparison-\(scheme == .dark ? "dark" : "light").png"))
        }
    }

    private func render<V: View>(_ view: V, to url: URL, scale: Double = 1) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertGreaterThan(image.width, 0)
        let bitmap = NSBitmapImageRep(cgImage: image)
        var colors = Set<UInt32>()
        for y in Swift.stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 100)) {
            for x in Swift.stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 100)) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    colors.insert(UInt32(color.redComponent * 255) << 16
                                  | UInt32(color.greenComponent * 255) << 8
                                  | UInt32(color.blueComponent * 255))
                }
            }
        }
        XCTAssertGreaterThan(colors.count, 3, "The render must contain content, not only an empty background: \(url.lastPathComponent)")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private func findCurtainPlayer(in view: NSView) -> NSView? {
        if String(describing: type(of: view)).contains("CurtainPlayerView") {
            return view
        }
        return view.subviews.lazy.compactMap(findCurtainPlayer).first
    }

    private func findAVPlayerSurface(in view: NSView) -> NSView? {
        if view.layer is AVPlayerLayer {
            return view
        }
        return view.subviews.lazy.compactMap(findAVPlayerSurface).first
    }

    private func findMetalSurface(in view: NSView) -> RainGlassMetalView? {
        if let metalView = view as? RainGlassMetalView {
            return metalView
        }
        return view.subviews.lazy.compactMap(findMetalSurface).first
    }

    private func findAtmosphereMetalSurface(in view: NSView) -> MTKView? {
        if let metalView = view as? MTKView { return metalView }
        return view.subviews.lazy.compactMap(findAtmosphereMetalSurface).first
    }

    private func findCloudTrainSurface(in view: NSView) -> CloudTrainMetalView? {
        if let metalView = view as? CloudTrainMetalView { return metalView }
        return view.subviews.lazy.compactMap(findCloudTrainSurface).first
    }

    private func findSnowfallSurface(in view: NSView) -> SnowfallMetalView? {
        if let metalView = view as? SnowfallMetalView { return metalView }
        return view.subviews.lazy.compactMap(findSnowfallSurface).first
    }

    private func writePreview(pixels: [UInt8], width: Int, height: Int, to output: String) throws {
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        ))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(
            using: .png, properties: [:]
        ))
        try png.write(to: URL(fileURLWithPath: output), options: .atomic)
    }

}

@MainActor
private final class CurtainPhaseTestModel: ObservableObject {
    @Published var phase: CurtainPhase = .closing
}

private struct CurtainPhaseTestView: View {
    @ObservedObject var model: CurtainPhaseTestModel

    var body: some View {
        CurtainBackdrop(palette: .smokedJade, phase: model.phase, animated: true)
            .frame(width: 640, height: 360)
    }
}

@MainActor
private final class Fixture {
    let suite = "RestOverlayTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let store: SettingsStore
    let scheduler: BreakScheduler
    let clock = RestOverlayTestClock(now: Date(timeIntervalSince1970: 1_800_000_000))
    let ambientSound = RestAmbientSoundSpy()
    var controller: RestOverlayWindowController!
    var screens = [RestOverlayScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
                   RestOverlayScreen(id: 2, frame: CGRect(x: 1440, y: 0, width: 800, height: 600))]

    init(reduceMotion: Bool = false, presentsWindows: Bool = false) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        store = SettingsStore(userDefaults: defaults)
        scheduler = BreakScheduler(settingsStore: store, notificationService: RestTestNotification(), idleMonitor: RestTestIdle(),
                                   pauseResumeSessionStore: PauseResumeSessionStore(userDefaults: defaults),
                                   now: { [clock] in clock.now })
        controller = RestOverlayWindowController(scheduler: scheduler,
                                                onSnooze: { [weak scheduler] in scheduler?.snoozeBreak() },
                                                onSkip: { [weak scheduler] in scheduler?.skipBreak() },
                                                screens: { [weak self] in self?.screens ?? [] },
                                                mouseLocation: { CGPoint(x: 1500, y: 300) },
                                                reduceMotion: { reduceMotion },
                                                presentsWindows: presentsWindows,
                                                ambientSoundService: ambientSound)
        scheduler.onRestStarted = { [weak controller] in controller?.show() }
        scheduler.onRestEnded = { [weak controller] in controller?.hideRest() }
    }

    func cleanUp() {
        controller.shutdown()
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class RestAmbientSoundSpy: RestAmbientSoundPlaying {
    private(set) var playRainCount = 0
    private(set) var stopCount = 0

    func playRain() { playRainCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor private final class RestTestNotification: BreakNotificationSending {
    func sendPreBreakNotification(playSound: Bool, soundEffect: RestSoundEffect) {}
}
private final class RestTestIdle: IdleTimeProviding { var idleSeconds: TimeInterval = 0 }
private final class RestOverlayTestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
