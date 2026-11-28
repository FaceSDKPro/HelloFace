**English** | [简体中文](SDK.zh-CN.md)

# HiFace Android SDK API Guide

## Quick start

Requires Android 6.0 / API 23 or later and an ARM64 or ARMv7 device.

Version `0.8.17` is used below. Add the SDK's bundled `maven-repository` to your project's Gradle repositories and keep `google()` and `mavenCentral()` for dependencies. If you use Maven Central for HiFace, confirm that the same version is published there. In the app module:

```kotlin
dependencies {
    implementation("io.github.facesdkpro:hiface-android:0.8.17")
}
android {
    androidResources { noCompress += "bphfm" }
}
```

Keep the [SDK license](../LICENSE) and the AAR's R8 consumer rules. In a Java app, replace the launcher Activity with this class and match its package name to your manifest. Run on a supported device. The screen should show `IMAGE_NO_FACE` for the generated blank image, without a camera permission.

```java
package com.example.hiface;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.Bundle;
import android.widget.TextView;
import com.hiface.sdk.HiFaceSdk;

public final class MainActivity extends Activity {
    private HiFaceSdk sdk;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        TextView output = new TextView(this);
        setContentView(output);

        sdk = HiFaceSdk.builder(this).build();
        Bitmap image = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888);
        image.eraseColor(Color.BLACK);
        sdk.capture().extractFeature(image, result -> output.setText(result.isSuccess()
                ? "Feature extracted"
                : result.requireError().getCode().name()));
        image.recycle();
    }

    @Override
    protected void onDestroy() {
        sdk.close();
        super.onDestroy();
    }
}
```

Creation starts initialization in the background. Static-image requests wait for readiness; if camera input returns `NOT_READY`, release that frame and submit a fresh one. The SDK neither opens a camera nor requests the host app's camera permission.

## API reference

```text
HiFaceSdk
├── builder(Context)
├── processFrame(Yuv420Frame)
├── processFrame(Yuv420Frame, FaceDetectionConfig)
├── processFrame(RgbIrFrame)
├── capture()
├── liveness()
├── verification()
├── search()
├── openSearchDatabase(Context)
└── close()
```

### Face detection

Call `sdk.processFrame(frame, config)`. A successful result contains face boxes, confidence, and landmarks. No faces returns an empty list. Coordinates refer to the rotated, unmirrored image.

| `FaceDetectionConfig` parameter | Range and default | Purpose |
|---|---|---|
| `maxFaces` | 1–10, default 1 | Limits the number of returned faces. |
| `detailedLandmarks` | Boolean, off by default | Includes detailed contours and head angles when enabled. |

Use even camera frame dimensions, at most 1920 on the long side and 1080 on the short side. Rotation is 0°, 90°, 180°, or 270°.
Provide `Yuv420Frame` with actual plane strides, color range/matrix, and rotation. The synchronous call borrows the frame until return. During search, read identity and scores from the search listener.

`Yuv420Frame` requires direct `ByteBuffer` objects for all three planes, with actual camera strides. Choose `VIDEO` or `FULL` for `range` and `BT601` or `BT709` for `matrix` from capture metadata. Serialize frame submission; the app handles preview mirroring. Even with detailed landmarks enabled, check `getMesh()` and `getHeadPose()` separately for null; head angles are in degrees.

### Face enrollment and photo capture

| API | Result |
|---|---|
| `capture().extractFeature(bitmap, callback)` | Extracts a feature for the largest face. Returns `IMAGE_NO_FACE` if no face is found, or `IMAGE_FACE_TOO_SMALL` if either face dimension is under 100 pixels. |
| `capture().fromBitmap(bitmap, callback)` | Returns the feature from `getFeature()` and an aligned preview from `getAlignedFace()`. Save the feature after the user confirms enrollment. |
| `capture().facesFromBitmap(bitmap, callback)` | Returns positions and individual capture results for up to 10 faces. No faces returns an empty list; a small face only affects its own entry. |
| `capture().startCameraCapture(listener)` | Guides the user through camera enrollment and delivers the result to the callback. |

Apply photo orientation first. Each SDK has one active static-image job and room for four waiting jobs. Submit batch photos one at a time. Photo APIs require no camera permission and perform no liveness check.

Use `extractFeature` when no preview is needed. For bulk import, call `extractFeatureBlocking` sequentially on a worker and retain the input until return. Each `getAlignedFace()` allocates a separate `Bitmap`; release it when unused and avoid repeated reads. Strict single-face enrollment requires exactly one `facesFromBitmap` entry with successful `getCapture()`. The largest-face APIs do not reject multi-person photos.

```java
FaceRequest request = sdk.capture().startCameraCapture(new FaceCaptureListener() {
    @Override
    public void onProgress(@NonNull FaceFlowProgress progress) {
        // Update the instructions.
    }
    @Override
    public void onResult(@NonNull FaceCaptureResult capture) {
        // Save capture.getFeature() after confirmation.
    }
    @Override
    public void onError(@NonNull HiFaceError error) {
        // Handle the SDK error.
    }
});
```

### Liveness and 1:1 verification

Start `liveness().startCameraLiveness(config, listener)` or `verification().startCameraVerification(config, listener)`, then keep sending camera frames. If you already have both face features, `verification().compare(left, right)` returns a similarity score from 0 to 1. It measures how close the features are.

| Parameter | Range and default | Purpose |
|---|---|---|
| `referenceFeature` | Required for 1:1 verification | The enrolled face feature. |
| `threshold` | Recommended 0.75–0.85; default 0.80 | Minimum 1:1 similarity. A completed comparison below this threshold returns a mismatch. |
| `actions` | 0–4 actions, empty by default | An empty action list still runs passive liveness in the liveness flow. |
| `enableSilentLiveness` | Boolean, off by default for 1:1 verification | Also requires passive liveness when enabled. |
| `allowMultipleFaces` | Boolean, off by default | Controls whether the flow accepts more than one face in view. |
| `actionTimeoutMillis` | 2,000–30,000 ms, default 3,000 ms | Time budget per action. |
| `faceAcquisitionTimeoutMillis` | 1,000–60,000 ms, default 10,000 ms | Time to find the first usable face. |

`actions` run in list order and may repeat: `SHAKE_HEAD`, `NOD_HEAD`, `BLINK` and `MOUTH_OPEN`. With no actions and `enableSilentLiveness=false`, 1:1 verification checks identity without liveness.

The recommended similarity range is 0.75–0.85, with 0.80 as the default configuration value. The 1:1 and feature-query APIs accept 0–1; camera search accepts only 0.75–0.85.

The recommended RGB/IR liveness threshold is 0.80–0.99, starting at 0.90. RGB passive liveness currently uses a fixed 0.90 with no public threshold setting. IR requires an explicit threshold and has no implicit default. The liveness and verification `onResult` callback carries both acceptance and rejection. Check `getOutcome()` first. Read similarity or liveness scores only when present. For standalone infrared liveness, call `liveness().evaluateInfrared(frame, threshold)` with a real GRAY8 infrared frame, its face box, and a required threshold calibrated on the target camera (recommended 0.80–0.99, starting at 0.90; the API accepts values greater than 0 and at most 1).

Only `FaceFlowResult.isPassed()` indicates acceptance. `getSimilarity()` and `getLivenessScore()` are null when unavailable, not zero. Both `getAlignedFace()` and `getFrameJpeg()` are optional; an image does not indicate acceptance. `getFrameWidth()` and `getFrameHeight()` are JPEG pixel dimensions, or zero without a JPEG. Map face boxes from the original detection dimensions.

```java
FaceFlowListener listener = new FaceFlowListener() {
    @Override
    public void onProgress(@NonNull FaceFlowProgress progress) {
        // Update the instructions.
    }
    @Override
    public void onResult(@NonNull FaceFlowResult result) {
        // Check result.getOutcome() before reading scores.
    }
    @Override
    public void onError(@NonNull HiFaceError error) {
        // Handle the SDK error.
    }
};
sdk.liveness().startCameraLiveness(FaceLivenessConfig.builder().build(), listener);
```

### Face library and search

Open an independent library with `HiFaceSdk.openSearchDatabase(context)`. Use `saveFeature` or `saveFeatures` to add or update by Face ID. Save 1–1,000 records per batch. Use `search(feature, config)` to query by a face feature. `list` / `listRecent` returns metadata, and `listFeatures` pages through records with features. Close an explicitly opened library when finished. Use a worker for database calls.

A library holds at most 50,000 records. Each `saveFeatures` batch succeeds or rolls back as a whole; the last duplicate Face ID in a batch wins. `contains` reports existence, `get` returns `NOT_FOUND` if absent, and the successful `delete` value reports whether a record was removed.

Pagination uses `offset` starting at 0 and `limit` from 1–1,000. `list` and `listFeatures` sort by Face ID; `listRecent` sorts newest first. `updateTimeMillis` uses Unix milliseconds: 0 selects the current time and negative values are invalid. For `updateMetadata`, null preserves a group or tag, while empty clears it; supply at least one.

**Face records and filters**

| Parameter | Range and default | Purpose |
|---|---|---|
| Face ID | Required; 1–1024 UTF-8 bytes; no NUL; no default | Application-assigned record ID. Saving the same ID updates that record. It is not a group or tag filter. |
| `group` | Optional; at most 1024 bytes (UTF-8); no NUL; unrestricted by default | The record's group. Queries match it exactly; `null` or empty means any group. |
| `tag` | Optional; at most 1024 bytes (UTF-8); no NUL; unrestricted by default | An application-defined label. Queries match it exactly; `null` or empty means any tag. |

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
| `needLiveness` | `true` / `false`; default `true` in single-face mode and `false` in multi-face mode | Enables RGB passive liveness. Multi-face mode rejects `true`. Paired IR search disables RGB liveness. |
| `threshold` | 0.75–0.85 inclusive, default 0.80 | Camera-search identity threshold. Similarity must be at least this value; required liveness must also pass. |
| `searchIntervalMillis` | 0–3,000 ms, default 0 | Delay before the next attempt after a match. |
| `searchTimeoutMillis` | 1,000–3,000 ms, default 3,000 ms | Time budget from the first selected face. |
| `maxFacesPerFrame` | 1–5, default 3 | Face limit in multi-face mode. Single-face mode selects the largest face. |

`startCameraSearch` immediately returns a `FaceSearchSession`; keep feeding fresh frames during preparation. `pause()` retains the session and camera-flow slot; `resume()` resumes it, and `setConfig()` replaces configuration and invalidates old results. Close the session before capture or verification. Use `onFrame` for display and `onResult` for business decisions. After an open/preparation error, fix the cause and call `resume()`; a session rejected because the SDK was closed or a flow conflicted must be recreated.

Check `getEndReason()` first. A `SPOOF_DETECTED` outcome rejects a match even if similarity passes. `getFrameId()` identifies one camera sample. `getFrameJpeg()` is an optional full scene from the terminal sample. Use the original frame size to map its face boxes.

### RGB/IR camera search

Use single-face mode. Setting `infraredLiveness` disables default RGB liveness; explicitly enabling `needLiveness(true)` conflicts and is rejected by `build()`. Supply `calibratedRgbToIr` from calibration of the actual camera pair; do not substitute an identity matrix for different cameras.

```java
InfraredSearchConfig infrared = new InfraredSearchConfig(
        0.90f, calibratedRgbToIr, 0.50f, 20, 50, 200);
FaceSearchSessionConfig config = FaceSearchSessionConfig.builder()
        .mode(FaceSearchMode.SINGLE_FACE)
        .infraredLiveness(infrared)
        .threshold(0.80f)
        .build();
// Pass config to sdk.search().startCameraSearch(config, listener).
// Feed each paired RGB/IR sample with sdk.processFrame(pair).
```

All following parameters are required and have no default.

| Parameter | Range | Purpose |
|---|---|---|
| `realThreshold` | Required; recommended 0.80–0.99, starting at 0.90; accepts (0,1] | IR liveness threshold calibrated on the device. |
| `normalizedRgbToIr` | 9 finite values | Nonsingular row-major 3×3 matrix mapping upright, unmirrored RGB to normalized IR coordinates. |
| `minimumFaceOverlap` | Greater than 0 and at most 1 | Minimum intersection area divided by union area of the mapped RGB and IR face boxes. |
| `minimumFacePixels` | 10–4096 px | Minimum IR face width and height. |
| `maxPairSkewMillis` | 1–200 ms | Maximum difference between the two frame timestamps. |
| `maxFrameAgeMillis` | `maxPairSkewMillis` through 1,000 ms | Maximum frame age when admitting the pair. |

Use the same `SystemClock.elapsedRealtime()` millisecond domain for both timestamps in `RgbIrFrame`. Use a new positive `sourceId` on each camera opening and strictly increasing pair and per-camera sequence IDs. IR requires a real upright, unmirrored GRAY8 direct buffer. Keep both pixel buffers alive until `processFrame(pair)` returns. Missing IR or liveness rejection must reject the match.

Store returned features as-is. When changing to an incompatible model, re-extract features from the original photos and reimport them. The host app handles consent, protection, and deletion of photos and features.

Use `FaceSearchConfig.builder().build()` for the default database query configuration.

## Errors and cleanup

Check `HiFaceResult.isSuccess()` before reading `requireValue()` or `requireError().getCode()`. Out-of-range builder values throw `IllegalArgumentException`; building 1:1 configuration without `referenceFeature` throws `IllegalStateException`. SDK callbacks arrive asynchronously on the main thread. Reuse one SDK per page and call `close()` on teardown, or call `builder(...).lifecycleOwner(owner)` on the main thread for automatic closing.

Use `HiFaceErrorUi.isAccessError(error.getCode())` to identify access errors. `HiFaceErrorUi.messageFor(context, error)` returns localized guidance followed by the stable error number, for example `(Error code 1605)` for expiration. Use `error.getCode()` for the specific cause. The Demo’s `DemoErrorUi.accessMessage(code)` returns the numbered string resource for an access error and `0` for other errors.

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

Camera frame buffers are borrowed until `processFrame` returns; release them to the camera afterward. Asynchronous static capture snapshots the image before returning. Cancellation suppresses callbacks that have not started and does not synthesize a terminal result; a callback already running may finish, so also guard the current page or request ID. Build on the main thread when binding a `lifecycleOwner`, and call `close()` on the main thread; a view-scoped Fragment should bind its View Lifecycle.

The current model does not support face recognition for people under 12. Financial use is prohibited. Outdoor face search requires a camera with a wide dynamic range greater than 100 dB.
