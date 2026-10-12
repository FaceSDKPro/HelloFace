import XCTest

/// 必须在真机执行：通过原始采集帧时间戳验证恢复，不能以 isRunning 或页面存在代替出帧。
final class CameraLifecycleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Camera lifecycle tests require a physical iPhone camera")
        #endif
    }

    @MainActor
    func testDetectionResumes() { checkBackgroundResume(page: "实时人脸检测") }

    @MainActor
    func testSearchResumes() { checkBackgroundResume(page: "人脸搜索识别") }

    @MainActor
    private func checkBackgroundResume(page: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--camera-lifecycle-test"]
        app.launch()
        let entry = app.staticTexts[page].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            let allow = springboard.alerts.buttons.matching(
                NSPredicate(format: "label IN %@", ["Allow", "OK", "允许", "好"])
            ).firstMatch
            if allow.exists { allow.tap() }
        }

        let frame = app.staticTexts["camera.liveFrame"].firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 10))
        waitForFrames(frame, after: 0)
        // 多轮切换覆盖 active → inactive → background → inactive → active。
        for _ in 0..<3 {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
            app.activate()
            XCTAssertTrue(frame.waitForExistence(timeout: 10))
            let restoredTimestamp = timestamp(frame)
            waitForFrames(frame, after: restoredTimestamp)
        }
        app.terminate()
    }

    @MainActor
    private func timestamp(_ frame: XCUIElement) -> Double {
        Double(frame.value as? String ?? "") ?? 0
    }

    @MainActor
    private func waitForFrames(_ frame: XCUIElement, after previous: Double) {
        let advancing = NSPredicate { [self] _, _ in timestamp(frame) > previous + 0.5 }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advancing, object: nil)], timeout: 12)
        XCTAssertEqual(result, .completed, "恢复后必须持续输出新帧，不能停在最后一帧")
    }
}
