**English** | [简体中文](README.zh-CN.md)

# HiFace HarmonyOS Demo Guide


See the [SDK API](../SDK.md) for integration requirements and API details.

On Face Recognition, action challenges start enabled for both 1:1 verification and standalone liveness, with Blink and Nod Head selected. You can turn them off or choose other actions.

Camera verification and standalone liveness use system text-to-speech for face-position and action prompts. The Demo supplies English (`en-US`) and Chinese (`zh-CN`) prompts, and playback depends on a matching voice on the device. Repeated prompt text leaves playback uninterrupted. A new prompt replaces it. The camera guidance stays visible throughout.

The Demo returns as soon as a camera flow completes and lets an already-playing prompt continue for up to two seconds. Canceling the camera flow stops speech immediately. Speech is limited to camera guidance. Results are shown on screen.

## 1:1 reference enrollment

Face Recognition owns the ordered action choices and the 1:1 passive-liveness switch. Swipe through the enrolled portraits and select a Face ID to start verification directly. A thin indicator shows the scroll position while browsing the list. Independent liveness always performs passive checks, with optional actions. Both camera flows return their outcomes to this page without a result dialog. Confirmed captures save a private portrait; older references without photos show a placeholder. Add from Album opens the system photo picker directly from Face Recognition. Cancel to return to the same page, or select a photo with exactly one face and confirm the preview and Face ID to save it. **Use Camera** starts guided capture. Both sources reuse the same confirmation before saving a reference.

[Index](src/main/ets/pages/Index.ets) opens the picker and discards results after navigation. [RealtimeCameraDemo](src/main/ets/pages/RealtimeCameraDemo.ets) handles confirmation for both input sources.

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
