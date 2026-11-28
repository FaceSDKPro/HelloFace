import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import HiFace
import XCTest
@testable import HiFaceDemo

/// Run inside the real Demo App against the binary SDK; exercise model resources and HF1 storage without a camera.
/// 在真实 Demo App 内针对二进制 SDK 运行，无需相机即可验证模型资源与 HF1 存储。
final class ModelResourceTests: XCTestCase {
    func testAccessPromptsEndWithTheStableCodeExactlyOnce() {
        let numbers: [HiFaceErrorCode: Int] = [
            .licenseMissing: 1602, .licenseInvalid: 1603, .licenseNotYetValid: 1604,
            .licenseExpired: 1605, .licenseFeatureDenied: 1606, .licenseClockInvalid: 1608
        ]
        for code in HiFaceErrorCode.allCases {
            let prompt = DemoErrorPresentation.accessMessage(for: code)
            if let number = numbers[code] {
                let expected = DemoL10n.text("功能不可用（错误码 {0}）", [String(number)])
                XCTAssertEqual(prompt, expected)
                XCTAssertEqual(DemoErrorPresentation.message(for: HiFaceError(code: code, message: "")), expected)
                XCTAssertEqual(expected.components(separatedBy: String(number)).count, 2)
            } else {
                XCTAssertNil(prompt)
            }
        }
    }

    private func requireDeviceRuntime() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("The simulator SDK is compile/link-only; native runtime acceptance requires a physical iOS device")
        #endif
    }

    /// Supply the synthetic 224 x 224 gray fixture in the private XCTest bundle for physical-device inference.
    @MainActor
    func testAlbumReferenceWithSyntheticPortraitOnDevice() async throws {
        try requireDeviceRuntime()
        guard let url = Bundle(for: Self.self).url(forResource: "synthetic-face", withExtension: "gray") else {
            throw XCTSkip("Supply synthetic-face.gray in the test bundle")
        }
        let gray = try Data(contentsOf: url)
        XCTAssertEqual(gray.count, 224 * 224)
        let model = CameraDemoModel(mode: .capture)
        let existing = try DemoFaceStore.faceIDs()
        let selection = try DemoFaceStore.selectedFaceID(among: existing)
        let id = "album-device-" + UUID().uuidString
        defer {
            try? DemoFaceStore.delete(faceID: id)
            if let selection { try? DemoFaceStore.select(faceID: selection) }
        }
        for count in [0, 2, 1] {
            let width = 224 * max(count, 1)
            var rgba = Data(capacity: width * 224 * 4)
            for y in 0..<224 {
                for x in 0..<width {
                    let level: UInt8 = count == 0 ? 128 : gray[y * 224 + x % 224]
                    rgba.append(contentsOf: [level, level, level, 255])
                }
            }
            let image = try HiFaceRGBAImage(rgba: rgba, width: width, height: 224)
            do {
                try await model.prepareAlbumReference(image)
                XCTAssertEqual(count, 1)
            } catch ReferencePhotoError.requiresSingleFace {
                XCTAssertNotEqual(count, 1)
            }
            XCTAssertEqual(model.pendingReferenceFeature != nil, count == 1)
            XCTAssertNil(try DemoFaceStore.feature(for: id))
        }
        model.enrollmentFaceID = id
        XCTAssertTrue(model.saveCapturedReference())
        XCTAssertNil(model.alignedFace)
        XCTAssertNil(model.pendingReferenceFeature)
        XCTAssertTrue(try DemoFaceStore.feature(for: id)?.hasPrefix("HF1:") == true)
        await FacePhotoStore.remove(faceID: id, library: .reference)
    }

    @MainActor
    func testAlbumReferenceRequiresOneUsableFaceAndConfirmation() throws {
        let model = CameraDemoModel(mode: .capture)
        let bounds = FaceBounds(x: 0, y: 0, width: 224, height: 224)
        let crop = try HiFaceAlignedImage(rgba: Data(repeating: 128, count: 333 * 333 * 4))
        let sample = FaceCaptureResult(feature: "HF1:" + String(repeating: "A", count: 600), alignedFace: crop)
        let face = FaceImageCapture(bounds: bounds, capture: .success(sample))
        let small = FaceImageCapture(bounds: bounds, capture: .failure(HiFaceError(code: .imageFaceTooSmall, message: "")))
        let id = "album-test-" + UUID().uuidString
        model.enrollmentFaceID = id
        for invalid in [[], [small], [face, small], [face, face]] {
            XCTAssertThrowsError(try model.stageAlbumReference(invalid))
            XCTAssertFalse(model.canSaveCapturedReference)
        }
        try model.stageAlbumReference([face])
        XCTAssertNotNil(model.alignedFace)
        XCTAssertFalse(model.previewMirrored)
        XCTAssertNil(try DemoFaceStore.feature(for: id))
        XCTAssertTrue(model.canSaveCapturedReference)
        model.clearPendingCapture()
        XCTAssertNil(model.alignedFace)
        XCTAssertFalse(model.saveCapturedReference())
        XCTAssertNil(try DemoFaceStore.feature(for: id))
    }

    @MainActor
    func testSimulatorStubReportsUnavailableWithoutPretendingToRunModels() async throws {
        #if targetEnvironment(simulator)
        let sdk = HiFaceSDK()
        defer { sdk.close() }
        switch try await extractBlankImageFeature(sdk) {
        case .failure(let error):
            XCTAssertEqual(error.code, .modelLoadFailed)
            XCTAssertTrue(error.message.contains("iOS Simulator"))
        case .success:
            XCTFail("The simulator stub must not claim successful native inference")
        }
        #else
        throw XCTSkip("Simulator-only contract; device runtime is covered by the native tests")
        #endif
    }

    @MainActor
    func testImageSearchPreservesOriginalResolutionAndOddPixelCrop() async throws {
        for (width, height) in [(4032, 3024), (3024, 4032), (4096, 1024), (2049, 1025), (100, 100)] {
            try autoreleasepool {
                let encoded = try photoData(width: width, height: height)
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
                try encoded.write(to: temporary)
                defer { try? FileManager.default.removeItem(at: temporary) }
                let decoded = try StaticPhotoDecoder.decode(fileURL: temporary,
                    maximumPixelSize: FacePhotoPicker.imageSearchMaximumPixelSize).get()
                XCTAssertEqual(decoded.width, width & ~1)
                XCTAssertEqual(decoded.height, height & ~1)
                XCTAssertEqual(decoded.rgba.count, (width & ~1) * (height & ~1) * 4)
            }
        }
    }

    @MainActor
    func testImageSearchCapAndExifRotationKeepComparisonDefault() async throws {
        for (width, height, orientation, expectedWidth, expectedHeight) in [
            (6000, 3000, 1, 4096, 2048), (3000, 6000, 1, 2048, 4096),
            (2049, 1025, 6, 1024, 2048)
        ] {
            try autoreleasepool {
                let encoded = try photoData(width: width, height: height, orientation: orientation)
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
                try encoded.write(to: temporary)
                defer { try? FileManager.default.removeItem(at: temporary) }
                let decoded = try StaticPhotoDecoder.decode(fileURL: temporary,
                    maximumPixelSize: FacePhotoPicker.imageSearchMaximumPixelSize).get()
                XCTAssertEqual(decoded.width, expectedWidth)
                XCTAssertEqual(decoded.height, expectedHeight)
            }
        }
        let comparison = try StaticPhotoDecoder.decode(data: photoData(width: 3000, height: 2000)).get()
        XCTAssertEqual(comparison.width, 1080)
        XCTAssertEqual(comparison.height, 720)
    }

    private func photoData(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @MainActor
    func testImageFacesReturnEmptyOnBlankPhoto() async throws {
        try requireDeviceRuntime()
        let sdk = HiFaceSDK()
        defer { sdk.close() }
        let image = try HiFaceRGBAImage(rgba: Data(repeating: 128, count: 332 * 332 * 4), width: 332, height: 332)
        let faces = try await sdk.captureFaces(image).get()
        XCTAssertTrue(faces.isEmpty, "An empty detection is successful; it must not manufacture a capture")
    }

    @MainActor
    func testQ7DatabasePreservesHF1ScoresAndReopens() async throws {
        try requireDeviceRuntime()
        let resource = try XCTUnwrap(Bundle.main.url(forResource: "features_10000", withExtension: "json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: resource)) as? [String: Any])
        let records = try XCTUnwrap(manifest["entries"] as? [[String: Any]])
        let first = try XCTUnwrap(records[0]["feature"] as? String)
        let second = try XCTUnwrap(records[1]["feature"] as? String)
        let group = "q7-regression-" + UUID().uuidString
        let sdk = HiFaceSDK()
        defer { sdk.close() }
        let score = try await sdk.compare(feature: first, with: second).get()
        let configuration = try FaceSearchConfiguration(group: group, topK: 2, threshold: 0)
        let database = try HiFaceSDK.openSearchDatabase()
        do {
            try await database.saveFeature(faceID: group + "-a", feature: first, group: group)
            try await database.saveFeatures([
                try FaceSearchFeatureEntry(faceID: group + "-b", feature: second, group: group)
            ])
            let before = try await database.search(feature: first, configuration: configuration)
            XCTAssertEqual(before.count, 2)
            XCTAssertEqual(before.first?.score, 1)
            XCTAssertEqual(before.last?.score, score)
            let firstEntry = try await database.entry(faceID: group + "-a")
            XCTAssertEqual(firstEntry.feature, first)
            XCTAssertEqual(firstEntry.featureSpaceID, FaceFeatureFormat.featureSpaceID)
            try await database.updateMetadata(faceID: group + "-a", tag: "metadata-only", updateTimeMilliseconds: 123)
            let updated = try await database.entry(faceID: group + "-a")
            XCTAssertEqual(updated.feature, first)
            XCTAssertEqual(updated.group, group)
            XCTAssertEqual(updated.tag, "metadata-only")
            let metadata = try await database.recentEntries(group: group)
            XCTAssertEqual(metadata.count, 2)
            let exported = try await database.featureEntries(group: group)
            XCTAssertEqual(exported.map(\.feature), [first, second])
            do {
                _ = try await database.featureEntries(offset: Int(Int32.max) + 1)
                XCTFail("An overflowing page offset must be rejected")
            } catch let error as HiFaceError {
                XCTAssertEqual(error.code, .invalidArgument)
            }
            try await database.updateMetadata(faceID: group + "-a", tag: "", updateTimeMilliseconds: firstEntry.updateTimeMilliseconds)
            await database.close()

            let reopened = try HiFaceSDK.openSearchDatabase()
            do {
                let after = try await reopened.search(feature: first, configuration: configuration)
                XCTAssertEqual(after, before)
                let restored = try await reopened.entry(faceID: group + "-a")
                XCTAssertEqual(restored.feature, firstEntry.feature)
                _ = try await reopened.delete(faceID: group + "-a")
                _ = try await reopened.delete(faceID: group + "-b")
                await reopened.close()
            } catch {
                _ = try? await reopened.delete(faceID: group + "-a")
                _ = try? await reopened.delete(faceID: group + "-b")
                await reopened.close()
                throw error
            }
        } catch {
            _ = try? await database.delete(faceID: group + "-a")
            _ = try? await database.delete(faceID: group + "-b")
            await database.close()
            throw error
        }
    }

    @MainActor
    func testDemoLoadsFrameworkModelsWithoutAnAppModelDirectory() async throws {
        try requireDeviceRuntime()
        let appModels = try XCTUnwrap(Bundle.main.resourceURL)
            .appendingPathComponent("HiFaceModels", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appModels.path),
                       "This regression must exercise SDK-owned resources, without an App model copy")
        let sdk = HiFaceSDK()
        defer { sdk.close() }

        switch try await extractBlankImageFeature(sdk) {
        case .failure(let error):
            XCTAssertEqual(error.code, .imageNoFace,
                           "Native detector and feature models must load before rejecting a blank image: \(error.message)")
        case .success:
            XCTFail("A blank image must not produce a face feature")
        }
    }

    @MainActor
    func testAnExplicitMissingModelDirectoryReportsModelLoadFailure() async throws {
        try requireDeviceRuntime()
        let missingModels = try XCTUnwrap(Bundle.main.resourceURL)
            .appendingPathComponent("MissingHiFaceModels", isDirectory: true)
        let sdk = HiFaceSDK(configuration: HiFaceConfiguration(modelDirectoryURL: missingModels))
        defer { sdk.close() }

        switch try await extractBlankImageFeature(sdk) {
        case .failure(let error):
            XCTAssertEqual(error.code, .modelLoadFailed)
            XCTAssertTrue(error.message.contains("kcehc.bphfm"))
        case .success:
            XCTFail("An explicit missing model directory must not silently use another resource location")
        }
    }

    @MainActor
    private func extractBlankImageFeature(_ sdk: HiFaceSDK) async throws -> Result<String, HiFaceError> {
        let image = try HiFaceRGBAImage(rgba: Data(repeating: 0, count: 64 * 64 * 4), width: 64, height: 64)
        for _ in 0..<250 {
            let result = await sdk.extractFeature(from: image)
            if case .failure(let error) = result, error.code == .notReady {
                try await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            return result
        }
        XCTFail("Native SDK initialization did not complete within five seconds")
        return .failure(HiFaceError(code: .notReady, message: "Initialization timeout"))
    }
}

final class CameraSwitchTests: XCTestCase {
    @MainActor
    func testCameraReadyAfterSettingsRestartsDetection() {
        let model = CameraDemoModel(mode: .detection)
        model.start()
        defer { model.stop() }
        model.pipeline.onError?("Denied", true)
        XCTAssertTrue(model.needsCameraSettings)
        XCTAssertEqual(model.phase, .failed)
        model.suspend()
        model.start()
        model.pipeline.onStarted?()
        XCTAssertFalse(model.needsCameraSettings)
        XCTAssertEqual(model.phase, .running)
    }

    @MainActor
    func testChangingSearchSettingsWhileSuspendedKeepsCameraStopped() {
        let model = CameraDemoModel(mode: .search)
        model.start()
        defer { model.stop() }
        model.suspend()
        model.updateSearchConfiguration(model.searchConfiguration)
        model.resumeSearch()

        XCTAssertFalse(model.cameraReady)
        XCTAssertFalse(model.pipeline.switchCamera { _ in XCTFail("Suspended camera switched lenses") })
    }

    @MainActor
    func testRejectedSwitchLeavesTheVisibleFlowRunning() {
        let model = CameraDemoModel(mode: .detection)
        model.start()
        defer { model.stop() }

        // The screen still shows a running flow while the pipeline can no longer accept a switch.
        model.pipeline.stop()
        model.pipeline.onStarted?()
        XCTAssertEqual(model.phase, .running)
        let status = model.status
        model.switchCamera()
        XCTAssertFalse(model.isSwitchingCamera)
        XCTAssertEqual(model.phase, .running)
        XCTAssertEqual(model.status, status)
    }

    @MainActor
    func testInterruptionBeforeSwitchRecoversOnDevice() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires an active capture session on a physical iPhone")
        #else
        let model = CameraDemoModel(mode: .detection)
        model.start()
        defer { model.stop() }
        try await waitForRunningCamera(model)

        // AVFoundation notifies the pipeline synchronously. The screen learns of it on the next turn.
        let session = model.pipeline.captureSession
        NotificationCenter.default.post(name: AVCaptureSession.wasInterruptedNotification, object: session)
        model.switchCamera()
        XCTAssertFalse(model.isSwitchingCamera)
        XCTAssertEqual(model.phase, .running)
        for _ in 0..<100 where model.cameraReady {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(model.cameraReady)
        NotificationCenter.default.post(name: AVCaptureSession.interruptionEndedNotification, object: session)
        try await waitForRunningCamera(model)
        #endif
    }

    @MainActor
    private func waitForRunningCamera(_ model: CameraDemoModel) async throws {
        for _ in 0..<200 {
            if model.cameraReady && model.phase == .running { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Camera did not return to the running phase")
    }
}
