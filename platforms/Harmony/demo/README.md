# HiFace HarmonyOS SDK and Demo Guide

English | [简体中文](README.zh-CN.md)

The development Demo uses bundle ID `com.hiface.sdk.public`.

<!-- SDK-USER-GUIDE:BEGIN -->
## Installation

Beta expires at **2026-12-26 00:00 (UTC+08:00)**. Upgrade before expiry. [Updates](https://github.com/FaceSDKPro/).

| Requirement | Supported |
|---|---|
| HarmonyOS | API 20 and later |
| ABI | `arm64-v8a` |
| Entry point | ArkTS `HiFaceSdk` |

For direct delivery, copy the versioned HAR into the application and configure the module's `oh-package.json5`:

```json5
{ "dependencies": { "hiface": "file:./libs/hiface-0.0.1.har" } }
```

After the same version is approved in the OpenHarmony package registry, use `ohpm install hiface@0.0.1`. Direct and registry delivery must use the same version and HAR SHA-256. Never replace an artifact already delivered under a version number. Sign the host HAP/APP with your own credentials; SDK HARs do not include Demo signing files or private keys.

## Initialization and ownership

```typescript
import { common } from '@kit.AbilityKit';
import { HiFaceSdk, HiFaceResult } from 'hiface';

async function createSdk(context: common.UIAbilityContext): Promise<HiFaceSdk> {
  const sdk: HiFaceSdk = HiFaceSdk.create(context);
  const ready: HiFaceResult<boolean> = await sdk.whenReady();
  if (ready.isFailure()) {
    const error = ready.requireError();
    sdk.close();
    throw new Error(`HiFace initialization failed: ${error.message}`);
  }
  return sdk;
}
```

Check `isSuccess()` / `isFailure()` before `requireValue()` / `requireError()`. Invalid constructor arguments throw `Error`. Use stable error codes for decisions; SDK message text remains internal diagnostics. Keep camera/platform failures separate from SDK business outcomes.

Reuse an instance per Ability or business container. Pass the SDK to ArkUI children through a normal field, optionally `@Require`, **not `@Prop`**. Deep copying SDK objects corrupts their Promise state. Do not copy SDK/request/database handles into observed UI state.

## Public capabilities

| Capability | Entry point |
|---|---|
| Detection | `processFrame`, `processRgba` |
| Frame backpressure | `createRealtimeProcessor` |
| Capture and extraction | `capture()` |
| Action/passive liveness | `liveness()` |
| HF1, static, and camera 1:1 verification | `verification()` |
| Continuous 1:N/M:N search | `search()` |
| Independent face library | `HiFaceSdk.openSearchDatabase(context)` |

Import only public exports from `hiface` / `Index.ets`. Internal ArkTS/N-API/native fields are outside the public compatibility contract. Use `whenReady()` for readiness; `getApiVersion()` is ABI diagnostics only.

```typescript
const feature: HiFaceResult<string> = await sdk.capture().extractFeature(image);
const capture = await sdk.capture().fromRgba(image);
const similarity: HiFaceResult<number> = sdk.verification().compare(leftHF1, rightHF1);
```

Normalize orientation before constructing `RgbaImage`. Static inputs select the largest face; `fromRgba` also returns a 333×333 aligned preview. Async calls snapshot pixels immediately. Each instance queues one running static request and four waiting requests; process batch images serially.

HF1 is a 604-character Q7/Base64URL representation, **not encryption**. Detection exposes boxes, confidence, five landmarks, and optional pose/468-point contours. Internal EAR/MAR and action measurements are not public identity decisions.

## Frames and camera flows

Y/U/V frame buffers are borrowed until the processing Promise completes; do not release or overwrite them earlier. Supply actual strides, color range/matrix, rotation, and mirroring. Analysis dimensions must be positive and even, with long side at most 1920 and short side at most 1080; rotation is 0/90/180/270 degrees.

Use one `FaceRealtimeProcessor` per camera pipeline. `tryProcessFrame()` returns `undefined` when busy; release the new frame instead of building an unbounded queue. `NOT_READY` also covers initialization and idle skipped frames. After 10 seconds without faces, analysis targets a 200 ms interval, then resumes normal processing when faces return.

Coordinates are in the rotated, unmirrored result image. Apply preview scaling, crop, and front-camera mirroring yourself. `frameId` links detection/scoring/completion from one sample; it is not a tracking identifier across frames.

Capture, liveness, verification, and search share a camera flow slot:

1. Create the listener and start the desired `startCamera...` flow.
2. Keep its returned `FaceRequest` / `FaceSearchSession`.
3. Keep sending latest frames through the same realtime processor.
4. Cancel/close the flow before switching cameras/features or tearing down the page; then close the SDK.

`onResult` contains a business outcome; `onError` reports technical failure. Search must check final `endReason`, and `SPOOF_DETECTED` rejects a result even if similarity passes. Empty liveness actions still run seven-frame passive liveness with both models. Use public configuration defaults and limits.

Search automatically opens and warms its database. Pause retains the slot, models, and connection while releasing scope cache; resume warms the scope before processing new frames. Closing releases the slot and connection. New starts wait for earlier native start/stop work. If native stop fails, close and recreate the SDK. `close()` suppresses stale callbacks immediately; keep borrowed frame buffers alive until their Promise ends.

## Face library

`openSearchDatabase(context)` does not load models. Explicit database handles are independent and must be closed by their owner. The SDK manages its private database path.

| API | Behavior |
|---|---|
| `saveFeature`, `saveFeatures` | Upsert by Face ID; atomic batches of 1–1000 |
| `contains`, `get` | ID existence; full original HF1 |
| `list`, `listRecent` | Metadata-only pagination |
| `listFeatures` | Full feature pagination for export |
| `updateMetadata` | Update group/tag/time without changing features; undefined preserves, empty clears |
| `search` | Exact Top-K with scope filters |
| `releaseMemory`, `close` | Release gallery cache; close the handle |

SQLite stores the original 450-byte Q7 payload and returns complete HF1 without re-quantization. Validate server features using `FaceFeatureFormat.FEATURE_SPACE_ID` (`hiface-feature-new-v1`) and `FaceSearchFeatureEntry`. Pagination offsets support `0..2147483647`, limits `1..1000`. Thresholds normalize to Core float32 precision.

`close()` rejects new operations immediately and releases SQLite/cache after started work; queued work returns `CLOSED`. Await successful saving before closing. Search sessions own their own connections.

The SDK does not encrypt SQLite. The host owns biometric consent, access control, encryption, retention, deletion, and backup policies. Retain the SDK/model commercial license, `CHANGELOG.md`, and `THIRD_PARTY_NOTICES.txt`. Commercial use requires written authorization; deliver version identifiers and `SHA256SUMS` with release artifacts.
<!-- SDK-USER-GUIDE:END -->

## Run the Demo

Open `platforms/harmony` in DevEco Studio 26. `demo` is the App; `sdk` builds the `hiface` HAR. Configure your bundle name and HAP signing, then run `demo` on an API 20+ arm64 phone. Unsigned HAPs cannot install on phones. The home page provides seven capabilities and device version/model details.

| Area | Source |
|---|---|
| Navigation | [Index](src/main/ets/pages/Index.ets) |
| Camera | [CameraPreviewController](src/main/ets/camera/CameraPreviewController.ets) |
| Camera flows | [RealtimeCameraDemo](src/main/ets/pages/RealtimeCameraDemo.ets) |
| Face library | [FaceSearchLibraryDemo](src/main/ets/search/FaceSearchLibraryDemo.ets) |

Copy CameraKit YUV data before releasing its Image; retain buffers until processing completes. Use one realtime processor and discard busy frames. Map rotated/unmirrored result coordinates to the preview. Pass SDK handles through normal fields or `@Require`, never `@Prop`.

## Languages and imports

The Demo uses Simplified Chinese in system regions CN/HK/MO/TW and English elsewhere. Restart after changing the region. SDK diagnostics stay in Chinese; the Demo translates errors by code. Native permission dialogs follow system settings.

`features_10000.json` provides 10,000 offline HF1 features; `images_1000.json` lists 1,000 online images. Both are Demo data. These files are excluded from the `hiface` HAR. Images download up to five at a time, extract serially and save every 100 successes; feature imports save every 1000 entries.

Progress shows processed and saved counts. Back during import offers **Continue import** or **Stop and exit**. Stop finishes the current operation, saves the completed tail batch and reports saved/failed counts. Failed images are skipped; database errors keep earlier saved batches. Wait for import cleanup before closing SDK/database resources.

## Data and troubleshooting

Replace sample identities, features and URLs before production. HF1 is encoding; SDK SQLite is not encrypted. Protect biometric data and implement retention/deletion in your App. 1:1 references use a Demo-owned HUKS-encrypted file.

For model errors, retain the SDK model bundle. For camera-size errors, select a supported even size within 1920×1080. Test camera permission recovery, rotation, foreground/background changes and all flows on target phones.

Edit the bilingual Demo string resources.
