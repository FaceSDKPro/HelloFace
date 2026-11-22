**English** | [简体中文](README.zh-CN.md)

# HiFace Windows SDK · 0.8.15


## Quick start

Use Windows 10/11 x64, the Visual Studio 2022 Desktop C++ tools and CMake 3.22.1+. Run from the SDK directory in PowerShell:

```powershell
cmake -S ../examples -B build -G "Visual Studio 17 2022" -A x64 -DCMAKE_PREFIX_PATH="$PWD"
cmake --build build --config Release --target hiface_model_consumer
./build/bin/Release/hiface_model_consumer.exe
```

[model_consumer.cpp](../examples/model_consumer.cpp) loads the built-in CPU models and runs detection on a blank image. It prints `Built-in CPU models and blank RGBA detection passed without external model files` on success. The example build copies the DLLs next to the executable.

For your own project, set `CMAKE_PREFIX_PATH` to the SDK folder, call `find_package(HiFace 0.8.15 CONFIG REQUIRED COMPONENTS C)`, and link `HiFace::HiFace`. Configure the runtime once with `hiface_runtime_configure_v1`, create a session with `hiface_session_create_v1`, load the requested models with `hiface_windows_session_load_model_v1`, then call `hiface_session_prepare_loaded_models_v1`. Deploy the x64 DLLs in `bin/` alongside your executable and include your application's CRT.

## API reference

See `include/hiface/hiface_c_api.h` and the platform header for signatures and structures. Initialize each `struct_size` field with `sizeof(...)` and set `api_version` to `HIFACE_C_API_VERSION_V1` where present. With the C API, supply configuration values explicitly. The suggested values below are starting points.

Zero-initialize configurations, then explicitly fill required fields. Initialization and model loading are synchronous: run them on a worker and initialize each model report's `struct_size`. Process-wide settings cannot change after the first session is created.

| Configuration field | Range and suggested value | Purpose |
|---|---|---|
| `HiFaceRuntimeConfigV1.cpu_threads` | 0, 2, 4; suggested 0 | 0 selects automatically; keep the same setting throughout the process. |
| `HiFaceConfigV1.compute_mode` | `HIFACE_COMPUTE_CPU` | The delivered SDK uses the CPU. |
| `HiFaceConfigV1.enable_feature` | 0 or 1 | Enable and load feature capability for extraction, capture, camera verification and search. |
| `HiFaceConfigV1.enable_landmark` | 0 or 1 | Enables detailed landmarks and action capability; also fill both thresholds below. |
| `HiFaceConfigV1.eye_closed_ear_threshold` | 0.05–0.45; suggested 0.18 | Blink threshold; ignored when landmark capability is off. |
| `HiFaceConfigV1.mouth_open_mar_threshold` | 0.05–0.80; suggested 0.22 | Mouth-open threshold; ignored when landmark capability is off. |

Load the detector first, then the feature model for extraction/capture/search, landmarks for detailed output and actions, and both passive-liveness models for RGB liveness. Enabling a capability does not load its model; check preparation after loading.

### Face detection

Use `hiface_session_process_rgba_v1` for photos and `hiface_session_process_camera_yuv420_v1` for camera frames. Provide the actual frame strides and rotation. On success, read the first `count` entries in `faces`. No faces sets `count=0`. Face boxes use top-left coordinates, width and height in pixels. Camera results refer to the rotated, unmirrored image.

| `HiFaceDetectionRequestV1` parameter | Range and suggested value | Purpose |
|---|---|---|
| `max_faces` | 1–10; start with 1 | Limits returned faces. Set `capacity` to at least this value. |
| `detailed_landmarks` | 0 or 1; start with 0 | Includes detailed landmarks and head angles when enabled with the corresponding model. |

`HiFaceFrameResultV1.faces` points to the caller's face array; set `capacity` to its length and initialize the result's `struct_size`. `pose_valid`, `mesh_valid` and `metrics_valid` independently indicate valid fields; zero values do not indicate validity. Head angles are in degrees. Input pixels and strides are borrowed only during the synchronous call.

### Face enrollment and photo capture

- `hiface_session_capture_rgba_v1` uses the largest face and returns a feature and optional aligned image. No face and a face that is too small return `HIFACE_STATUS_IMAGE_NO_FACE` and `HIFACE_STATUS_IMAGE_FACE_TOO_SMALL`, respectively.
- `hiface_session_capture_faces_rgba_v1` handles multiple faces. Supply a capacity of 1–10 and check each face's status. No faces is a successful `count=0`.
- For guided enrollment, use `hiface_session_face_flow_start_v1` with `HIFACE_FLOW_GUIDED_CAPTURE`. Photo capture performs no liveness check. Save the feature after the user confirms enrollment.

Feature capacity is measured in `HIFACE_FACE_FEATURE_DIMENSION` float elements; preview capacity is `HIFACE_ALIGNED_PREVIEW_RGBA_BYTES` bytes. To omit previews, pass `NULL/0`. Strict single-face enrollment uses the multi-face API with capacity 10 and requires one returned face with status `OK`; largest-face capture does not reject multi-person photos.

### Liveness and 1:1 verification

Choose a mode with `hiface_session_face_flow_start_v1` and keep feeding frames. Use `HIFACE_FLOW_ACTION_LIVENESS` for standalone passive or action liveness, `HIFACE_FLOW_FACE_VERIFICATION` for 1:1, and `HIFACE_FLOW_FACE_AUTHENTICATION` for 1:1 with passive liveness. Compare two existing features with `hiface_feature_compare_v1` to get a similarity score from 0 to 1.

| `HiFaceFlowConfigV1` parameter | Range and suggested value | Purpose |
|---|---|---|
| `action_count` | 0–4; enrollment requires 0 | Action count. Standalone liveness with 0 actions still runs passive liveness. |
| `verification_threshold` | Recommended 0.75–0.85; use 0.80 explicitly | A completed comparison below this score returns a mismatch. Also supply `verification_reference` and the reference feature length for verification. |
| `action_timeout_ms` | Suggested 3,000 ms | Per-action timer; zero or less disables it. |
| `face_acquisition_timeout_ms` | Suggested 10,000 ms | Initial face acquisition timer; zero or less disables it. |
| `face_lost_timeout_ms` | Suggested 300 ms; zero or less disables it | Wait after the selected face leaves the frame. |
| `multiple_faces_allowed` | 0 or 1; suggested 0 | Allows additional faces; it does not provide cross-frame identity tracking. |
| `multiple_faces_timeout_ms` | Suggested 500 ms; zero or less disables it | Wait while multiple faces remain when they are disallowed. |
| `final_capture_timeout_ms` | Greater than 0 except for guided enrollment; suggested 3,000 ms | Time budget for final capture. |
| `min_face_size_pixels` | Finite and greater than 0; suggested 100 px | Minimum capture face width and height; final verification may still sample smaller faces. Explicitly required. |
| `frontal_hold_ms` | At least 0; suggested 1,000 ms | For passive liveness, the seven samples span this duration after a fixed 400 ms frontal wait. A zero duration still requires seven frames. |

Use a prepared `session`; `now_ms` is the current millisecond value from the same monotonic clock used for subsequent frames. These are caller-supplied settings, not defaults from zero initialization.

```c
HiFaceFlowConfigV1 config = {0};
config.struct_size = sizeof(config);
config.api_version = HIFACE_C_API_VERSION_V1;
config.mode = HIFACE_FLOW_ACTION_LIVENESS;
config.action_count = 0;
config.action_timeout_ms = 3000;
config.face_acquisition_timeout_ms = 10000;
config.face_lost_timeout_ms = HIFACE_FLOW_DEFAULT_FACE_LOST_TIMEOUT_MS;
config.multiple_faces_timeout_ms = HIFACE_FLOW_DEFAULT_MULTIPLE_FACES_TIMEOUT_MS;
config.final_capture_timeout_ms = 3000;
config.frontal_hold_ms = 1000;
config.min_face_size_pixels = 100.0f;
config.verification_threshold = 0.80f;
HiFaceStatus status = hiface_session_face_flow_start_v1(session, &config, now_ms);
```

Check `out_event.kind` as well as the frame return status: read `flow_status` on `HIFACE_FLOW_EVENT_ERROR`, and copy a terminal result on `HIFACE_FLOW_EVENT_RESULT_AVAILABLE`. An `OK` frame call does not imply flow acceptance. The `HIFACE_FLOW_RESULT_HAS_FEATURE`, `HIFACE_FLOW_RESULT_HAS_PREVIEW`, `HIFACE_FLOW_RESULT_HAS_LIVENESS` and `HIFACE_FLOW_RESULT_HAS_SIMILARITY` flags independently indicate available data.

Pass a null output buffer and zero capacity to `hiface_session_face_flow_copy_frame_v1` to query dimensions. With an image it returns `RESOURCE_EXHAUSTED`; allocate `width * height * 4` bytes and copy the same result again. Without an image it returns `OK` with zero dimensions. This capacity query is not an allocation failure. Call `hiface_session_face_flow_stop_v1` after consuming the result or to cancel; cancellation does not produce an accepted result.

The recommended similarity range is 0.75–0.85, with 0.80 as the default configuration value. The 1:1 and feature-query APIs accept 0–1; camera search accepts only 0.75–0.85. C APIs have no implicit defaults: supply the configuration values explicitly.

The recommended RGB/IR liveness threshold is 0.80–0.99, starting at 0.90. RGB passive liveness currently uses a fixed 0.90 with no public threshold setting. IR requires an explicit threshold and has no implicit default. Read `outcome` with `hiface_session_face_flow_copy_result_v1`, and check `flags` before using optional scores or data. For standalone infrared liveness, load the IR model with `hiface_windows_session_load_model_v1`, then call `hiface_session_evaluate_infrared_liveness_v1` with a real GRAY8 IR frame, its face box, and a required threshold calibrated on the target camera (recommended 0.80–0.99, starting at 0.90; the API accepts values greater than 0 and at most 1).

### Face library and search

Open a database with `hiface_search_open_v1` and save records with `hiface_search_upsert_v1`. Saving the same Face ID updates that record. Save at most 1,000 records per batch.

A library holds at most 50,000 records. Each upsert batch commits or rolls back as a whole; the last duplicate ID wins. Pagination uses offset starting at 0 and limit from 1–1,000; ordinary/feature lists sort by ID, and recent lists sort newest first. `update_time_ms` uses Unix milliseconds: 0 selects the current time and negatives are invalid. Metadata updates preserve a field for `NULL` and clear it for empty.

C capture produces floating-point features. Before saving, use `hiface_feature_encode_text_v1` with `HIFACE_FEATURE_TEXT_BUFFER_SIZE` capacity and preserve the returned text. Queries take float arrays; decode stored text with `hiface_feature_decode_text_v1` using `HIFACE_FACE_FEATURE_DIMENSION` elements. Set a write record's `feature_space_id` with `HIFACE_FEATURE_SPACE_ID`, rather than spelling its value yourself.

**Face records and filters**

| Parameter | Range and suggested value | Purpose |
|---|---|---|
| Face ID (`face_id`) | Required; 1–1024 UTF-8 bytes, followed by a NUL terminator | Application-assigned record ID for saving, updating or reading a record by ID. It is not a group or tag filter. |
| `group` | Optional; at most 1024 bytes (UTF-8) | The record's group. Queries match it exactly; `NULL` or empty means any group. |
| `tag` | Optional; at most 1024 bytes (UTF-8) | An application-defined label. Queries match it exactly; `NULL` or empty means any tag. |

When both filters are supplied, both must match. With neither filter, search the whole library.

**Query by an existing feature (`hiface_search_query_v1`)**

| Parameter | Range and suggested value | Purpose |
|---|---|---|
| `top_k` | Required; 1–100; start with 1 | Maximum number of matches returned. |
| `threshold` | Required; recommended 0.75–0.85; start at 0.80 | Feature-query similarity threshold. Returns records at or above it, or a successful empty result. Camera search uses the separate range below. |

Start continuous search with `hiface_session_search_start_v1`. Use one monotonic clock and run prepare → resolve → complete → read → destroy for each frame.

| `HiFaceSearchCameraConfigV1` parameter | Range and suggested value | Purpose |
|---|---|---|
| `multi_face` | 0 or 1; suggested 0 | 0 selects the largest face. 1 processes multiple faces, up to `max_faces`. |
| `need_liveness` | 0 or 1; suggested 1 for single-face mode | 1 enables RGB passive liveness; 0 disables it. Multi-face mode requires 0. |
| `threshold` | Required; 0.75–0.85 inclusive; suggested 0.80 | Camera-search identity threshold. Similarity must be at least this value; required liveness must also pass. |
| `max_faces` | 1–5; start with 3 for multi-face search | Limits faces per frame in multi-face mode. Single-face mode selects the largest face. |
| `interval_ms` | 0–3,000 ms; suggested 0 | Wait after a match before the next search. |
| `timeout_ms` | 1,000–3,000 ms; suggested 3,000 | Per-round time budget from the first selected face. |

Continue with resolve, complete and read only after prepare succeeds with a non-null batch. Destroy any created batch even if a later step fails. `end_reason == HIFACE_SEARCH_END_NONE` means the round is still running; do not accept from a provisional score. `image_width` and `image_height` are detection dimensions, while JPEG callback dimensions describe the output image; scale overlays accordingly.

Check `end_reason` first. Read scores when `has_similarity` or `has_liveness_score` indicates a value. A liveness rejection takes precedence over passing similarity. To get the optional terminal scene, call `hiface_session_search_copy_jpeg_v1` before submitting another frame or destroying the batch. Copy the bytes in the callback.

Store features as returned. When changing to an incompatible model, re-extract and reimport features from the original photos. Your application handles consent, protection and deletion of photos and features.

Count query/read results with `hiface_search_results_count_v1`, then call `hiface_search_results_get_v1` with initialized `out_entry.struct_size`. Its strings and feature pointers are borrowed until result destruction; copy anything to retain. Only a query's `score` represents similarity. A missing get returns `NOT_FOUND`; a query without matches returns `OK` and an empty result. `contains` and `delete` report existence/removal through their output values.

## Errors and cleanup

| Status | What to do |
|---|---|
| `HIFACE_STATUS_OK` | The call succeeded. Check `outcome` or `end_reason` for the business result. |
| `HIFACE_STATUS_FRAME_SKIPPED` | Drop the old frame and continue with the latest one. |
| `HIFACE_STATUS_BUSY` | Stop the conflicting flow before retrying. For busy initialization, release the unfinished session and retry later. |
| `HIFACE_STATUS_INVALID_ARGUMENT` | Check structure size, version, arguments and buffers. |
| `HIFACE_STATUS_RESOURCE_EXHAUSTED` | Reduce concurrency and check memory, disk space and capacity before retrying. |
| `HIFACE_STATUS_DATABASE_ERROR` | Check the database path, permissions and storage; preserve the data rather than deleting it automatically. |
| `HIFACE_STATUS_INTERNAL_ERROR` | Stop this request and contact support with the SDK version and error code. |
| `HIFACE_STATUS_MODEL_LOAD_FAILED` | Check the model load report and initialization of the required capability. |
| `HIFACE_STATUS_LICENSE_EXPIRED` | Check the validity dates and contact SDK support if needed. |

Serialize calls to each session on a worker thread and wait for active calls before closing it. Copy data you need to retain before destroying the result. Use the matching SDK functions to destroy search results, batches and sessions, and to close the database. For a missing DLL or `0xc000007b`, check the architecture and deploy the complete x64 DLL set.

| Resource | Release function |
|---|---|
| `HiFaceSearchResultsHandle` | `hiface_search_results_destroy_v1` |
| `HiFaceSearchBatchHandle` | `hiface_search_batch_destroy_v1` |
| `HiFaceSearchDatabaseHandle` | `hiface_search_close_v1` |
| `HiFaceSessionHandle` | `hiface_session_destroy_v1` |

Do not use `free/delete` on SDK handles. JPEG callback bytes are valid only during that callback: copy before returning. Do not throw C++ exceptions or destroy the borrowed session/batch from the callback.

The current model does not support face recognition for people under 12. Financial use is prohibited. Keep the license and notices when redistributing.
