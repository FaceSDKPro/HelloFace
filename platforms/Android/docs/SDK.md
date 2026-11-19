# HiFace Android SDK API Guide

## Quick start

Requires Android 6.0 / API 23 or later and an ARM64 or ARMv7 device.

Version `0.8.13` is used below. Add the SDK's bundled `maven-repository` to your project's Gradle repositories and keep `google()` and `mavenCentral()` for dependencies. If you use Maven Central for HiFace, confirm that the same version is published there. In the app module:

```kotlin
dependencies {
    implementation("io.github.facesdkpro:hiface-android:0.8.13")
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

### Face enrollment and photo capture

| API | Result |
|---|---|
| `capture().extractFeature(bitmap, callback)` | Extracts a feature for the largest face. Returns `IMAGE_NO_FACE` if no face is found, or `IMAGE_FACE_TOO_SMALL` if either face dimension is under 100 pixels. |
| `capture().fromBitmap(bitmap, callback)` | Returns `getFeature()` and an optional aligned preview, `getAlignedFace()`. Save the feature after the user confirms enrollment. |
| `capture().facesFromBitmap(bitmap, callback)` | Returns positions and individual capture results for up to 10 faces. No faces returns an empty list; a small face only affects its own entry. |
| `capture().startCameraCapture(listener)` | Guides the user through camera enrollment and delivers the result to the callback. |

Apply photo orientation first. Each SDK has one active static-image job and room for four waiting jobs. Submit batch photos one at a time. Photo APIs require no camera permission and perform no liveness check.

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
| `threshold` | 0–1, default 0.80 | Minimum 1:1 similarity. A completed comparison below this threshold returns a mismatch. |
| `actions` | 0–4 actions, empty by default | An empty action list still runs passive liveness in the liveness flow. |
| `enableSilentLiveness` | Boolean, off by default for 1:1 verification | Also requires passive liveness when enabled. |
| `allowMultipleFaces` | Boolean, off by default | Controls whether the flow accepts more than one face in view. |
| `actionTimeoutMillis` | 2,000–30,000 ms, default 3,000 ms | Time budget per action. |
| `faceAcquisitionTimeoutMillis` | 1,000–60,000 ms, default 10,000 ms | Time to find the first usable face. |

RGB passive liveness uses an SDK threshold of 0.90. The liveness and verification `onResult` callback carries both acceptance and rejection. Check `getOutcome()` first. Read similarity or liveness scores only when present. For standalone infrared liveness, call `liveness().evaluateInfrared(frame, threshold)` with a real GRAY8 infrared frame, its face box, and a required 0–1 threshold calibrated on the target camera.

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

| Database query parameter | Range and default | Purpose |
|---|---|---|
| Face ID, `group`, `tag` | 1–1024 UTF-8 bytes for Face ID, at most 1024 bytes per filter, no NUL | Group and tag match exactly. If both are set, both must match. Leave both unset to search the whole library. |
| `topK` | 1–100, default 1 | Maximum number of matches returned. |
| `threshold` | 0–1, default 0.80 | Minimum similarity for a database match. A query without a qualifying match returns an empty list. |

Use `search().startCameraSearch(config, listener)` for continuous search. It manages its own library connection.

| Continuous search parameter | Range and default | Purpose |
|---|---|---|
| `mode`, `needLiveness` | Single-face with liveness by default; multi-face search has no liveness | Selects the largest face or analyzes multiple faces. |
| `threshold` | 0.75–0.85, default 0.80 | Minimum identity score in continuous search. |
| `searchIntervalMillis` | 0–3,000 ms, default 0 | Delay before the next attempt after a match. |
| `searchTimeoutMillis` | 1,000–3,000 ms, default 3,000 ms | Time budget from the first selected face. |
| `maxFacesPerFrame` | 1–5, default 3 | Face limit in multi-face mode. Single-face mode selects the largest face. |

Check `getEndReason()` first. A `SPOOF_DETECTED` outcome rejects a match even if similarity passes. `getFrameId()` identifies one camera sample. `getFrameJpeg()` is an optional full scene from the terminal sample. Use the original frame size to map its face boxes.

Store returned features as-is. When changing to an incompatible model, re-extract features from the original photos and reimport them. The host app handles consent, protection, and deletion of photos and features.

Use `FaceSearchConfig.builder().build()` for the default database query configuration.

## Errors and cleanup

Check `HiFaceResult.isSuccess()` before reading `requireValue()` or `requireError().getCode()`. Invalid builder arguments throw `IllegalArgumentException`. SDK callbacks arrive asynchronously on the main thread. Reuse one SDK per page and call `close()` on teardown, or call `builder(...).lifecycleOwner(owner)` on the main thread for automatic closing.

| Condition | What to do |
|---|---|
| `NOT_READY` | While models initialize, the runtime is busy, or a camera frame is skipped, drop the old frame and keep submitting the latest one. |
| `BUSY` | Wait for static jobs to finish or end the current camera flow. |
| `INVALID_ARGUMENT` | Check the parameters, frame format, and buffers. |
| `LICENSE_EXPIRED` | Check the validity dates and contact SDK support if needed. |
| `CLOSED` | Stop sending work to this instance. |

Capture, liveness, verification, and continuous search share one camera flow slot. When switching or leaving, stop feeding frames, cancel the request or close the search, then close the SDK. `onError` reports technical failures. Inspect the outcome for business results.

The current model does not support face recognition for people under 12. Financial use is prohibited. Outdoor face search requires a camera with a wide dynamic range greater than 100 dB.
