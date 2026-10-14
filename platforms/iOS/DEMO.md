# HiFace iOS Demo Guide

English | [简体中文](DEMO.zh-CN.md)

See the [SDK guide](SDK/README.md) for APIs and integration requirements.

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
