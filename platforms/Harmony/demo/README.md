# HiFace HarmonyOS Demo Guide

English | [简体中文](README.zh-CN.md)

See the [SDK guide](../SDK.md) for APIs and integration requirements.

## Sample code

| Area | Source |
|---|---|
| Navigation | [Index](src/main/ets/pages/Index.ets) |
| Camera | [CameraPreviewController](src/main/ets/camera/CameraPreviewController.ets) |
| Camera flows | [RealtimeCameraDemo](src/main/ets/pages/RealtimeCameraDemo.ets) |
| Face library | [FaceSearchLibraryDemo](src/main/ets/search/FaceSearchLibraryDemo.ets) |

## Demo data

`features_10000.json` provides 10,000 offline features; `images_1000.json` provides 1,000 online image URLs. They are excluded from the `hiface` HAR.

Back during import offers continue or stop. Stop saves completed data and reports saved/failed counts. Failed images are skipped; database errors keep previously saved data.

1:1 references use a HUKS-encrypted file. SDK SQLite is not encrypted; HF1 is feature encoding. Replace sample data and implement data protection/deletion in your App.

## Flow result images

`FaceFlowResult` retains the 333×333 aligned face and adds a JPEG of the complete terminal frame. The frame keeps its aspect ratio, is never enlarged, and has both dimensions at most 720 pixels. JPEG quality is fixed at 95 (high-quality lossy compression). Images are rotated and unmirrored. Both images come from the same terminal frame; there is no image candidate pool. Similarity and seven-frame liveness scoring retain their existing rules, so the highest similarity may come from an earlier frame.

Business outcomes, including no face, multiple faces, face loss, action timeout, and mismatch, also return a frame when possible. The aligned image is absent when no face can be cropped; images are absent when no valid frame is available or image generation fails. Technical errors still use `onError`; cancellation and close suppress results. Image presence does not imply acceptance.

Images are generated once at completion, kept in memory, and never written to a disk cache or retained as a history. Delivered results own their data after SDK cleanup. Release results and display images when finished.

Use `frameJpeg`, `frameWidth`, and `frameHeight`; keep using `alignedRgba` and `alignedSide` for the crop. Decode the JPEG with ImageKit and release system image resources after use.
