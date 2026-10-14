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
