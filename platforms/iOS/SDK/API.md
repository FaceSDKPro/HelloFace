**English** | [简体中文](API.zh-CN.md)

# HiFace iOS 0.8.16 SDK API Guide

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

`HiFaceSDK()` initializes in the background. Static calls wait for readiness; discard a camera frame returning `.notReady`. The SDK does not manage cameras or permissions. The example is for one image; retain one instance for a realtime page rather than creating one per frame.

| `HiFaceConfiguration` parameter | Range and default | Purpose |
|---|---|---|
| `cpuThreads` | `.automatic` / `.two` / `.four`; default `.automatic` | Use the same policy for all instances in a process; it cannot change after the first session is created. |
| `modelDirectoryURL` | Local directory URL; default `nil` | Uses packaged SDK resources by default. A custom directory must contain the complete model resources; manual integration must preserve both frameworks and their resources. |

## API reference

### Face detection

Call `sdk.processFrame(frame, configuration: config)`. A successful result contains face boxes, confidence, and landmarks. No faces returns an empty list. Coordinates refer to the rotated, unmirrored image.

| `FaceDetectionConfiguration` parameter | Range and default | Purpose |
|---|---|---|
| `maxFaces` | 1–10, default 1 | Limits the number of returned faces. |
| `includesDetailedLandmarks` | Boolean, off by default | Includes detailed contours and head angles when enabled. |

Use even camera frame dimensions, at most 1920 on the long side and 1080 on the short side. Rotation is 0°, 90°, 180°, or 270°.
Build a `HiFaceCameraFrame` from two-plane NV12 (`420v` or `420f`) with a BT.601/709 matrix attachment and the correct rotation. The synchronous call borrows the pixel buffer until return.

`isMirrored` describes the preview; it does not mirror recognition input or results. The app transforms overlays. Even with `includesDetailedLandmarks` enabled, check `mesh` and `headPose` separately for nil; angles are in degrees.

### Face enrollment and photo capture

| API | Result |
|---|---|
| `await sdk.extractFeature(from: image)` | Extracts a feature for the largest face. Returns `.imageNoFace` if no face is found, or `.imageFaceTooSmall` if either face dimension is under 100 pixels. |
| `await sdk.capture(image)` | Returns `feature` and an optional aligned preview, `alignedFace`. Save the feature after the user confirms enrollment. |
| `await sdk.captureFaces(image)` | Returns positions and individual capture results for up to 10 faces. No faces returns an empty list; a small face only affects its own entry. |
| `sdk.startCameraCapture(callbacks:)` | Guides the user through camera enrollment and delivers the result to the callback. |

Apply photo orientation first. Each SDK has one active static-image job and room for four waiting jobs. Submit batch photos one at a time. Photo APIs require no camera permission and perform no liveness check.

`HiFaceRGBAImage(rgba:width:height:)` accepts tightly packed RGBA8888 with exactly `width * height * 4` bytes and snapshots pixels on construction; the convenience APIs also accept `CGImage`. Display an aligned preview with `alignedFace?.makeCGImage()`. Strict single-face enrollment requires exactly one `captureFaces` entry with successful `capture`; largest-face APIs do not reject multi-person photos.

### Liveness and 1:1 verification

Start `sdk.startCameraLiveness(configuration:callbacks:)` or `sdk.startCameraVerification(configuration:callbacks:)`, then keep sending camera frames. If you already have both face features, `await sdk.compare(feature:with:)` returns a similarity score from 0 to 1. It measures how close the features are.

| Parameter | Range and default | Purpose |
|---|---|---|
| `referenceFeature` | Required for 1:1 verification | The enrolled face feature. |
| `threshold` | Recommended 0.75–0.85; default 0.80 | Minimum 1:1 similarity. A completed comparison below this threshold returns a mismatch. |
| `actions` | 0–4 actions, empty by default | An empty action list still runs passive liveness in the liveness flow. |
| `requiresSilentLiveness` | Boolean, off by default for 1:1 verification | Also requires passive liveness when enabled. |
| `allowsMultipleFaces` | Boolean, off by default | Controls whether the flow accepts more than one face in view. |
| `actionTimeoutMilliseconds` | 2,000–30,000 ms, default 3,000 ms | Time budget per action. |
| `faceAcquisitionTimeoutMilliseconds` | 1,000–60,000 ms, default 10,000 ms | Time to find the first usable face. |

`actions` run in order and may repeat: `.shakeHead`, `.nodHead`, `.blink`, `.openMouth`. With no actions and `requiresSilentLiveness=false`, 1:1 checks identity without liveness. Only `FaceFlowResult.passed` indicates acceptance. Nil `similarity` or `livenessScore` means unavailable, not zero; an image does not indicate acceptance. `frameWidth` and `frameHeight` are JPEG pixel dimensions, or zero without an image.

The recommended similarity range is 0.75–0.85, with 0.80 as the default configuration value. The 1:1 and feature-query APIs accept 0–1; camera search accepts only 0.75–0.85.

The recommended RGB/IR liveness threshold is 0.80–0.99, starting at 0.90. RGB passive liveness currently uses a fixed 0.90 with no public threshold setting. IR requires an explicit threshold and has no implicit default. The liveness and verification `onResult` callback carries both acceptance and rejection. Check `outcome` first. Read similarity or liveness scores only when present. For standalone infrared liveness, call `await sdk.evaluateInfraredLiveness(_:realThreshold:)` with a real GRAY8 infrared frame, its face box, and a required threshold calibrated on the target camera (recommended 0.80–0.99, starting at 0.90; the API accepts values greater than 0 and at most 1).

### Face library and search

Open an independent library with `HiFaceSDK.openSearchDatabase()`. Use `saveFeature` or `saveFeatures` to add or update by Face ID. Save 1–1,000 records per batch. Use `search` to query by a face feature. `entries` / `recentEntries` returns metadata, and `featureEntries` pages through records with features. Close an explicitly opened library when finished. Call methods on the database actor with `try await` where required.

A library holds at most 50,000 records. A batch succeeds or rolls back as a whole; the last duplicate ID in the batch wins. `contains(faceID:)` reports existence, `entry(faceID:)` throws `.notFound` if absent, and `delete(faceID:)` reports whether a record was removed.

Pagination uses `offset` from 0 through `Int32.max` (default 0) and `limit` from 1–1,000 (default 100). `entries` and `featureEntries` sort by Face ID; `recentEntries` sorts newest first. `updateTimeMilliseconds` uses Unix milliseconds; the default 0 selects the current time and negative values are invalid. For `updateMetadata`, nil preserves and empty clears a group or tag; supply at least one. Use `await database.close()` to close the connection; closing the SDK does not close independently opened connections.

**Face records and filters**

| Parameter | Range and default | Purpose |
|---|---|---|
| Face ID | Required; 1–1024 UTF-8 bytes; no NUL; no default | Application-assigned record ID. Saving the same ID updates that record. It is not a group or tag filter. |
| `group` | Optional; at most 1024 bytes (UTF-8); no NUL; unrestricted by default | The record's group. Queries match it exactly; `nil` or empty means any group. |
| `tag` | Optional; at most 1024 bytes (UTF-8); no NUL; unrestricted by default | An application-defined label. Queries match it exactly; `nil` or empty means any tag. |

When both filters are supplied, both must match. With neither filter, search the whole library.

**Query by an existing feature (`FaceSearchConfiguration`)**

| Parameter | Range and default | Purpose |
|---|---|---|
| `topK` | 1–100, default 1 | Maximum number of matches returned. |
| `threshold` | Recommended 0.75–0.85; default 0.80 | Applies to feature queries. Returns records at or above the threshold, or an empty list. Camera search uses the separate range below. |

Use `sdk.startCameraSearch(configuration:callbacks:)` for continuous search. It manages its own library connection.

| Continuous search parameter | Range and default | Purpose |
|---|---|---|
| `mode` | `.singleFace` / `.multiFace`; default `.singleFace` | Single-face mode selects the largest face. Multi-face mode processes up to `maxFacesPerFrame` faces. |
| `needsLiveness` | `true` / `false`; default `true` in single-face mode and `false` in multi-face mode | Enables RGB passive liveness. Multi-face mode rejects `true`. |
| `threshold` | 0.75–0.85 inclusive, default 0.80 | Camera-search identity threshold. Similarity must be at least this value; required liveness must also pass. |
| `searchIntervalMilliseconds` | 0–3,000 ms, default 0 | Delay before the next attempt after a match. |
| `searchTimeoutMilliseconds` | 1,000–3,000 ms, default 3,000 ms | Time budget from the first selected face. |
| `maxFacesPerFrame` | 1–5, default 3 | Face limit in multi-face mode. Single-face mode selects the largest face. |

`startCameraSearch` immediately returns a session; keep feeding fresh frames during preparation. `pause()` retains the camera-flow slot, so close it before capture or verification. `resume()` resumes it; `update(configuration:)` replaces settings and invalidates old results. Use `onFrame` for display and `onResult` for business decisions. Technical errors pause the session; fix the cause before `resume()`. Closed sessions cannot be reused.

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
| `.resourceExhausted` | Reduce concurrency and check memory, disk space and capacity before retrying. |
| `.databaseError` | Check the database path, permissions and storage; preserve the data rather than deleting it automatically. |
| `.internalError` | Stop this request and contact support with the SDK version and error code. |

Capture, liveness, verification, and continuous search share one camera flow slot. When switching or leaving, stop feeding frames, cancel the request or close the search, then close the SDK. `onError` reports technical failures. Inspect the outcome for business results.

Keep camera input valid until the synchronous frame call returns, and retain static-image input until its awaited operation finishes. Result images are optional and do not indicate acceptance. Cancellation and close do not synthesize a terminal callback.

Cancel a camera method's `FaceRequest` with `cancel()`; cancellation does not synthesize a terminal callback. Static-image async calls have no such handle: canceling a Swift `Task` does not abort the SDK job. After awaiting, check task cancellation or page validity. `close()` does not wait for in-flight operations; stop submitting work to the old instance.

The current model does not support face recognition for people under 12. Financial use is prohibited. Outdoor face search requires a camera with a wide dynamic range greater than 100 dB.
