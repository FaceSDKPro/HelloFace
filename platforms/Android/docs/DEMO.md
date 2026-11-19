# HiFace Android Demo Guide

English | [简体中文](DEMO.zh-CN.md)

See the [SDK API](SDK.md) for integration requirements and API details.

## 1:1 reference enrollment

On Face Recognition, choose ordered action challenges and the 1:1 passive-liveness switch before opening the camera. Swipe the enrolled reference portraits and tap a Face ID to verify. Independent liveness always performs passive checks with optional actions. Verification and liveness return their result to this page without a result dialog. Confirmed captures save a private portrait; older feature-only references use a placeholder. Choose **Add from Album** to open the system picker directly or **Use Camera** to start guided capture. A photo must contain exactly one detected face. Both paths show the same confirmation before saving the reference under the entered Face ID.

[FaceRecognitionActivity](../demo/src/main/java/com/hiface/sdk/demo/recognition/FaceRecognitionActivity.java) opens the picker and invokes SDK photo capture. [CameraFlowActivity](../demo/src/main/java/com/hiface/sdk/demo/camera/CameraFlowActivity.java) checks camera readiness and cancels active requests on stop. Both reference capture paths use [ReferenceConfirmation](../demo/src/main/java/com/hiface/sdk/demo/verification/ReferenceConfirmation.java) to save the feature and attempt to store its aligned portrait.

## Sample code

| Area | Source |
|---|---|
| Camera | [CameraPreviewFragment](../demo/src/main/java/com/hiface/sdk/demo/camera/CameraPreviewFragment.java) |
| Search | [FaceSearchActivity](../demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchActivity.java) |
| Face library | [FaceSearchLibraryActivity](../demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchLibraryActivity.java) |

## Demo data

`features_10000.json` provides 10,000 offline features; `images_1000.json` provides 1,000 online image URLs. They are not included in SDK AARs.

Back during import offers continue or stop. Stop saves completed data and reports saved/failed counts. Failed images are skipped; database errors keep previously saved data.

1:1 references use MMKV. Replace the fixed Demo encryption key in your App. SDK SQLite is not encrypted; HF1 is feature encoding. Replace sample data and implement data protection/deletion in your App.

## Flow result images

`FaceFlowResult` retains the 333×333 aligned face and adds a JPEG of the complete terminal frame. The frame keeps its aspect ratio, is never enlarged, and has both dimensions at most 720 pixels. JPEG quality is fixed at 95 (high-quality lossy compression). Images are rotated and unmirrored. Both images come from the same terminal frame; there is no image candidate pool. Similarity and seven-frame liveness scoring retain their existing rules, so the highest similarity may come from an earlier frame.

Business outcomes, including no face, multiple faces, face loss, action timeout, and mismatch, also return a frame when possible. The aligned image is absent when no face can be cropped; images are absent when no valid frame is available or image generation fails. Technical errors still use `onError`; cancellation and close suppress results. Image presence does not imply acceptance.

Images are generated once at completion, kept in memory, and never written to a disk cache or retained as a history. Delivered results own their data after SDK cleanup. Release results and display images when finished.

Use `getFrameJpeg()`, `getFrameWidth()`, and `getFrameHeight()`; keep using `getAlignedFace()` for the crop. Each JPEG getter call returns an independent byte copy.
