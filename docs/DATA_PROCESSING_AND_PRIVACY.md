# Data Processing and Privacy Compliance

English | [简体中文](DATA_PROCESSING_AND_PRIVACY.zh-CN.md) · [Home](../README.md)

Scope: the HelloFace SDK and public Demos. This document describes current data flows and integrator responsibilities. It is not a host application's privacy policy and does not indicate that any particular deployment has been certified as compliant.

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

## Responsibilities before deployment

Identify the actual personal information handler, purposes, necessity, notice and consent process, permissions, retention/deletion rules and a contact for individual rights. Implement access control, security audit, risk assessment and incident handling, plus applicable arrangements for processors, disclosure and cross-border transfers.

Under applicable PRC law, biometrics are sensitive personal information. The actual handler must assess and meet requirements concerning necessity, separate consent, minors and prior impact assessment. See Articles 28–31 and 55 of the [Personal Information Protection Law](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm).

The [Measures for the Safe Application of Facial Recognition Technology](https://www.cac.gov.cn/2025-03/21/c_1744174262156096.htm) also address on-device storage and external transmission, minimal retention, alternative verification and filing requirements. Apply the relevant conditions to your deployment. On-device calculation alone does not fulfill every obligation.

The current SDK does not support face recognition for children under 12 and must not be used in financial scenarios. Assess local rules for deployments outside China.

Direct personal-data requests first to the application or service operator actually using the face data. For SDK integration or security issues, contact [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com).
