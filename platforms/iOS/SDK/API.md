# HiFace iOS 0.8.13 SDK API Guide

English | [简体中文](API.zh-CN.md)

## Quick start

Requires Xcode with Swift 6 and an iOS 15+ device. In Xcode, add the delivered `SDK` folder as a local Swift package, or add the published binary Swift package and select its version. Link the `HiFace` product, which includes both `HiFace` and `HiFaceNative`.

In a SwiftUI iOS app, replace `ContentView.swift` with the following and run on an iPhone. Expect `imageNoFace` for the blank image. The Apple Silicon simulator can build and launch the app, but inference needs a device. Add `NSCameraUsageDescription` when integrating a camera flow.

```swift
import Foundation
import HiFace
import SwiftUI

struct ContentView: View {
    @State private var status = "Running…"

    var body: some View {
        Text(status).task { await extractFeature() }
    }

    private func extractFeature() async {
        let sdk = HiFaceSDK()
        defer { sdk.close() }
        do {
            let image = try HiFaceRGBAImage(
                rgba: Data(repeating: 0, count: 256 * 256 * 4),
                width: 256, height: 256
            )
            switch await sdk.extractFeature(from: image) {
            case .success:
                status = "Feature extracted"
            case .failure(let error):
                status = String(describing: error.code)
            }
        } catch {
            status = String(describing: error)
        }
    }
}
```

## API reference

### Face detection

Call `sdk.processFrame(frame, configuration: config)`. A successful result contains face boxes, confidence, and landmarks. No faces returns an empty list. Coordinates refer to the rotated, unmirrored image.

| `FaceDetectionConfiguration` parameter | Range and default | Purpose |
|---|---|---|
| `maxFaces` | 1–10, default 1 | Limits the number of returned faces. |
| `includesDetailedLandmarks` | Boolean, off by default | Includes detailed contours and head angles when enabled. |

Use even camera frame dimensions, at most 1920 on the long side and 1080 on the short side. Rotation is 0°, 90°, 180°, or 270°.
Build a `HiFaceCameraFrame` from two-plane NV12 (`420v` or `420f`) with a BT.601/709 matrix attachment and the correct rotation. The synchronous call borrows the pixel buffer until return.

### Face enrollment and photo capture

| API | Result |
|---|---|
| `await sdk.extractFeature(from: image)` | Extracts a feature for the largest face. Returns `.imageNoFace` if no face is found, or `.imageFaceTooSmall` if either face dimension is under 100 pixels. |
| `await sdk.capture(image)` | Returns `feature` and an optional aligned preview, `alignedFace`. Save the feature after the user confirms enrollment. |
| `await sdk.captureFaces(image)` | Returns positions and individual capture results for up to 10 faces. No faces returns an empty list; a small face only affects its own entry. |
| `sdk.startCameraCapture(callbacks:)` | Guides the user through camera enrollment and delivers the result to the callback. |

Apply photo orientation first. Each SDK has one active static-image job and room for four waiting jobs. Submit batch photos one at a time. Photo APIs require no camera permission and perform no liveness check.

### Liveness and 1:1 verification

Start `sdk.startCameraLiveness(configuration:callbacks:)` or `sdk.startCameraVerification(configuration:callbacks:)`, then keep sending camera frames. If you already have both face features, `await sdk.compare(feature:with:)` returns a similarity score from 0 to 1. It measures how close the features are.

| Parameter | Range and default | Purpose |
|---|---|---|
| `referenceFeature` | Required for 1:1 verification | The enrolled face feature. |
| `threshold` | 0–1, default 0.80 | Minimum 1:1 similarity. A completed comparison below this threshold returns a mismatch. |
| `actions` | 0–4 actions, empty by default | An empty action list still runs passive liveness in the liveness flow. |
| `requiresSilentLiveness` | Boolean, off by default for 1:1 verification | Also requires passive liveness when enabled. |
| `allowsMultipleFaces` | Boolean, off by default | Controls whether the flow accepts more than one face in view. |
| `actionTimeoutMilliseconds` | 2,000–30,000 ms, default 3,000 ms | Time budget per action. |
| `faceAcquisitionTimeoutMilliseconds` | 1,000–60,000 ms, default 10,000 ms | Time to find the first usable face. |

RGB passive liveness uses an SDK threshold of 0.90. The liveness and verification `onResult` callback carries both acceptance and rejection. Check `outcome` first. Read similarity or liveness scores only when present. For standalone infrared liveness, call `await sdk.evaluateInfraredLiveness(_:realThreshold:)` with a real GRAY8 infrared frame, its face box, and a required 0–1 threshold calibrated on the target camera.

### Face library and search

Open an independent library with `HiFaceSDK.openSearchDatabase()`. Use `saveFeature` or `saveFeatures` to add or update by Face ID. Save 1–1,000 records per batch. Use `search` to query by a face feature. `entries` / `recentEntries` returns metadata, and `featureEntries` pages through records with features. Close an explicitly opened library when finished. Call methods on the database actor with `try await` where required.

| Database query parameter | Range and default | Purpose |
|---|---|---|
| Face ID, `group`, `tag` | 1–1024 UTF-8 bytes for Face ID, at most 1024 bytes per filter, no NUL | Group and tag match exactly. If both are set, both must match. Leave both unset to search the whole library. |
| `topK` | 1–100, default 1 | Maximum number of matches returned. |
| `threshold` | 0–1, default 0.80 | Minimum similarity for a database match. A query without a qualifying match returns an empty list. |

Use `sdk.startCameraSearch(configuration:callbacks:)` for continuous search. It manages its own library connection.

| Continuous search parameter | Range and default | Purpose |
|---|---|---|
| `mode`, `needsLiveness` | Single-face with liveness by default; multi-face search has no liveness | Selects the largest face or analyzes multiple faces. |
| `threshold` | 0.75–0.85, default 0.80 | Minimum identity score in continuous search. |
| `searchIntervalMilliseconds` | 0–3,000 ms, default 0 | Delay before the next attempt after a match. |
| `searchTimeoutMilliseconds` | 1,000–3,000 ms, default 3,000 ms | Time budget from the first selected face. |
| `maxFacesPerFrame` | 1–5, default 3 | Face limit in multi-face mode. Single-face mode selects the largest face. |

Check `endReason` first. A `.spoofDetected` outcome rejects a match even if similarity passes. `frameID` identifies one camera sample. `frameJPEG` is an optional full scene from the terminal sample. Use the original frame size to map its face boxes.

Store returned features as-is. When changing to an incompatible model, re-extract features from the original photos and reimport them. The host app handles consent, protection, and deletion of photos and features.

## Errors and cleanup

Static and frame APIs return Swift `Result`; configuration initializers and database APIs may throw. Branch on `HiFaceError.code`. Camera callbacks are delivered on `MainActor`. Keep one SDK per feature screen and close it when finished.

| Condition | What to do |
|---|---|
| `.notReady` | While models initialize, the runtime is busy, or a camera frame is skipped, drop the old frame and keep submitting the latest one. |
| `.busy` | Wait for static jobs to finish or end the current camera flow. |
| `.invalidArgument` | Check the parameters, frame format, and buffers. |
| `.licenseExpired` | Check the validity dates and contact SDK support if needed. |
| `.closed` | Stop sending work to this instance. |

Capture, liveness, verification, and continuous search share one camera flow slot. When switching or leaving, stop feeding frames, cancel the request or close the search, then close the SDK. `onError` reports technical failures. Inspect the outcome for business results.

The current model does not support face recognition for people under 12. Financial use is prohibited. Outdoor face search requires a camera with a wide dynamic range greater than 100 dB.
