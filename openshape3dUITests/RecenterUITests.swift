//
//  RecenterUITests.swift
//  openshape3dUITests
//
//  The recenter button beside the orientation cube brings the model back
//  into view from wherever the camera has wandered.
//

import XCTest

final class RecenterUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OS3D_FRESH"] = "1"
        app.launchEnvironment["OS3D_RESET_STORE"] = "1"
        app.launchEnvironment["OS3D_DEBUG_SEED"] = "1"
        app.launchEnvironment["OS3D_AUTO_OPEN"] = "1"
        app.launch()
        return app
    }

    /// Sits just left of the cube, level with it, and is tappable.
    func testRecenterButtonSitsBesideTheCube() throws {
        let app = launchSeeded()
        let window = app.windows.firstMatch
        let recenter = app.buttons["RecenterButton"]
        XCTAssertTrue(recenter.waitForExistence(timeout: 10))
        XCTAssertTrue(recenter.isHittable)

        // OrientationCube: 92pt square, 14pt from the right edge, 96pt down.
        let cube = CGRect(x: window.frame.maxX - 14 - 92, y: window.frame.minY + 96,
                          width: 92, height: 92)
        let frame = recenter.frame
        XCTAssertLessThanOrEqual(frame.maxX, cube.minX, "Recenter should sit left of the cube")
        XCTAssertGreaterThan(frame.minX, cube.minX - 80, "Recenter should sit right beside the cube")
        XCTAssertEqual(frame.midY, cube.midY, accuracy: 4, "Recenter should be level with the cube")
    }

    /// Disturb the camera (a pinch — XCUITest has no two-finger pan), then
    /// Recenter: the fit centres the model whatever the view direction, so a
    /// tap at the screen centre must land on the box and select it.
    func testRecenterPutsTheModelUnderTheScreenCentre() throws {
        let app = launchSeeded()
        let window = app.windows.firstMatch
        let recenter = app.buttons["RecenterButton"]
        XCTAssertTrue(recenter.waitForExistence(timeout: 10))
        // Let the opening fit settle, then clear the seeded selection.
        sleep(2)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85)).tap()
        sleep(1)
        let delete = app.buttons.containing(.staticText, identifier: "Delete").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        XCTAssertFalse(delete.isEnabled, "Nothing should be selected to start")

        window.pinch(withScale: 0.1, velocity: -5)
        sleep(1)

        recenter.tap()
        sleep(2) // camera flight settles
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let selected = NSPredicate(format: "isEnabled == true")
        expectation(for: selected, evaluatedWith: delete)
        waitForExpectations(timeout: 5)
    }
}
