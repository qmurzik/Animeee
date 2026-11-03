import XCTest

final class PlaybackUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 30), "Missing control: \(element)", file: file, line: line)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.isHittable }, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 10), .completed, "Control is not hittable: \(element)", file: file, line: line)
        // Dispatch an actual coordinate tap through the system hit-testing path.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testFullscreenQualityVoicesEpisodesAndPortraitControls() {
        let app = XCUIApplication()
        app.launchEnvironment = ["ANIMEAPP_PROBE": "cvh", "ANIMEAPP_LANDSCAPE": "0", "ANIMEAPP_UI_TEST": "1"]
        app.launch()
        tap(app.buttons["player.icon.arrow.up.left.and.arrow.down.right"])
        let quality = app.buttons["player.quality"]
        XCTAssertTrue(quality.waitForExistence(timeout: 40))
        // Quality comes from a real CVH response; do not tap an unready selector.
        let ready = NSPredicate(format: "label CONTAINS %@", "720p")
        expectation(for: ready, evaluatedWith: quality)
        waitForExpectations(timeout: 40)
        tap(quality)
        XCTAssertTrue(app.navigationBars["Настройки просмотра"].waitForExistence(timeout: 10))
        snapshot("landscape-quality")
        let choice = app.buttons["quality.480p"]
        tap(choice)
        expectation(for: NSPredicate(format: "label CONTAINS %@", "480p"), evaluatedWith: quality)
        waitForExpectations(timeout: 30)
        tap(app.buttons["player.voices"])
        XCTAssertTrue(app.navigationBars["Озвучки"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["Студия или источник"].exists)
        snapshot("landscape-voices")
        tap(app.buttons["panel.close"])
        tap(app.buttons["player.episodes"])
        XCTAssertTrue(app.navigationBars["Выбрать серию"].waitForExistence(timeout: 10))
        snapshot("landscape-episodes")
        tap(app.buttons["panel.close"])
        tap(app.buttons["player.icon.ellipsis"])
        XCTAssertTrue(app.navigationBars["Настройки просмотра"].waitForExistence(timeout: 10))
        tap(app.buttons["panel.close"])
        tap(app.buttons["player.icon.arrow.down.right.and.arrow.up.left"])
        tap(app.buttons["player.settings.portrait"])
        XCTAssertTrue(app.navigationBars["Настройки просмотра"].waitForExistence(timeout: 10))
        snapshot("portrait-settings")
    }
    func testInstalledAppIconOnSpringBoard() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCUIDevice.shared.press(.home)
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<4 { if board.icons["AnimeApp"].isHittable { break }; board.swipeLeft() }
        XCTAssertTrue(board.icons["AnimeApp"].exists)
        snapshot("installed-app-icon")
    }
}

final class SourceSettingsUITests: XCTestCase {
    func testSourceNavigationAndMirrorValidation() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Настройки"].tap()
        let sources = app.buttons["Источники и зеркала"]
        XCTAssertTrue(sources.waitForExistence(timeout: 15)); sources.tap()
        let animego = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "AnimeGO")).firstMatch
        XCTAssertTrue(animego.waitForExistence(timeout: 10)); animego.tap()
        let field = app.textFields["mirror.site"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("http://invalid.example")
        if !app.buttons["mirror.save"].isHittable { app.swipeUp() }; app.buttons["mirror.save"].tap()
        XCTAssertTrue(app.staticTexts["Нужен HTTPS-домен без пути, параметров, логина и пароля."].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "source-mirror-validation"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
