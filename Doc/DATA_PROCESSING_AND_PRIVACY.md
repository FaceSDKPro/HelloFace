# Data Processing and Privacy Compliance

English | [简体中文](DATA_PROCESSING_AND_PRIVACY.zh-CN.md) · [Home](../README.md)

Scope: the HelloFace 0.8.6 Beta SDKs and public Demos. This document describes current data flows and integrator responsibilities. It is not a host application's privacy policy or a compliance certification for a deployment. SDK usage restrictions and third-party licenses continue to apply separately.

## Where processing happens

The SDK performs face detection, capture, feature extraction, liveness, comparison and search on the device. Its face calculations do not require camera frames or face features to be sent to a vendor service. The SDK layer declares no network permissions or capabilities.

The Demos are editable integration examples. Online image import in the Android, iOS and Harmony Demos requests the selected image URLs; image servers may receive IP addresses and request metadata. The host application must explain its camera, photo-picker and network uses. GitHub, the APK download site, the online Web experience and WeChat are separate services with their own processing practices, rather than part of the SDK's offline calculations.

## Data involved

| Data | Purpose and boundary |
|---|---|
| Camera frames, selected/imported photos and face crops | Detection, capture, liveness, feature extraction and preview; additional original-image storage depends on the application |
| Face features, record IDs, groups and tags | Enrollment, lookup and comparison in a local gallery; enrollment or import can create persistent records |
| Similarity, liveness results and errors | Result display and diagnostics; a score alone does not establish identity or security |
| Local SDK runtime state, application settings and logs | Operation and diagnostics; managed separately from the business face gallery, with data minimization also applied to logs |

Face features are not inherently anonymous. Feature encoding, protection of SDK models and application signing do not encrypt your galleries, photos, exports or system backups. Protect storage, access, backups, exports and transport according to risk, including encryption at rest and key management where needed. A Demo is not a complete production data-security system.

## Retention, deletion and resources

Integrators determine necessary data, retention periods and deletion procedures. Closing the camera or a screen, or deleting a gallery record, does not delete original photos, other galleries, exports, caches, logs, remote image sources or system backups. Uninstallation depends on platform and backup settings; it is not a cross-platform secure-erasure promise.

Example features and image indexes support demonstrations. They do not grant commercial rights or a legal basis to process arbitrary external images, faces or identity data. Verify provenance, processing grounds and permitted use. Keep real galleries, personal photos, features, keys and device state out of Git, public issues and public logs. Calling the Demo or SDK does not automatically upload these inputs for vendor model training.

## Responsibilities before deployment

Identify the actual personal information handler, purposes, necessity, notice and consent process, permissions, retention/deletion rules and a contact for individual rights. Implement access control, security audit, risk assessment and incident handling, plus applicable arrangements for processors, disclosure and cross-border transfers.

Under applicable PRC law, biometrics are sensitive personal information. The actual handler must assess and meet requirements concerning necessity, separate consent, minors and prior impact assessment. See Articles 28–31 and 55 of the [Personal Information Protection Law](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm).

The [Measures for the Safe Application of Facial Recognition Technology](https://www.cac.gov.cn/2025-03/21/c_1744174262156096.htm) also address on-device storage and external transmission, minimal retention, alternative verification and filing requirements. Apply the relevant conditions to your deployment. On-device calculation alone does not fulfill every obligation.

The current model does not support face recognition for children under 12 and must not be used in financial scenarios. These product restrictions differ from legal protections for the personal information of children under 14; neither replaces the other. Assess local rules for other jurisdictions.

Direct personal-data requests first to the application or service operator actually using the face data. For SDK integration or security issues, contact [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com). Start with the version, redacted error codes and minimum necessary reproduction details, rather than personal photos or face features.
