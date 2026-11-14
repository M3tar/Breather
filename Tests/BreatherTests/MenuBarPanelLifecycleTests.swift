import AppKit
import SwiftUI
import XCTest
@testable import Breather

@MainActor
final class MenuBarPanelLifecycleTests: XCTestCase {
    func testClosingReleasesHostingGraphAndPanelCanBeReused() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 430),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        weak var oldController: NSViewController?
        weak var oldView: NSView?
        autoreleasepool {
            let controller = NSHostingController(rootView: Text("Menu"))
            oldController = controller
            oldView = controller.view
            panel.contentViewController = controller
            MenuBarController.hideAndReleaseContent(in: panel)
            XCTAssertNil(panel.contentViewController)
            XCTAssertNil(panel.contentView)
            XCTAssertFalse(panel.isVisible)
        }
        XCTAssertNil(oldController)
        XCTAssertNil(oldView)
        autoreleasepool {
            panel.contentViewController = NSHostingController(rootView: Text("Reopened menu"))
            XCTAssertNotNil(panel.contentView)
            MenuBarController.hideAndReleaseContent(in: panel)
        }
        XCTAssertNil(panel.contentView)
    }
}
