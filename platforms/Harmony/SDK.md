# HiFace HarmonyOS SDK API Guide

## Quick start

Requires HarmonyOS API 20 or later and an ARM64 device. In a DevEco Studio ArkTS Empty Ability project, put the HAR in the project-root `libs/` folder and add this dependency in the entry module's `oh-package.json5`:

```json5
{
  "dependencies": {
    "hiface": "file:../libs/hiface-0.8.14.har"
  }
}
```

Run `ohpm install` from the project root; if this version is available in your registry, use `ohpm install hiface@0.8.14` instead of the file dependency, or set `"hiface": "0.8.14"` in the dependency list. Replace the entry page `pages/Index.ets` with the following and run the signed app on a device. Tap **Run HiFace**. The blank image should show `1201` (`IMAGE_NO_FACE`).

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

## API reference

### Face detection

Call `sdk.processFrame(frame, config)` / `sdk.processRgba(image, config)`. A successful result contains face boxes, confidence, and landmarks. No faces returns an empty list. Coordinates refer to the rotated, unmirrored image.

| `FaceDetectionConfig` parameter | Range and default | Purpose |
|---|---|---|
| `maxFaces` | 1–10, default 1 | Limits the number of returned faces. |
| `detailedLandmarks` | Boolean, off by default | Includes detailed contours and head angles when enabled. |

Use even camera frame dimensions, at most 1920 on the long side and 1080 on the short side. Rotation is 0°, 90°, 180°, or 270°.
For camera input, give the actual Y/U/V strides, color range/matrix and rotation. Keep input buffers valid until the Promise completes. Use one `createRealtimeProcessor()` per stream and drop a frame when `tryProcessFrame()` returns `undefined`.

### Face enrollment and photo capture

| API | Result |
|---|---|
| `await sdk.capture().extractFeature(image)` | Extracts a feature for the largest face. Returns `IMAGE_NO_FACE` if no face is found, or `IMAGE_FACE_TOO_SMALL` if either face dimension is under 100 pixels. |
| `await sdk.capture().fromRgba(image)` | Returns `feature` and an optional aligned preview, `alignedRgba`. Save the feature after the user confirms enrollment. |
| `await sdk.capture().facesFromRgba(image)` | Returns positions and individual capture results for up to 10 faces. No faces returns an empty list; a small face only affects its own entry. |
| `capture().startCameraCapture(listener)` | Guides camera enrollment. Await successful startup to obtain the `FaceRequest`. The callback delivers the result. |

Apply photo orientation first. Each SDK has one active static-image job and room for four waiting jobs. Submit batch photos one at a time. Photo APIs require no camera permission and perform no liveness check.

### Liveness and 1:1 verification

Start `liveness().startCameraLiveness(config, listener)` or `verification().startCameraVerification(config, listener)`, then keep sending camera frames. If you already have both face features, `verification().compare(left, right)` returns a similarity score from 0 to 1. It measures how close the features are.

| Parameter | Range and default | Purpose |
|---|---|---|
| `referenceFeature` | Required for 1:1 verification | The enrolled face feature. |
| `threshold` | 0–1, default 0.80 | Minimum 1:1 similarity. A completed comparison below this threshold returns a mismatch. |
| `actions` | 0–4 actions, empty by default | An empty action list still runs passive liveness in the liveness flow. |
| `silentLivenessEnabled` | Boolean, off by default for 1:1 verification | Also requires passive liveness when enabled. |
| `allowMultipleFaces` | Boolean, off by default | Controls whether the flow accepts more than one face in view. |
| `actionTimeoutMillis` | 2,000–30,000 ms, default 3,000 ms | Time budget per action. |
| `faceAcquisitionTimeoutMillis` | 1,000–60,000 ms, default 10,000 ms | Time to find the first usable face. |

RGB passive liveness uses an SDK threshold of 0.90. The liveness and verification `onResult` callback carries both acceptance and rejection. Check `outcome` first. Read similarity or liveness scores only when present. For standalone infrared liveness, call `await sdk.liveness().evaluateInfrared(frame, threshold)` with a real GRAY8 infrared frame, its face box, and a required 0–1 threshold calibrated on the target camera.

Wait for a successful `HiFaceResult<FaceRequest>` from the start call before feeding frames.

### Face library and search

Open an independent library with `await HiFaceSdk.openSearchDatabase(context)`. Use `saveFeature` or `saveFeatures` to add or update by Face ID. Save 1–1,000 records per batch. Use `search` to query by a face feature. `list` / `listRecent` returns metadata, and `listFeatures` pages through records with features. Close an explicitly opened library when finished. Await writes before closing the database.

| Database query parameter | Range and default | Purpose |
|---|---|---|
| Face ID, `group`, `tag` | 1–1024 UTF-8 bytes for Face ID, at most 1024 bytes per filter, no NUL | Group and tag match exactly. If both are set, both must match. Leave both unset to search the whole library. |
| `topK` | 1–100, default 1 | Maximum number of matches returned. |
| `threshold` | 0–1, default 0.80 | Minimum similarity for a database match. A query without a qualifying match returns an empty list. |

Use `search().startCameraSearch(config, listener)` for continuous search. It manages its own library connection.

| Continuous search parameter | Range and default | Purpose |
|---|---|---|
| `mode`, `needsLiveness` | Single-face with liveness by default; multi-face search has no liveness | Selects the largest face or analyzes multiple faces. |
| `threshold` | 0.75–0.85, default 0.80 | Minimum identity score in continuous search. |
| `searchIntervalMillis` | 0–3,000 ms, default 0 | Delay before the next attempt after a match. |
| `searchTimeoutMillis` | 1,000–3,000 ms, default 3,000 ms | Time budget from the first selected face. |
| `maxFacesPerFrame` | 1–5, default 3 | Face limit in multi-face mode. Single-face mode selects the largest face. |

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

Capture, liveness, verification, and continuous search share one camera flow slot. When switching or leaving, stop feeding frames, cancel the request or close the search, then close the SDK. `onError` reports technical failures. Inspect the outcome for business results.

The current model does not support face recognition for people under 12. Financial use is prohibited. Outdoor face search requires a camera with a wide dynamic range greater than 100 dB.
