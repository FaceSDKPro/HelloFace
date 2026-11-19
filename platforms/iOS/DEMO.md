# HiFace iOS Demo Guide

English | [简体中文](DEMO.zh-CN.md)

See the [SDK API](SDK/API.md) for integration requirements and API details.

## 1:1 reference enrollment

Face Recognition owns the ordered action choices and the 1:1 passive-liveness switch. Swipe or scroll the enrolled portraits and select a Face ID to start verification directly. Independent liveness always performs passive checks, with optional actions. Both camera flows return their outcomes to this page without a result dialog. Confirmed captures save a private portrait; older references without photos show a placeholder. Add from Album opens the system photo picker directly from Face Recognition. Cancel to return to the same page, or select a photo with exactly one face and confirm the preview and Face ID to save it. **Use Camera** starts guided capture. Both sources use the same confirmation with Retry and Done. Retry reopens the picker for album input or restarts guided camera capture. The 1:1 confirmation buttons use a 42 pt minimum height and can grow with larger text.

[FaceRecognitionView](HiFaceDemo/Recognition/FaceRecognitionView.swift) owns album selection and cancels extraction when leaving Face Recognition. [CameraDemoModel](HiFaceDemo/Camera/CameraDemoModel.swift) validates and stages the sample. [CaptureConfirmation](HiFaceDemo/Capture/FaceCaptureView.swift) saves a reference on Done.

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
