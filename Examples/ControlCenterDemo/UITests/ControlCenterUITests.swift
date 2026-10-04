import XCTest

final class ControlCenterUITests: XCTestCase {
    @MainActor func testPresentToggleExpandCollapseDismissAndReopen() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["demo.open"].tap()
        let close = app.buttons["control-center.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Control Center"
        shot.lifetime = .keepAlways
        add(shot)
        let wifi = app.buttons["Wi-Fi"]
        XCTAssertTrue(wifi.exists)
        wifi.tap()
        XCTAssertEqual(wifi.value as? String, "Off")
        app.buttons["Expand Now Playing"].tap()
        let collapse = app.buttons["Collapse Now Playing"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        let expandedShot = XCTAttachment(screenshot: app.screenshot())
        expandedShot.name = "Expanded control"
        expandedShot.lifetime = .keepAlways
        add(expandedShot)
        collapse.tap()
        close.tap()
        XCTAssertTrue(app.buttons["demo.open"].waitForExistence(timeout: 3))
        app.buttons["demo.open"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["Wi-Fi"].value as? String, "Off")
        close.tap()
    }

    @MainActor func testFallbackAndReducedMotion() {
        let app = XCUIApplication()
        app.launchArguments = ["--fallback", "--reduce-motion", "--reduce-transparency"]
        app.launch()
        app.buttons["demo.open"].tap()
        let close = app.buttons["control-center.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Control Center"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Expand Now Playing"].tap()
        let collapse = app.buttons["Collapse Now Playing"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        let expandedShot = XCTAttachment(screenshot: app.screenshot())
        expandedShot.name = "Expanded control"
        expandedShot.lifetime = .keepAlways
        add(expandedShot)
        collapse.tap()
        close.tap()
    }
}

extension ControlCenterUITests {
    @MainActor func testLongPressSliderAndPageNavigation() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["demo.open"].tap()
        XCTAssertTrue(app.buttons["control-center.close"].waitForExistence(timeout: 5))
        let focus = app.buttons["control-tile.focus"]
        let originalValue = focus.value as? String
        focus.press(forDuration: 0.5)
        let collapse = app.buttons["Collapse Focus"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        collapse.tap()
        XCTAssertEqual(focus.value as? String, originalValue, "Holding a tile must not trigger its tap action")
        app.buttons["Your Space"].tap()
        XCTAssertTrue(app.buttons["control-tile.lights"].waitForExistence(timeout: 3))
        app.buttons["Favorites"].tap()
        XCTAssertTrue(app.buttons["control-tile.focus"].waitForExistence(timeout: 3))
        app.buttons["control-center.close"].tap()
    }
}

extension ControlCenterUITests {
    @MainActor func testDynamicRemovalAndInterruptedDismissalFromSmallAnchor() {
        let app = XCUIApplication()
        app.launchArguments = ["--integration-harness"]
        app.launch()
        app.buttons["Open harness"].tap()
        let close = app.buttons["control-center.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Disabled action"].isEnabled)
        app.buttons["Expand removable"].tap()
        app.buttons["Remove this tile"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Collapse Removable"].exists)
        app.buttons["Interrupt dismissal"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        // The delayed completion of the original dismissal must not close the reopened center.
        let remainsOpen = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in close.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [remainsOpen], timeout: 3), .completed)
        close.tap()
        XCTAssertTrue(app.staticTexts["Cycle finished"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Dismissals: 1"].waitForExistence(timeout: 3))
    }

    @MainActor func testPresentationOverSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["--integration-harness"]
        app.launch()
        app.buttons["Open sheet"].tap()
        app.buttons["Open center over sheet"].tap()
        let close = app.buttons["control-center.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Above the sheet"].exists)
        close.tap()
        XCTAssertTrue(app.buttons["Open center over sheet"].waitForExistence(timeout: 3))
    }

    @MainActor func testLandscapeWithLargeType() {
        let app = XCUIApplication()
        app.launchArguments = ["--large-type"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["demo.open"].tap()
        let close = app.buttons["control-center.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable)
        app.buttons["Expand Now Playing"].tap()
        let collapse = app.buttons["Collapse Now Playing"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        XCTAssertTrue(collapse.isHittable)
        collapse.tap()
        close.tap()
    }

    @MainActor func testUIKitHostWithoutSwiftUIModifier() {
        let app = XCUIApplication()
        app.launchArguments = ["--uikit-host"]
        app.launch()
        app.buttons["uikit.open"].tap()
        let close = app.buttons["control-center.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let flashlight = app.buttons["control-tile.uikit-flashlight"]
        XCTAssertEqual(flashlight.value as? String, "Off")
        flashlight.tap()
        XCTAssertEqual(flashlight.value as? String, "On", "Rebuilding pages must refresh the presented tiles")
        close.tap()
        XCTAssertTrue(app.staticTexts["Flashlight on · Dismissals: 1"].waitForExistence(timeout: 3))
        // Interactive presentation: pull the UIKit view down.
        let pull = app.staticTexts["uikit.pull"]
        pull.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertTrue(app.staticTexts["Flashlight on · Dismissals: 2"].waitForExistence(timeout: 3))
    }

    @MainActor func testSwipeUpDismisses() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["demo.open"].tap()
        let close = app.buttons["control-center.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        XCTAssertTrue(app.buttons["demo.open"].waitForExistence(timeout: 3))
        XCTAssertFalse(close.exists)
    }
}
