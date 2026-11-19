# HiFace Windows SDK · 0.8.13

English | [简体中文](README.zh-CN.md)

## Quick start

Use Windows 10/11 x64, the Visual Studio 2022 Desktop C++ tools and CMake 3.22.1+. Run from the SDK directory in PowerShell:

```powershell
cmake -S ../examples -B build -G "Visual Studio 17 2022" -A x64 -DCMAKE_PREFIX_PATH="$PWD"
cmake --build build --config Release --target hiface_model_consumer
./build/bin/Release/hiface_model_consumer.exe
```

[model_consumer.cpp](../examples/model_consumer.cpp) loads the built-in CPU models and runs detection on a blank image. It prints `Built-in CPU models and blank RGBA detection passed without external model files` on success. The example build copies the DLLs next to the executable.

For your own project, set `CMAKE_PREFIX_PATH` to the SDK folder, call `find_package(HiFace 0.8.13 CONFIG REQUIRED COMPONENTS C)`, and link `HiFace::HiFace`. Configure the runtime once with `hiface_runtime_configure_v1`, create a session with `hiface_session_create_v1`, load the requested models with `hiface_windows_session_load_model_v1`, then call `hiface_session_prepare_loaded_models_v1`. Deploy the x64 DLLs in `bin/` alongside your executable and include your application's CRT.

## API reference

See `include/hiface/hiface_c_api.h` and the platform header for signatures and structures. Initialize each `struct_size` field with `sizeof(...)` and set `api_version` to `HIFACE_C_API_VERSION_V1` where present. With the C API, supply configuration values explicitly. The suggested values below are starting points.

### Face detection

Use `hiface_session_process_rgba_v1` for photos and `hiface_session_process_camera_yuv420_v1` for camera frames. Provide the actual frame strides and rotation. On success, read the first `count` entries in `faces`. No faces sets `count=0`. Face boxes use top-left coordinates, width and height in pixels. Camera results refer to the rotated, unmirrored image.

| `HiFaceDetectionRequestV1` parameter | Range and suggested value | Purpose |
|---|---|---|
| `max_faces` | 1–10; start with 1 | Limits returned faces. Set `capacity` to at least this value. |
| `detailed_landmarks` | 0 or 1; start with 0 | Includes detailed landmarks and head angles when enabled with the corresponding model. |

### Face enrollment and photo capture

- `hiface_session_capture_rgba_v1` uses the largest face and returns a feature and optional aligned image. No face and a face that is too small return `HIFACE_STATUS_IMAGE_NO_FACE` and `HIFACE_STATUS_IMAGE_FACE_TOO_SMALL`, respectively.
- `hiface_session_capture_faces_rgba_v1` handles multiple faces. Supply a capacity of 1–10 and check each face's status. No faces is a successful `count=0`.
- For guided enrollment, use `hiface_session_face_flow_start_v1` with `HIFACE_FLOW_GUIDED_CAPTURE`. Photo capture performs no liveness check. Save the feature after the user confirms enrollment.

### Liveness and 1:1 verification

Choose a mode with `hiface_session_face_flow_start_v1` and keep feeding frames. Use `HIFACE_FLOW_ACTION_LIVENESS` for standalone passive or action liveness, `HIFACE_FLOW_FACE_VERIFICATION` for 1:1, and `HIFACE_FLOW_FACE_AUTHENTICATION` for 1:1 with passive liveness. Compare two existing features with `hiface_feature_compare_v1` to get a similarity score from 0 to 1.

| `HiFaceFlowConfigV1` parameter | Range and suggested value | Purpose |
|---|---|---|
| `action_count` | 0–4; enrollment requires 0 | Action count. Standalone liveness with 0 actions still runs passive liveness. |
| `verification_threshold` | 0–1; suggested 0.80 | A completed comparison below this score returns a mismatch. Also supply `verification_reference` and the reference feature length for verification. |
| `action_timeout_ms`, `face_acquisition_timeout_ms` | Suggested 3,000 and 10,000 ms | Per-action and initial face acquisition timers. A value of zero or less disables that timer. |
| `final_capture_timeout_ms` | Greater than 0 except for guided enrollment; suggested 3,000 ms | Time budget for final capture. |

RGB passive liveness uses an SDK threshold of 0.90. Read `outcome` with `hiface_session_face_flow_copy_result_v1`, and check `flags` before using optional scores or data. For standalone infrared liveness, load the IR model with `hiface_windows_session_load_model_v1`, then call `hiface_session_evaluate_infrared_liveness_v1` with a real GRAY8 IR frame, its face box, and a required 0–1 threshold calibrated on the target camera.

### Face library and search

Open a database with `hiface_search_open_v1`. Use `hiface_search_upsert_v1` to save entries. Call `hiface_search_query_v1` with an explicit `top_k` (1–100; start with 1) and `threshold` (0–1; suggested 0.80). It returns matches that meet the threshold. No matches is a successful empty result. `group` and `tag` are exact filters that must both match when supplied. Use an empty string or `NULL` to omit a filter. Face IDs take 1–1024 UTF-8 bytes, and each group or tag takes at most 1024 bytes. Saving the same Face ID updates the record. Save at most 1,000 records per batch.

Start continuous search with `hiface_session_search_start_v1`. Use one monotonic clock and run prepare → resolve → complete → read → destroy for each frame.

| `HiFaceSearchCameraConfigV1` parameter | Range and suggested value | Purpose |
|---|---|---|
| `multi_face`, `need_liveness` | 0 or 1; start with single-face and liveness enabled | Liveness is available in single-face mode. |
| `threshold` | 0.75–0.85; suggested 0.80 | Identity threshold for continuous search. |
| `max_faces` | 1–5; start with 3 for multi-face search | Limits faces per frame in multi-face mode. Single-face mode selects the largest face. |
| `interval_ms`, `timeout_ms` | 0–3,000 ms (suggested 0), 1,000–3,000 ms (suggested 3,000) | Wait after a match and time budget from the first selected face. |

Check `end_reason` first. Read scores when `has_similarity` or `has_liveness_score` indicates a value. A liveness rejection takes precedence over passing similarity. To get the optional terminal scene, call `hiface_session_search_copy_jpeg_v1` before submitting another frame or destroying the batch. Copy the bytes in the callback.

Store features as returned. When changing to an incompatible model, re-extract and reimport features from the original photos. Your application handles consent, protection and deletion of photos and features.

## Errors and cleanup

| Status | What to do |
|---|---|
| `HIFACE_STATUS_OK` | The call succeeded. Check `outcome` or `end_reason` for the business result. |
| `HIFACE_STATUS_FRAME_SKIPPED` | Drop the old frame and continue with the latest one. |
| `HIFACE_STATUS_BUSY` | Stop the conflicting flow before retrying. For busy initialization, release the unfinished session and retry later. |
| `HIFACE_STATUS_INVALID_ARGUMENT` | Check structure size, version, arguments and buffers. |
| `HIFACE_STATUS_MODEL_LOAD_FAILED`, `HIFACE_STATUS_LICENSE_EXPIRED` | Check the model load report or license validity. |

Serialize calls to each session on a worker thread and wait for active calls before closing it. Copy data you need to retain before destroying the result. Use the matching SDK functions to destroy search results, batches and sessions, and to close the database. For a missing DLL or `0xc000007b`, check the architecture and deploy the complete x64 DLL set.

The current model does not support face recognition for people under 12. Financial use is prohibited. Keep the license and notices when redistributing.
