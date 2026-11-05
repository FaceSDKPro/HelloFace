# Data Processing and Privacy Compliance

**English** · [简体中文](DATA_PROCESSING_AND_PRIVACY.zh-CN.md) · [Español](DATA_PROCESSING_AND_PRIVACY.es.md) · [Português (Brasil)](DATA_PROCESSING_AND_PRIVACY.pt-BR.md)<br>
[Français](DATA_PROCESSING_AND_PRIVACY.fr.md) · [Deutsch](DATA_PROCESSING_AND_PRIVACY.de.md) · [日本語](DATA_PROCESSING_AND_PRIVACY.ja.md) · [한국어](DATA_PROCESSING_AND_PRIVACY.ko.md) · [Bahasa Melayu](DATA_PROCESSING_AND_PRIVACY.ms.md)

[Home](../../README.md)

Scope: the HelloFace SDK. This document is intended for SDK integrators and describes current data flows and integrators' data management responsibilities. It does not replace the privacy policy of an integrator's app or service and does not indicate that any particular deployment has been certified as compliant.

## Where processing happens

The SDK performs face detection, capture, feature extraction, liveness detection, comparison and search on the device. The SDK itself does not collect or transmit any data.
The SDK layer declares no network permissions or capabilities. The host application must explain the purposes of its camera permissions, photo selection and network permissions.

## Data involved

| Data | Purpose and boundary |
|---|---|
| Camera frames, selected/imported photos and face crops | Detection, capture, liveness, feature extraction and preview; additional original-image storage depends on the application |
| Face features, record IDs, groups and tags | Enrollment, lookup and comparison in a local gallery; records can be stored persistently on the device after enrollment or import |
| Local SDK runtime state, application settings and logs | Operation and diagnostics; managed separately from the business face gallery, with data minimization also applied to logs |
| Operating system version and hardware model | Allow the SDK to select optimized execution strategies for different operating systems and hardware configurations |

## Responsibilities of SDK integrators

SDK integrators are responsible for the lawful, compliant handling and management of face data in the apps or services that integrate the SDK, according to their use cases, processing activities, and the requirements applicable in each country or region of deployment. This includes collection, use, storage, access, sharing, transfer, and deletion. Integrators must also provide users with clear information about data processing and a channel for related requests, and are responsible for handling those requests.

The SDK's current offline, on-device architecture keeps face-data computation on the device to protect user data by design and minimize the risk of exposing face data to external services. Integrators are responsible for the access controls, storage protection, retention and deletion mechanisms, and applicable notice, authorization, and security measures for any data storage, cloud synchronization, or other processing implemented by their apps or services.

The current SDK does not support face recognition for children under 12 and must not be used in financial scenarios.

For SDK integration support or to report SDK security issues, integrators can contact [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com).
