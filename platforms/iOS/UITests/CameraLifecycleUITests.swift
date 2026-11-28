import XCTest

/// Run on a real device: verify recovery from raw capture timestamps, not isRunning or screen presence.
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
        app.launchArguments = ["--camera-lifecycle-test", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let entry = app.descendants(matching: .any)["demo.feature.\(page)"].firstMatch
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
        waitForRunningFlow(app)
        let cameraSwitch = app.buttons["切换摄像头"].firstMatch
        for _ in 0..<2 {
            XCTAssertTrue(cameraSwitch.waitForExistence(timeout: 5))
            cameraSwitch.tap()
            let changedTimestamp = timestamp(frame)
            waitForFrames(frame, after: changedTimestamp)
            waitForRunningFlow(app)
        }
        // Repeated transitions cover active to inactive to background to inactive to active.
        // 多轮切换覆盖 active → inactive → background → inactive → active。
        for _ in 0..<3 {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
            app.activate()
            XCTAssertTrue(frame.waitForExistence(timeout: 10))
            let restoredTimestamp = timestamp(frame)
            waitForFrames(frame, after: restoredTimestamp)
            waitForRunningFlow(app)
        }
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = page + " after camera switches and background recovery"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
    }

    @MainActor
    private func timestamp(_ frame: XCUIElement) -> Double {
        Double(frame.value as? String ?? "") ?? 0
    }

    @MainActor
    private func waitForRunningFlow(_ app: XCUIApplication) {
        let phase = app.staticTexts["camera.phase"].firstMatch
        let running = NSPredicate(format: "value == %@", "running")
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: running, object: phase)], timeout: 12)
        XCTAssertEqual(result, .completed, "相机出帧时 SDK 也必须处于运行状态")
    }

    @MainActor
    private func waitForFrames(_ frame: XCUIElement, after previous: Double) {
        let advancing = NSPredicate { [self] _, _ in timestamp(frame) > previous + 0.5 }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: advancing, object: nil)], timeout: 12)
        XCTAssertEqual(result, .completed, "恢复后必须持续输出新帧，不能停在最后一帧")
    }
}

/// Check the ordinary search page without test-only camera diagnostics.
/// 验证普通搜索页面，不启用仅供测试的相机诊断文字。
final class SearchPresentationUITests: XCTestCase {
    @MainActor
    func testNormalSearchPresentation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let entry = app.descendants(matching: .any)["demo.feature.人脸搜索识别"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.staticTexts["1:N · 活体已开启"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Running: Search"].exists)
        XCTAssertFalse(app.staticTexts["camera.liveFrame"].exists)
        let mode = app.staticTexts["search.caption.mode"]
        let result = app.staticTexts["search.caption.result"]
        XCTAssertTrue(mode.exists && result.exists)
        let baseline = result.frame.minY
        mode.tap()
        XCTAssertTrue(app.navigationBars["人脸搜索识别"].waitForExistence(timeout: 5))
        app.navigationBars["人脸搜索识别"].buttons["返回"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.frame.minY, baseline, accuracy: 0.5)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Face search normal presentation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
    }
}

/// Keep the recognition controls compact and readable on a physical iPhone.
/// 人脸识别参数保持紧凑，并在真机白色卡片上使用清晰的文字对比度。
final class RecognitionLayoutUITests: XCTestCase {
    @MainActor
    private func openRecognition(references: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if !references.isEmpty {
            app.launchEnvironment["HIFACE_UI_TEST_REFERENCE_IDS"] = references.joined(separator: ",")
        }
        app.launch()
        let entry = app.descendants(matching: .any)["demo.feature.recognition"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.navigationBars["人脸识别"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    func testDraggingAcrossPortraitsScrollsWithoutVerifyingOrDeleting() {
        continueAfterFailure = false
        let prefix = UUID().uuidString.prefix(8)
        let ids = (1...12).map { "\(prefix)-\($0)" }
        let app = openRecognition(references: ids)
        func portrait(_ index: Int) -> XCUIElement {
            app.buttons["验证 \(ids[index])，长按删除"].firstMatch
        }
        let first = portrait(0), third = portrait(2)
        XCTAssertTrue(first.isHittable && third.isHittable)
        let hint = app.staticTexts["点击头像开始验证，长按删除（左右滑动列表）"]
        XCTAssertTrue(hint.exists)
        XCTAssertLessThanOrEqual(hint.frame.maxY, first.frame.minY)
        // Start both drags on a portrait, away from the screen-edge navigation gesture.
        let firstFrame = first.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let left = origin.withOffset(CGVector(dx: firstFrame.midX, dy: firstFrame.midY))
        let right = origin.withOffset(CGVector(dx: third.frame.midX, dy: third.frame.midY))
        right.press(forDuration: 0.05, thenDragTo: left, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(portrait(4).isHittable)
        // XCTest may report an invalid activation point for the clipped portrait.
        if first.exists { XCTAssertLessThanOrEqual(first.frame.maxX, firstFrame.minX) }
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        first.press(forDuration: 0.8)
        app.buttons["删除"].firstMatch.tap()
        let deletion = app.alerts["删除这条人脸？"]
        XCTAssertTrue(deletion.waitForExistence(timeout: 5))
        deletion.buttons["取消"].tap()
        XCTAssertTrue(first.isHittable)
        first.tap()
        // The in-memory ID has no stored feature, so verification returns an inline result.
        let result = app.otherElements["recognition.result"].staticTexts.firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.label.hasPrefix("流程执行失败") || result.label.hasPrefix("相机或帧处理失败"))
    }

    @MainActor
    func testAlbumPickerCanCancelBackToRecognition() {
        let app = openRecognition()
        let album = app.buttons["相册添加"].firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 5))
        let camera = app.buttons["相机录入"].firstMatch
        XCTAssertTrue(camera.exists)
        XCTAssertEqual(album.frame.midY, camera.frame.midY, accuracy: 1)
        XCTAssertEqual(camera.frame.minX - album.frame.maxX, 16, accuracy: 1)
        let empty = app.staticTexts["暂无已录入的人脸。"]
        let portrait = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "验证 ")).firstMatch
        let above = empty.exists ? empty : portrait
        XCTAssertTrue(above.exists)
        XCTAssertLessThanOrEqual(above.frame.maxY, album.frame.minY)
        if !album.isHittable { app.swipeUp() }
        album.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(app.navigationBars["人脸识别"].waitForExistence(timeout: 5))
        XCTAssertTrue(camera.isHittable)
        XCTAssertFalse(app.navigationBars["录入参考人脸"].exists)
    }

    @MainActor
    func testRecognitionActionsUseOneReadableRow() {
        continueAfterFailure = false
        let app = openRecognition()
        XCTAssertFalse(app.staticTexts["选择检测方式与活体参数，结果将在本页显示"].exists)
        let actionToggle = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "动作活体")).firstMatch
        XCTAssertTrue(actionToggle.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "value == %@", "1")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: actionToggle)], timeout: 5), .completed)

        let actions = ["眨眼", "张嘴", "摇头", "点头"].map { app.buttons[$0].firstMatch }
        for action in actions { XCTAssertTrue(action.waitForExistence(timeout: 5)) }
        let baseline = actions[0].frame.midY
        for action in actions.dropFirst() { XCTAssertEqual(action.frame.midY, baseline, accuracy: 1) }

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Face recognition readable action row"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let passiveDescription = app.staticTexts["始终开启，无需指定动作即可检测是否为真人。"]
        if !passiveDescription.isHittable { app.swipeUp() }
        XCTAssertTrue(passiveDescription.isHittable)
    }
}

/// Static image search works without a camera and can run on a simulator.
/// 静态图片搜索无需相机，可在模拟器运行。
final class ImageFaceSearchUITests: XCTestCase {
    @MainActor
    func testAlbumCancelPreservesEmptyState() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let entry = app.staticTexts["图片人脸搜索识别"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        let status = app.staticTexts["imageSearch.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let library = app.descendants(matching: .any)["imageSearch.library"].firstMatch
        XCTAssertTrue(library.exists)
        XCTAssertGreaterThan(library.frame.midX, app.frame.midX)
        XCTAssertLessThan(library.frame.maxY, status.frame.minY)
        library.tap()
        let back = app.buttons["返回"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let original = status.label
        app.buttons["相册添加"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, original)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Image face search"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
