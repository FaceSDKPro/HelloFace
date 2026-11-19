# HiFace iOS Demo Guide

English | [简体中文](DEMO.zh-CN.md)

See the [SDK API](SDK/API.md) for APIs and integration requirements.

## Sample code

| Area | Source |
|---|---|
| Camera | [CameraPipeline](HiFaceDemo/Camera/CameraPipeline.swift) |
| Camera flows | [CameraDemoModel](HiFaceDemo/Camera/CameraDemoModel.swift) |
| Face library | [SearchLibraryView](HiFaceDemo/Search/SearchLibraryView.swift) |

## Demo data

`features_10000.json` provides 10,000 offline features; `images_1000.json` provides 1,000 online image URLs. They are excluded from `HiFace.framework` and XCFramework/SPM packages.

Back during import offers continue or stop. Stop saves completed data and reports saved/failed counts. Failed images are skipped; database errors keep previously saved data.

1:1 references use Keychain. SDK SQLite is not encrypted; HF1 is feature encoding. Replace sample data and implement data protection/deletion in your App.

## Flow result images

`FaceFlowResult` retains the 333×333 aligned face and adds a JPEG of the complete terminal frame. The frame keeps its aspect ratio, is never enlarged, and has both dimensions at most 720 pixels. JPEG quality is fixed at 95 (high-quality lossy compression). Images are rotated and unmirrored. Both images come from the same terminal frame; there is no image candidate pool. Similarity and seven-frame liveness scoring retain their existing rules, so the highest similarity may come from an earlier frame.

Business outcomes, including no face, multiple faces, face loss, action timeout, and mismatch, also return a frame when possible. The aligned image is absent when no face can be cropped; images are absent when no valid frame is available or image generation fails. Technical errors still use `onError`; cancellation and close suppress results. Image presence does not imply acceptance.

Images are generated once at completion, kept in memory, and never written to a disk cache or retained as a history. Delivered results own their data after SDK cleanup. Release results and display images when finished.

Use `frameJPEG`, `frameWidth`, and `frameHeight`; keep using `alignedFace` for the crop. Display the JPEG with `UIImage(data:)`.
