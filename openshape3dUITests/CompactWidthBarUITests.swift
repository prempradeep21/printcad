//
//  CompactWidthBarUITests.swift
//  openshape3dUITests
//
//  iPhone-width regression guard for the bottom contextual bars.
//
//  The bars used to lay out as a single fixed HStack sized for iPad. At iPhone
//  width SwiftUI compressed each label to its minimum and wrapped it one
//  character per line: "Extrude", "Offset Plane" and "Cancel" each became a
//  vertical stack of letters, the Extrude button rendered as an unlabelled blue
//  pill, and the bar ate ~40% of the screen — pushing the tool palette's last
//  entries off. See marketing/bugs/iphone-extrude-bar-broken.png.
//
//  The assertions here are geometric on purpose. A per-character-wrapped button
//  still reports the full `label` string to XCUITest, so comparing labels alone
//  cannot catch the bug; what actually distinguishes a healthy text button is
//  that it is wider than it is tall.
//
//  These tests are meaningful only where the horizontal size class is compact,
//  so they skip themselves on iPad rather than failing there.
//

import XCTest

final class CompactWidthBarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// Launches straight into the seeded document, matching the bug repro.
    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OS3D_FRESH"] = "1"
        app.launchEnvironment["OS3D_RESET_STORE"] = "1"
        app.launchEnvironment["OS3D_DEBUG_SEED"] = "1"
        app.launchEnvironment["OS3D_AUTO_OPEN"] = "1"
        app.launch()
        return app
    }

    /// iPad lays these bars out as one row by design; only compact width is
    /// under test. 500pt is comfortably above every iPhone portrait width and
    /// below every iPad one.
    private func skipUnlessCompact(_ app: XCUIApplication) throws {
        let width = app.windows.firstMatch.frame.width
        try XCTSkipUnless(width > 0 && width < 500,
                          "Compact-width layout test; window is \(width)pt wide")
    }

    /// A healthy text control is a horizontal pill. When the label wraps one
    /// character per line it becomes narrow and very tall, which is exactly the
    /// shape this asserts against.
    private func assertReadsHorizontally(_ element: XCUIElement,
                                         minimumWidth: CGFloat,
                                         _ what: String,
                                         file: StaticString = #filePath,
                                         line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5),
                      "\(what) should exist", file: file, line: line)
        XCTAssertTrue(element.isHittable,
                      "\(what) should be hittable, not clipped or covered",
                      file: file, line: line)
        let frame = element.frame
        XCTAssertGreaterThan(frame.width, frame.height,
                             "\(what) is taller than it is wide — its label is wrapping vertically",
                             file: file, line: line)
        XCTAssertGreaterThan(frame.width, minimumWidth,
                             "\(what) is only \(frame.width)pt wide — its label is truncated",
                             file: file, line: line)
    }

    /// QA-53 at compact width: the sketch Move/Rotate and Copy pills read
    /// horizontally and the X control stays reachable. A completed line keeps
    /// its selection; turning the tool off exposes the pills.
    func testSketchTransformControlsAreUsableAtCompactWidth() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OS3D_FRESH"] = "1"
        app.launchEnvironment["OS3D_RESET_STORE"] = "1"
        app.launch()
        try skipUnlessCompact(app)
        let window = app.windows.firstMatch
        func p(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        }
        XCTAssertTrue(app.buttons["SketchGroup"].waitForExistence(timeout: 10))
        startSketchTool(app, "Line")
        XCTAssertTrue(app.staticTexts["Choose a sketch plane"].waitForExistence(timeout: 3))
        p(0.8, 0.78).tap()
        XCTAssertTrue(app.staticTexts["Sketching on ground plane"].waitForExistence(timeout: 3))
        sleep(2)
        p(0.30, 0.45).press(forDuration: 0.15, thenDragTo: p(0.70, 0.45))
        XCTAssertTrue(app.buttons["DimensionLabel"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Line"].firstMatch.tap() // tool off; the selection stays
        XCTAssertTrue(app.staticTexts["Drag to orbit — pick a tool to draw"].waitForExistence(timeout: 3))

        assertReadsHorizontally(app.buttons["SketchTransformMode"], minimumWidth: 70, "Move/Rotate pill")
        assertReadsHorizontally(app.buttons["SketchCopyBadge"], minimumWidth: 44, "Copy pill")
        app.buttons["SketchTransformMode"].tap()
        let xControl = app.descendants(matching: .any)
            .matching(identifier: "SketchTransform-x").firstMatch
        XCTAssertTrue(xControl.waitForExistence(timeout: 3))
        XCTAssertTrue(xControl.isHittable, "The X control must not be covered at compact width")
        app.buttons["SketchTransformMode"].tap()
    }

    /// QA-29 at compact width: a line against the (left) palette opens its
    /// keypad clear of the palette, on screen, with the commit key reachable.
    func testEdgeKeypadIsUsableAtCompactWidth() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OS3D_FRESH"] = "1"
        app.launchEnvironment["OS3D_RESET_STORE"] = "1"
        app.launch()
        try skipUnlessCompact(app)
        let window = app.windows.firstMatch
        func p(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        }
        XCTAssertTrue(app.buttons["SketchGroup"].waitForExistence(timeout: 10))
        startSketchTool(app, "Line")
        XCTAssertTrue(app.staticTexts["Choose a sketch plane"].waitForExistence(timeout: 3))
        p(0.8, 0.78).tap()
        XCTAssertTrue(app.staticTexts["Sketching on ground plane"].waitForExistence(timeout: 3))
        sleep(2)
        let palette = app.buttons["Line"].firstMatch
        XCTAssertTrue(palette.waitForExistence(timeout: 3))

        // A line starting just right of the palette.
        p(0.30, 0.45).press(forDuration: 0.15, thenDragTo: p(0.62, 0.45))
        // A completed line keeps its readout selected — no selection tap.
        let label = app.buttons["DimensionLabel"].firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 3), "A completed line should show its length label")
        sleep(1)
        XCTAssertGreaterThanOrEqual(label.frame.minX, palette.frame.maxX,
                                    "The length badge must not sit under the palette at compact width")
        label.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let keypad = app.otherElements["NumericKeypad"].firstMatch
        XCTAssertTrue(keypad.waitForExistence(timeout: 3), "The badge tap should open the keypad")
        XCTAssertGreaterThanOrEqual(keypad.frame.minX, palette.frame.maxX,
                                    "The keypad must stay clear of the palette at compact width")
        XCTAssertLessThanOrEqual(keypad.frame.maxX, window.frame.maxX)
        XCTAssertLessThanOrEqual(keypad.frame.maxY, window.frame.maxY)
        let commit = app.buttons["KeypadCommit"].firstMatch
        XCTAssertTrue(commit.isHittable, "The commit key must be reachable at compact width")
        commit.tap()
    }

    /// Extrude controls ride the arrow now (no bottom bar); at iPhone width
    /// they must stay on screen and reachable, keep the options menu
    /// reachable, and leave the palette and the viewport usable — the two
    /// failures the old bottom bar was reported for.
    func testExtrudeBarIsUsableAtCompactWidth() throws {
        let app = launchSeeded()
        try skipUnlessCompact(app)

        // Tap the seeded box's top face to arm extrude.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.27)).tap()
        XCTAssertTrue(app.buttons["Extrude"].waitForExistence(timeout: 5),
                      "Tapping the top face should arm the extrude controls")

        assertArrowControlsUsable(app, window: window, maxHeightFraction: 0.25)

        // The controls must leave the tool palette usable: Delete is its last
        // entry and was unreachable under the old bottom bar.
        let delete = app.buttons.containing(.staticText, identifier: "Delete").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        // Nine entries do not fit an iPhone portrait screen, so the palette
        // scrolls there (ViewThatFits); the requirement is that Delete is
        // reachable — directly or by scrolling the palette.
        if !delete.isHittable {
            let palette = app.scrollViews["ToolPalette"]
            XCTAssertTrue(palette.exists, "A palette that does not fit should scroll")
            palette.swipeUp()
        }
        XCTAssertTrue(delete.isHittable,
                      "The extrude controls are covering the tool palette's last entry")

        // The widest option, once in the bar, is still one tap away.
        tapExtrudeOption(app, "Offset Plane")
        XCTAssertTrue(app.buttons["Add Plane"].waitForExistence(timeout: 3),
                      "Offset Plane should be reachable from the arrow's options menu")
    }

    /// Landscape is the tightest case: on every iPhone but the Max/Plus the
    /// width stays compact while the height drops to ~390pt.
    ///
    /// Unlike the tests above this one runs everywhere — staying on screen and
    /// reachable are requirements in both size classes, so there is nothing to
    /// skip.
    func testExtrudeBarIsUsableInLandscape() throws {
        let app = launchSeeded()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.30)).tap()
        XCTAssertTrue(app.buttons["Extrude"].waitForExistence(timeout: 5),
                      "Tapping the top face should arm the extrude controls in landscape")

        assertArrowControlsUsable(app, window: window, maxHeightFraction: 0.35)

        // The palette cannot show all eight tools in ~390pt on any layout, so
        // the requirement here is that Delete is *reachable* by scrolling.
        let delete = app.buttons.containing(.staticText, identifier: "Delete").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        if !delete.isHittable {
            let palette = app.scrollViews.containing(.staticText, identifier: "Sketch").firstMatch
            XCTAssertTrue(palette.exists, "Tool palette should be a scrollable column")
            palette.swipeUp()
        }
        XCTAssertTrue(delete.isHittable,
                      "The tool palette's last entry is unreachable even after scrolling")
    }

    /// The on-arrow options chip, value, cancel and commit: each on screen and
    /// hittable, and together a small cluster rather than a bar that
    /// swallows the viewport.
    private func assertArrowControlsUsable(_ app: XCUIApplication, window: XCUIElement,
                                           maxHeightFraction: CGFloat,
                                           file: StaticString = #filePath, line: UInt = #line) {
        assertReadsHorizontally(app.buttons["ExtrudeOptionsMenu"], minimumWidth: 40,
                                "Extrude options chip", file: file, line: line)
        let controls = [app.buttons["ExtrudeOptionsMenu"], app.textFields["Distance"].firstMatch,
                        app.buttons["Cancel"], app.buttons["Extrude"]]
        var union = CGRect.null
        for control in controls {
            XCTAssertTrue(control.waitForExistence(timeout: 3),
                          "\(control) should exist", file: file, line: line)
            XCTAssertTrue(control.isHittable,
                          "\(control) should be hittable, not clipped or covered", file: file, line: line)
            XCTAssertTrue(window.frame.contains(control.frame),
                          "\(control) runs off screen: \(control.frame)", file: file, line: line)
            union = union.union(control.frame)
        }
        XCTAssertLessThan(union.height, window.frame.height * maxHeightFraction,
                          "The arrow's controls span \(union.height)pt of a \(window.frame.height)pt screen",
                          file: file, line: line)
    }

    /// The primitive dimension bar, which showed "B/o/x" stacked vertically.
    func testPrimitiveDimensionBarIsUsableAtCompactWidth() throws {
        let app = launchSeeded()
        try skipUnlessCompact(app)

        let title = app.staticTexts["Box"]
        XCTAssertTrue(title.waitForExistence(timeout: 10),
                      "The seeded box should open with its dimension bar showing")
        XCTAssertGreaterThan(title.frame.width, title.frame.height,
                             "The 'Box' title is wrapping one character per line")

        assertReadsHorizontally(app.buttons["Done"], minimumWidth: 44, "Done button")

        // Every dimension field must be reachable, not squeezed off the bar.
        let fields = app.textFields
        XCTAssertEqual(fields.count, 3, "A box should offer width/depth/height fields")
        for index in 0..<3 {
            XCTAssertTrue(fields.element(boundBy: index).isHittable,
                          "Dimension field \(index) is not hittable")
        }
    }
}
