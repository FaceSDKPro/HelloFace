**English** | [简体中文](README.zh-CN.md)

# HiFace HarmonyOS SDK API Guide

## Quick start

Requires HarmonyOS API 20 or later and an ARM64 device. In a DevEco Studio ArkTS Empty Ability project, put the HAR in the project-root `libs/` folder and add this dependency in the entry module's `oh-package.json5`:

```json5
{
  "dependencies": {
    "hiface": "file:../libs/hiface-0.8.17.har"
  }
}
```

Run `ohpm install` from the project root; if this version is available in your registry, use `ohpm install hiface@0.8.17` instead of the file dependency, or set `"hiface": "0.8.17"` in the dependency list. Replace the entry page `pages/Index.ets` with the following and run the signed app on a device. Tap **Run HiFace**. The blank image should show `1201` (`IMAGE_NO_FACE`).

```typescript
import { common } from '@kit.AbilityKit';
import { HiFaceSdk, RgbaImage } from 'hiface';

@Entry
@Component
struct Index {
  @State status: string = 'Ready';
  private sdk?: HiFaceSdk;

  private async extractFeature(): Promise<void> {
    if (this.sdk !== undefined) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const sdk = HiFaceSdk.create(context);
    this.sdk = sdk;
    try {
      const ready = await sdk.whenReady();
      if (this.sdk !== sdk) {
        return;
      }
      if (ready.isFailure()) {
        this.status = String(ready.requireError().code);
        return;
      }
      const image = new RgbaImage(new ArrayBuffer(256 * 256 * 4), 256, 256);
      const result = await sdk.capture().extractFeature(image);
      if (this.sdk === sdk) {
        this.status = result.isSuccess() ? 'Feature extracted' : String(result.requireError().code);
      }
    } finally {
      if (this.sdk === sdk) {
        this.closeSdk();
      }
    }
  }

  private closeSdk(): void {
    this.sdk?.close();
    this.sdk = undefined;
  }

  aboutToDisappear(): void {
    this.closeSdk();
  }

  build() {
    Column() {
      Button('Run HiFace').onClick(() => { this.extractFeature(); })
      Text(this.status)
    }
  }
}
```

`create(context)` requires the current `UIAbilityContext`; the SDK does not create cameras or request permissions. Retain one instance in a regular field, outside `@State`. Await `whenReady()` and check the result's `isSuccess()`. Repeating it waits for the same initialization result; after initialization fails, fix the cause, close the old instance and create another.

## API reference

### Face detection

Call `sdk.processFrame(frame, config)` / `sdk.processRgba(image, config)`. A successful result contains face boxes, confidence, and landmarks. No faces returns an empty list. Coordinates refer to the rotated, unmirrored image.

| `FaceDetectionConfig` parameter | Range and default | Purpose |
|---|---|---|
| `maxFaces` | 1–10, default 1 | Limits the number of returned faces. |
| `detailedLandmarks` | Boolean, off by default | Includes detailed contours and head angles when enabled. |

Use even camera frame dimensions, at most 1920 on the long side and 1080 on the short side. Rotation is 0°, 90°, 180°, or 270°.
For camera input, give the actual Y/U/V strides, color range/matrix and rotation. Keep input buffers valid until the Promise completes. Use one `createRealtimeProcessor()` per stream and drop a frame when `tryProcessFrame()` returns `undefined`.

`YuvPlane.rowStride` and `pixelStride` are positive integer byte counts. Y pixel stride must be 1; U and V pixel strides must match. Set `range` to `VIDEO` / `FULL` and `matrix` to `BT601` / `BT709` from capture metadata. `mirrored` does not mirror the preview. Check `headPose` and `mesh` separately for undefined even when detailed landmarks are enabled.

An undefined `tryProcessFrame()` return means the frame was not accepted and may be released immediately. A returned Promise must finish before release, even if its result is `NOT_READY`. Closing the processor only stops new admission; it does not interrupt an in-flight Promise or close the SDK or camera.

### Face enrollment and photo capture

| API | Result |
|---|---|
| `await sdk.capture().extractFeature(image)` | Extracts a feature for the largest face. Returns `IMAGE_NO_FACE` if no face is found, or `IMAGE_FACE_TOO_SMALL` if either face dimension is under 100 pixels. |
| `await sdk.capture().fromRgba(image)` | Returns `feature` and an optional aligned preview, `alignedRgba`. Save the feature after the user confirms enrollment. |
| `await sdk.capture().facesFromRgba(image)` | Returns positions and individual capture results for up to 10 faces. No faces returns an empty list; a small face only affects its own entry. |
| `capture().startCameraCapture(listener)` | Guides camera enrollment. Await successful startup to obtain the `FaceRequest`. The callback delivers the result. |

Apply photo orientation first. Each SDK has one active static-image job and room for four waiting jobs. Submit batch photos one at a time. Photo APIs require no camera permission and perform no liveness check.

`RgbaImage` describes tightly packed RGBA8888, with at least `width * height * 4` bytes in `data`. Constructing it does not copy pixels; the static-image SDK calls snapshot the input before returning a Promise. Strict single-face enrollment requires exactly one `facesFromRgba` entry with successful `capture`. Largest-face APIs do not reject multi-person photos. `alignedRgba` contains RGBA bytes, not a `PixelMap`; use `alignedSide` for both display dimensions.

### Liveness and 1:1 verification

Start `liveness().startCameraLiveness(config, listener)` or `verification().startCameraVerification(config, listener)`, then keep sending camera frames. If you already have both face features, `verification().compare(left, right)` returns a similarity score from 0 to 1. It measures how close the features are.

| Parameter | Range and default | Purpose |
|---|---|---|
| `referenceFeature` | Required for 1:1 verification | The enrolled face feature. |
| `threshold` | Recommended 0.75–0.85; default 0.80 | Minimum 1:1 similarity. A completed comparison below this threshold returns a mismatch. |
| `actions` | 0–4 actions, empty by default | An empty action list still runs passive liveness in the liveness flow. |
| `silentLivenessEnabled` | Boolean, off by default for 1:1 verification | Also requires passive liveness when enabled. |
| `allowMultipleFaces` | Boolean, off by default | Controls whether the flow accepts more than one face in view. |
| `actionTimeoutMillis` | 2,000–30,000 ms, default 3,000 ms | Time budget per action. |
| `faceAcquisitionTimeoutMillis` | 1,000–60,000 ms, default 10,000 ms | Time to find the first usable face. |

`actions` run in order and may repeat: `SHAKE_HEAD`, `NOD_HEAD`, `BLINK`, `MOUTH_OPEN`. With no actions and `silentLivenessEnabled=false`, 1:1 checks identity without liveness. `FaceFlowResult.isPassed()` indicates acceptance; undefined `similarity` or `livenessScore` means unavailable, not zero. Aligned pixels and `frameJpeg` are optional; `frameWidth` and `frameHeight` are JPEG pixel dimensions, or zero without an image.

The recommended similarity range is 0.75–0.85, with 0.80 as the default configuration value. The 1:1 and feature-query APIs accept 0–1; camera search accepts only 0.75–0.85.

The recommended RGB/IR liveness threshold is 0.80–0.99, starting at 0.90. RGB passive liveness currently uses a fixed 0.90 with no public threshold setting. IR requires an explicit threshold and has no implicit default. The liveness and verification `onResult` callback carries both acceptance and rejection. Check `outcome` first. Read similarity or liveness scores only when present. For standalone infrared liveness, call `await sdk.liveness().evaluateInfrared(frame, threshold)` with a real GRAY8 infrared frame, its face box, and a required threshold calibrated on the target camera (recommended 0.80–0.99, starting at 0.90; the API accepts values greater than 0 and at most 1).

Wait for a successful `HiFaceResult<FaceRequest>` from the start call before feeding frames.

### Face library and search

Open an independent library with `await HiFaceSdk.openSearchDatabase(context)`. Use `saveFeature` or `saveFeatures` to add or update by Face ID. Save 1–1,000 records per batch. Use `search` to query by a face feature. `list` / `listRecent` returns metadata, and `listFeatures` pages through records with features. Close an explicitly opened library when finished. Await writes before closing the database.

A library holds at most 50,000 records. A batch succeeds or rolls back as a whole; the last duplicate ID wins. `contains` reports existence, `get` returns `NOT_FOUND` if absent, and `delete` reports whether a record was removed.

Pagination uses `offset` from 0–2,147,483,647 (default 0) and `limit` from 1–1,000 (default 100). `list` and `listFeatures` sort by Face ID; `listRecent` sorts newest first. `updateTimeMillis` is a nonnegative safe integer in Unix milliseconds; the default 0 uses the current time. For `updateMetadata`, undefined preserves a group or tag and empty clears it; supply at least one. Explicitly close independent connections; closing the SDK does not replace that step.

**Face records and filters**

| Parameter | Range and default | Purpose |
|---|---|---|
| Face ID | Required; 1–1024 UTF-8 bytes; no NUL; no default | Application-assigned record ID. Saving the same ID updates that record. It is not a group or tag filter. |
| `group` | Optional; at most 1024 bytes (UTF-8); no NUL; unrestricted by default | The record's group. Queries match it exactly; empty means any group. |
| `tag` | Optional; at most 1024 bytes (UTF-8); no NUL; unrestricted by default | An application-defined label. Queries match it exactly; empty means any tag. |

When both filters are supplied, both must match. With neither filter, search the whole library.

**Query by an existing feature (`FaceSearchConfig`)**

| Parameter | Range and default | Purpose |
|---|---|---|
| `topK` | 1–100, default 1 | Maximum number of matches returned. |
| `threshold` | Recommended 0.75–0.85; default 0.80 | Applies to feature queries. Returns records at or above the threshold, or an empty list. Camera search uses the separate range below. |

Use `search().startCameraSearch(config, listener)` for continuous search. It manages its own library connection.

| Continuous search parameter | Range and default | Purpose |
|---|---|---|
| `mode` | `SINGLE_FACE` / `MULTI_FACE`; default `SINGLE_FACE` | Single-face mode selects the largest face. Multi-face mode processes up to `maxFacesPerFrame` faces. |
| `needsLiveness` | `true` / `false`; default `true` in single-face mode and `false` in multi-face mode | Enables RGB passive liveness. Multi-face mode rejects `true`. |
| `threshold` | 0.75–0.85 inclusive, default 0.80 | Camera-search identity threshold. Similarity must be at least this value; required liveness must also pass. |
| `searchIntervalMillis` | 0–3,000 ms, default 0 | Delay before the next attempt after a match. |
| `searchTimeoutMillis` | 1,000–3,000 ms, default 3,000 ms | Time budget from the first selected face. |
| `maxFacesPerFrame` | 1–5, default 3 | Face limit in multi-face mode. Single-face mode selects the largest face. |

Await flow/search startup, check its result, then retain the `FaceRequest` or `FaceSearchSession`. The page may leave while awaiting; if the page or SDK is no longer current, cancel or close a newly returned handle. Search `pause()` retains its flow slot, so close before switching features. `setConfig()` updates settings and invalidates old results; `resume()` resumes. Use `onFrame` for display and `onResult` for business decisions; runtime errors pause the session until the cause is fixed.

Check `endReason` first. A `SPOOF_DETECTED` outcome rejects a match even if similarity passes. `frameId` identifies one camera sample. `frameJpeg` is an optional full scene from the terminal sample. Use the original frame size to map its face boxes.

Store returned features as-is. When changing to an incompatible model, re-extract features from the original photos and reimport them. The host app handles consent, protection, and deletion of photos and features.

Await a successful `HiFaceResult<FaceSearchSession>` and use the session to pause, resume or close the search.

## Errors and cleanup

Wait for `whenReady()` after creation. Check `HiFaceResult.isSuccess()` before reading `requireValue()` or `requireError().code`. Invalid constructor arguments throw `Error`. Keep the SDK in a regular field outside ArkUI observed state, and close it on teardown.

| Condition | What to do |
|---|---|
| `NOT_READY` | While models initialize, the runtime is busy, or a camera frame is skipped, drop the old frame and keep submitting the latest one. |
| `BUSY` | Wait for static jobs to finish or end the current camera flow. |
| `INVALID_ARGUMENT` | Check the parameters, frame format, and buffers. |
| `LICENSE_EXPIRED` | Check the validity dates and contact SDK support if needed. |
| `CLOSED` | Stop sending work to this instance. |
| `RESOURCE_EXHAUSTED` | Reduce concurrency and check memory, disk space and capacity before retrying. |
| `DATABASE_ERROR` | Check the database path, permissions and storage; preserve the data rather than deleting it automatically. |
| `INTERNAL_ERROR` | Stop this request and contact support with the SDK version and error code. |

Capture, liveness, verification, and continuous search share one camera flow slot. When switching or leaving, stop feeding frames, cancel the request or close the search, then close the SDK. `onError` reports technical failures. Inspect the outcome for business results.

Retain YUV input until its frame Promise completes; static RGBA snapshot timing is described above. Camera `FaceRequest.cancel()` only cancels the SDK flow, not CameraKit, preview or frame buffers. Static tasks return Promises without a cancellation handle; discard stale results at the page boundary. On exit, stop submission, cancel/close flows and processors, wait for accepted frames, then release camera resources. Close the SDK and independently opened databases separately.

The current model does not support face recognition for people under 12. Financial use is prohibited. Outdoor face search requires a camera with a wide dynamic range greater than 100 dB.
