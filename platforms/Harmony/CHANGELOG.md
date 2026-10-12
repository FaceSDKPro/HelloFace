# Changelog

## [Unreleased]

## [0.0.1] - Release candidate

- Preserved original HF1 features with explicit feature-space IDs; added lightweight metadata pages, existence checks and metadata-only updates.
- Moved search-database close and SQLite/cache cleanup to background work, rejecting queued operations after close.
- Rejected integer truncation at the N-API boundary and aligned search thresholds with Core float32 semantics.

- Aligned SDK and Demo versions with the Android/iOS 0.0.1 release train; verified local zero-major HAR build and OHPM prepublish (registry review pending).
- Added customer Demo checksums, version/source metadata and commercial/third-party notices; technical license enforcement is deferred to a later version.
- Removed the pre-release fixed build-stage probe; runtime compatibility diagnostics use `getApiVersion()` and readiness uses `whenReady()`.

- Hardened customer Demo export and Release verification so only a fully validated HAR with all five encrypted models embedded exactly once can be delivered.
- Fixed Demo capture/liveness/search startup by passing the shared SDK as a plain ArkUI component input, avoiding `@Prop` copies of live Promises and session state.
- Moved camera-flow/search start, stop and SDK destruction off the ArkUI thread; invalidate stale work immediately and order replacement starts after pending controls.

- Aligned liveness flow defaults and `hasActions()` with the Android SDK contract.
- Hardened camera-flow Native argument validation, Demo retry behavior and result-dialog frame suspension.
- Prepared the initial HarmonyOS release candidate of the HiFace bytecode HAR.
- Added offline face detection, capture, liveness, 1:1 verification and 1:N/M:N search.
- Added an independent SQLite face database, realtime frame backpressure and stable lifecycle errors.
- Added an arm64-v8a N-API library with embedded authenticated HFM2 models.
- Added consumer obfuscation rules and Release artifact hardening checks.
