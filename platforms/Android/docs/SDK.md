# HiFace Android SDK Integration Guide

## Installation

Beta expires at **2026-12-26 00:00 (UTC+08:00)**. Upgrade before expiry. [Updates](https://github.com/FaceSDKPro/).

| Requirement | Supported |
|---|---|
| Android | 6.0 / API 23 and later |
| ABI | `arm64-v8a`, `armeabi-v7a` |
| Entry point | Java `com.hiface.sdk.HiFaceSdk` |

Version `0.0.1` is a release candidate; use the published release record to confirm availability.

```kotlin
repositories {
    google()
    mavenCentral()
}
dependencies {
    implementation("io.github.facesdkpro:hiface-android:0.0.1")
}
android {
    androidResources { noCompress += "bphfm" }
}
```

Set `noCompress` in the host App module so the encrypted models can be read with mmap. Retain the AAR consumer R8 rules, [SDK license](../LICENSE), and [third-party notices](../LICENSE).

## Initialization and live detection

```java
HiFaceSdk sdk = HiFaceSdk.builder(this).lifecycleOwner(this).build();
FaceDetectionConfig config = FaceDetectionConfig.builder()
        .maxFaces(10).detailedLandmarks(true).build();
HiFaceResult<FaceDetectionResult> result = sdk.processFrame(frame, config);
```

Use a page-scoped instance and a single analysis thread. Models initialize asynchronously; `NOT_READY` means the current frame was not processed. Release it and keep sending the latest frames. Without a lifecycle owner, close the SDK explicitly.

Default detection returns one face with a box, confidence, and five landmarks. `maxFaces` accepts 1–10. Detailed landmarks and pose are optional and disabled by default. Capture, liveness, and verification prepare their own required models.

`Yuv420Frame` uses three direct Y/U/V buffers. Supply actual row and pixel strides, color range and matrix, rotation, and mirroring. Dimensions must be positive and even, with long side at most 1920 and short side at most 1080; rotation is 0/90/180/270 degrees. Buffers are borrowed only during `processFrame`. Use `KEEP_ONLY_LATEST` or equivalent backpressure. Coordinates are in the rotated, unmirrored image; the host maps preview crop, scaling, and front-camera mirroring.

## Static images, capture, liveness, and verification

```java
sdk.capture().extractFeature(bitmap, result -> {
    if (result.isSuccess()) {
        String feature = result.requireValue();
    } else {
        HiFaceError error = result.requireError();
    }
});
```

`fromBitmap` also returns an optional 333×333 aligned preview. Read `getAlignedFace()` once and release the returned Bitmap when finished. Static inputs select the largest face, without liveness or pose gates. A missing or small face returns `IMAGE_NO_FACE` or `IMAGE_FACE_TOO_SMALL`; usable faces need at least 100 pixels in both dimensions. Images are not resized; odd dimensions crop only the last row/column. Processed image dimensions must be even and within 2–4096.

Async calls copy pixels before returning. Each instance permits one running static request and four queued requests; additional requests return `BUSY`. For batch images, use one worker and call `extractFeatureBlocking` / `fromBitmapBlocking` serially. Blocking calls borrow the Bitmap until completion.

| Capability | Entry point |
|---|---|
| Guided capture | `capture().startCameraCapture(listener)` |
| Liveness | `liveness().startCameraLiveness(config, listener)` |
| HF1 comparison | `verification().compare(leftHF1, rightHF1)` |
| Static image comparison | `verification().compareBlocking(...)` on a worker |
| Camera verification | `verification().startCameraVerification(config, listener)` |

Camera flows need continuous frames. Capture results must be confirmed before saving. `FaceFlowListener.onResult` contains the business outcome, including rejection; `onError` reports technical failures. Check `isPassed()` / `getOutcome()` before using scores or images. Missing values mean the stage did not produce a result, not a score of zero.

Empty liveness actions still run seven-frame passive liveness with both models. Up to four actions, including repeats, are supported. Multiple faces are rejected by default. Capture, liveness, verification, and search share one camera flow slot.

```java
FaceVerificationConfig config = FaceVerificationConfig.builder()
        .referenceFeature(referenceFeature).threshold(0.80f)
        .enableSilentLiveness(true)
        .actions(Arrays.asList(FaceAction.BLINK, FaceAction.NOD_HEAD)).build();
sdk.verification().startCameraVerification(config, listener);
```

Cancel the `FaceRequest` and stop sending frames when leaving or switching camera features, then close the SDK. Cancellation suppresses stale callbacks while native work finishes without blocking page teardown. SDK callbacks are posted to the main thread; keep them short.

## Face library and continuous search

`HiFaceSdk.openSearchDatabase(context)` opens an independent database without loading models. The SDK manages its private path. Run database calls on a worker and close explicit handles yourself.

| API | Behavior |
|---|---|
| `saveFeature`, `saveFeatures` | Upsert by Face ID; atomic batches of 1–1000 |
| `contains`, `get` | ID existence; full original HF1 feature |
| `list`, `listRecent` | Metadata pagination without features |
| `listFeatures` | Full feature pagination for export |
| `updateMetadata` | Update group/tag; null preserves, empty clears |
| `search` | Exact Top-K with group/tag filters |
| `releaseMemory`, `close` | Release gallery cache; close the handle |

HF1 is a 604-character Q7/Base64URL representation, **not encryption**. SQLite stores the original 450-byte Q7 payload and returns complete HF1 strings without re-quantization. Validate server features with `FaceFeatureFormat.FEATURE_SPACE_ID` (`hiface-feature-new-v1`) and `FaceSearchFeatureEntry`. The host owns consent, access control, encryption, retention, deletion, and backup policy.

`search().startCameraSearch(config, listener)` opens and warms its own database connection. Continue sending frames through `processFrame`. The session supports `pause()`, `resume()`, `setConfig()`, and `close()`. Pausing releases the selected gallery cache; resume warms it again while reusing models.

1:N can run passive liveness; M:N does not. Search does not run 468-point/pose processing. Match `frameId` across detection, scoring, and completion. An unscored face is not a negative match. Use the final `endReason`; `SPOOF_DETECTED` rejects the result even if an identity passes the similarity threshold. Similarity is not identity probability.

After 10 seconds without faces, analysis targets a 200 ms interval and resumes normal processing when a face returns. Skipped frames return `NOT_READY`. Search interval controls the wait after a successful match, not camera FPS.

Handle errors by `HiFaceErrorCode`.
