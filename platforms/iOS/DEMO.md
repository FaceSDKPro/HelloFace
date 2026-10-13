# HiFace iOS SDK and Demo Guide

English | [简体中文](DEMO.zh-CN.md)

The development Demo uses bundle ID `com.hiface.sdk.public`.

<!-- SDK-USER-GUIDE:BEGIN -->
## Installation

Beta expires at **2026-12-26 00:00 (UTC+08:00)**. Upgrade before expiry. [Updates](https://github.com/FaceSDKPro/).

| Requirement | Supported |
|---|---|
| iOS | 15 and later |
| Device | `arm64` |
| Simulator | `arm64`, `x86_64` |
| Entry point | Swift `HiFaceSDK` |

Add the released binary Swift package to Xcode with a fixed version and select the `HiFace` product. Keep both `HiFace` and `HiFaceNative` binary targets. Configure `NSCameraUsageDescription` in the host Info.plist.

```swift
import HiFace
let sdk = HiFaceSDK()
```

The SDK owns its model bundle. Do not override it with the host App bundle.

## Live detection and frame ownership

Use two-plane NV12 `420v` / `420f` buffers with a BT.601 or BT.709 matrix attachment.

```swift
let frame = try HiFaceCameraFrame(
    pixelBuffer: pixelBuffer,
    rotation: .degrees90,
    isMirrored: usingFrontCamera
)
let result = sdk.processFrame(frame, configuration: try FaceDetectionConfiguration(
    maxFaces: 5, includesDetailedLandmarks: true
))
```

`processFrame` is synchronous and borrows/locks the pixel buffer only during the call. Reuse it afterward. Initialization, model switching, and native backpressure may return `.notReady`; discard that frame and continue sending the latest frames.

Dimensions must be even, with long side at most `HiFaceCameraFrame.maximumLongSidePixels` (1920) and short side at most `maximumShortSidePixels` (1080). The host selects compatible camera formats. Coordinates belong to the rotated, unmirrored image; the host maps aspect-fit/fill, crop, scaling, and front-camera mirroring.

## Static images and HF1

```swift
let capture = await sdk.capture(cgImage)
let feature = await sdk.extractFeature(from: cgImage)
let similarity = await sdk.compare(feature: leftHF1, with: rightHF1)
let imageSimilarity = await sdk.compare(leftCGImage, with: rightCGImage)
```

Static entry points select the largest face. `capture` returns HF1 and an optional 333×333 aligned preview; extraction alone avoids generating a preview. Compare existing HF1 features to avoid repeated detection and extraction.

Normalize EXIF orientation before creating a `CGImage`; its entry point does not read `UIImage.imageOrientation`. Odd dimensions crop the last row/column only. Final RGBA8888 dimensions must be even and within 2–4096. `HiFaceRGBAImage` copies input pixels. Each instance queues one running and four waiting static requests; further requests return `.busy`. A two-image comparison is one indivisible request.

HF1 is a 604-character Q7/Base64URL representation, **not encryption**. Protect stored images/features according to your application requirements.

## Capture, liveness, and 1:1 verification

Keep sending frames during a camera flow. Only one capture, liveness, verification, or search flow may use the SDK camera slot at a time. Callbacks arrive asynchronously on `MainActor`.

```swift
let request = sdk.startCameraCapture(callbacks: FaceCaptureCallbacks(
    onProgress: { progress in /* Update guidance. */ },
    onResult: { capture in /* Save capture.feature after confirmation. */ },
    onError: { error in /* Handle a technical failure. */ }
))
let callbacks = FaceFlowCallbacks(
    onProgress: { progress in /* Update action/liveness guidance. */ },
    onResult: { result in /* Check result.outcome first. */ },
    onError: { error in /* Handle a technical failure. */ }
)
// Start these separately, after ending any existing camera flow.
let liveness = sdk.startCameraLiveness(
    configuration: try FaceLivenessConfiguration(actions: [.blink, .shakeHead]),
    callbacks: callbacks
)
let verification = sdk.startCameraVerification(
    configuration: try FaceVerificationConfiguration(
        referenceFeature: referenceHF1, requiresSilentLiveness: true,
        actions: [.blink, .shakeHead]),
    callbacks: callbacks
)
```

`onResult` includes both acceptance and rejection. Check `FaceFlowResult.outcome`; technical errors use `onError`. A nil similarity or liveness score means the stage did not produce a result, not zero. Empty actions still run seven-frame passive liveness with both models. Core applies the 0.90 passive liveness threshold; do not repeat the decision in the UI. Use the public configuration defaults and `maximumActionCount` for supported limits.

Stop frame delivery and cancel the active request when leaving, backgrounding, or switching cameras. Then close the SDK. `cancel()` / `close()` suppress stale callbacks immediately and release native resources after in-flight calls finish.

## Face library and continuous search

The database is independent of inference and serializes operations on an actor.

```swift
let database = try HiFaceSDK.openSearchDatabase()
let exists = try await database.contains(faceID: "user-1")
try await database.saveFeature(faceID: "user-1", feature: hf1, group: "staff")
try await database.saveFeatures(featureBatch)
let matches = try await database.search(feature: hf1)
let record = try await database.entry(faceID: "user-1")
let metadata = try await database.recentEntries()
let exportPage = try await database.featureEntries(offset: 0, limit: 100)
try await database.updateMetadata(faceID: "user-1", group: "building-A")
await database.close()
```

The SDK manages a private Application Support database excluded from cloud backup. Face IDs contain 1–1024 UTF-8 bytes; group/tag allow at most 1024 bytes; NUL is not allowed. Save operations upsert by ID; atomic batches accept 1–1000 entries. Check `contains` before prompting for overwrite.

SQLite stores the original 450-byte Q7 payload. Full record/search/feature-page results return complete HF1 without re-quantization; `entries` and `recentEntries` return metadata only. `updateMetadata` preserves nil fields and clears empty fields. Validate server features using `FaceFeatureFormat.featureSpaceID` (`hiface-feature-new-v1`) and `FaceSearchFeatureEntry`. Compression and iOS file protection are not database encryption.

```swift
let search = sdk.startCameraSearch(configuration: .default, callbacks: FaceSearchCallbacks(
    onFrame: { frame in /* Draw current faces and available scores. */ },
    onProgress: { progress in /* Update guidance. */ },
    onResult: { result in /* Check endReason first. */ },
    onError: { error in /* Recover if appropriate, then resume. */ }
))
search.pause()
search.update(configuration: newConfiguration)
search.resume()
search.close()
```

Search manages its own database connection. Pause retains the models, connection, and flow slot but releases the selected gallery cache after in-flight processing. Resume warms the scope again before accepting new frames. `releaseMemory()` applies to an explicit database handle.

Correlate callbacks by `frameID`. An unscored detection (`similarity == nil`) is not an unmatched result. Use final `endReason`; `.spoofDetected` rejects the result even when similarity passes. After 10 seconds without faces, analysis targets 200 ms intervals; skipped frames return `.notReady`. Search interval controls the wait after successful matching, not camera FPS.

Use stable `HiFaceError.code` for decisions. Keep business outcomes separate from technical errors. SDK diagnostics remain internal; localize host presentation using error codes. The host owns consent, retention, protection, and deletion of biometric data.
<!-- SDK-USER-GUIDE:END -->

## Run the Demo

Open `HiFaceDemo.xcodeproj` in Xcode and run `HiFaceDemo` on an iPhone. The development project uses the binary SDK in `../sdk/Artifacts`. Configure your Team and bundle ID. The home page provides seven capabilities and device version/model details.

| Area | Source |
|---|---|
| Camera | [CameraPipeline](HiFaceDemo/Camera/CameraPipeline.swift) |
| Camera flows | [CameraDemoModel](HiFaceDemo/Camera/CameraDemoModel.swift) |
| Face library | [SearchLibraryView](HiFaceDemo/Search/SearchLibraryView.swift) |

Resolution adapts to the lens; actual size/zoom appears on camera pages. Reopen the page after changing settings. Simulators and My Mac do not replace iPhone camera validation.

## Languages and imports

The Demo uses Simplified Chinese in system regions CN/HK/MO/TW and English elsewhere. Restart after changing the region. SDK diagnostics stay in Chinese; the Demo translates errors by code. Native permission dialogs follow system settings.

`features_10000.json` provides 10,000 offline HF1 features; `images_1000.json` lists 1,000 online images. Both are Demo data. These files are excluded from `HiFace.framework` and XCFramework/SPM packages. Images download up to five at a time, extract serially and save every 100 successes; feature imports save every 1000 entries.

Progress shows processed and saved counts. Back during import offers **Continue import** or **Stop and exit**. Stop finishes the current operation, saves the completed tail batch and reports saved/failed counts. Failed images are skipped; database errors keep earlier saved batches. Wait for import cleanup before closing SDK/database resources.

## Data and troubleshooting

Replace sample identities, features and URLs before production. HF1 is encoding; SDK SQLite is not encrypted. Protect biometric data and implement retention/deletion in your App. 1:1 references use Keychain and are isolated by feature space.

For model errors, retain the SDK model bundle. For camera-size errors, select a supported even size within 1920×1080. Test camera permission recovery, rotation, foreground/background changes and all flows on target phones.

Edit the bilingual Demo string catalogs.
