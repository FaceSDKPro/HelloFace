# HiFace Linux SDK API 指南

[English](README.md) | 简体中文

## 快速开始

使用 Ubuntu 22.04+ 的 ARM64 或 x86_64 系统，选择对应架构的 SDK，并安装 C 编译器和 CMake 3.22.1+。在 SDK 目录中运行。部署时保留 `libhiface.so.1` 软链及其目标文件。

```bash
sha256sum -c FILES.sha256
cmake -S ../../../examples/image-search -B build -DCMAKE_PREFIX_PATH="$PWD"
cmake --build build --target hiface_sdk_image_search
./build/hiface_sdk_image_search --builtin :memory: --blank 256 256
```

[image_search.c](../../../examples/image-search/image_search.c) 加载内置模型，处理空白图，使用内存人脸库。预期输出以 `faces=0` 开头。处理自己的照片时，将 `--blank 256 256` 换成 `photo.rgba WIDTH HEIGHT`。先调整照片方向，传入宽高均为偶数、连续排列的 RGBA 像素，长度为 `WIDTH * HEIGHT * 4` 字节。

在自己的项目中，将 `CMAKE_PREFIX_PATH` 指向 SDK 目录，调用 `find_package(HiFace CONFIG REQUIRED)` 并链接 `HiFace::HiFace`。用 `hiface_runtime_configure_v1` 配置运行时，再用 `hiface_session_create_v1` 创建会话，最后通过 `hiface_linux_load_builtin_models_v1` 加载内置模型。运行时状态使用私有的持久目录，默认 `~/.local/state/hiface`，也可使用配置后的 `$XDG_STATE_HOME/hiface`。

## API 参考

函数签名和结构体定义见 `include/hiface/hiface_c_api.h` 与平台头文件。含 `struct_size` 的结构体填 `sizeof(...)`。 带 `api_version` 的结构体填 `HIFACE_C_API_VERSION_V1`。C API 的配置由调用方填写，下表中的建议值可作为初始配置。

### 人脸检测

照片用 `hiface_session_process_rgba_v1`，相机用 `hiface_session_process_camera_yuv420_v1`。传入实际行步长和旋转角度。成功时读取 `faces[0..count)`；无人脸时 `count=0`。人脸框为左上角和宽高，单位是像素。相机结果对应旋转后、未镜像的画面。

| `HiFaceDetectionRequestV1` 参数 | 范围与建议值 | 用途 |
|---|---|---|
| `max_faces` | 1–10，建议从 1 开始 | 限制返回的人脸数，`capacity` 至少等于此值。 |
| `detailed_landmarks` | 0 或 1，建议从 0 开始 | 开启后附带详细关键点及头部角度，须启用对应模型。 |

### 人脸录入与照片采集

- `hiface_session_capture_rgba_v1` 采集最大人脸，返回用于比对的特征，可选对齐图。无人脸或人脸过小分别返回 `HIFACE_STATUS_IMAGE_NO_FACE` 或 `HIFACE_STATUS_IMAGE_FACE_TOO_SMALL`。
- `hiface_session_capture_faces_rgba_v1` 采集多张脸。调用方提供容量 1–10，逐张读取状态，无人脸时成功返回 `count=0`。
- 相机引导录入使用 `hiface_session_face_flow_start_v1` 与 `HIFACE_FLOW_GUIDED_CAPTURE`。照片采集无活体判定，用户确认后再保存特征。

### 活体与 1:1 验证

用 `hiface_session_face_flow_start_v1` 选择流程并持续送帧。独立静默或动作活体用 `HIFACE_FLOW_ACTION_LIVENESS`；1:1 用 `HIFACE_FLOW_FACE_VERIFICATION`，需要叠加静默活体时用 `HIFACE_FLOW_FACE_AUTHENTICATION`。已有两份特征可用 `hiface_feature_compare_v1` 取得 0–1 相似度。

| `HiFaceFlowConfigV1` 参数 | 范围与建议值 | 用途 |
|---|---|---|
| `action_count` | 0–4，录入必须为 0 | 动作数量，独立活体设 0 时仅执行静默活体。 |
| `verification_threshold` | 0–1，推荐 0.80 | 完成比对且低于门槛时返回身份不匹配。验证还须传入 `verification_reference` 与特征长度。 |
| `action_timeout_ms`、`face_acquisition_timeout_ms` | 推荐 3,000、10,000 ms | 单个动作时限和首次取脸时限。小于等于 0 时停用对应计时。 |
| `final_capture_timeout_ms` | 除引导录入外须大于 0，推荐 3,000 ms | 最终取样的时限。 |

RGB 静默活体使用 SDK 固定门槛 0.90。流程结束时用 `hiface_session_face_flow_copy_result_v1` 读取 `outcome`，按 `flags` 检查分数或附带结果是否有效。独立红外活体先通过 `hiface_linux_load_infrared_model_v1` 加载红外模型，再调用 `hiface_session_evaluate_infrared_liveness_v1`。传入真实 GRAY8 红外帧、图中人脸框及按设备标定的 0–1 阈值。阈值必填。

### 人脸库与搜索

`hiface_search_open_v1` 打开数据库，`hiface_search_upsert_v1` 写入记录。调用 `hiface_search_query_v1` 时显式提供 `top_k`（1–100，建议从 1 开始）和 `threshold`（0–1，推荐 0.80）。返回达到门槛的匹配，无匹配为成功空结果。`group`、`tag` 为精确筛选，两项都填写时同时匹配，空串或 `NULL` 表示该项不限制。Face ID 为 1–1024 个 UTF-8 字节，分组和标签各最多 1024 字节。保存同一 Face ID 会更新记录，批量最多 1,000 条。

以 `hiface_session_search_start_v1` 启动连续搜索。使用同一单调时钟，逐帧执行 prepare → resolve → complete → read → destroy。

| `HiFaceSearchCameraConfigV1` 参数 | 范围与建议值 | 用途 |
|---|---|---|
| `multi_face`、`need_liveness` | 0 或 1，建议从单人并开启活体开始 | 多人搜索不支持活体。 |
| `threshold` | 0.75–0.85，推荐 0.80 | 连续搜索的身份门槛。 |
| `max_faces` | 1–5，多人可从 3 开始 | 多人模式每帧处理上限。单人仅处理最大脸。 |
| `interval_ms`、`timeout_ms` | 0–3,000 ms（推荐 0）、1,000–3,000 ms（推荐 3,000） | 成功后的等待间隔和从选中人脸开始的单轮时限。 |

先读 `end_reason`，再按 `has_similarity` 和 `has_liveness_score` 读取分数。活体拒绝时，即使相似度达标也不能放行。需要结束帧整图时，在释放批次或送入下一帧前调用 `hiface_session_search_copy_jpeg_v1`，在回调内复制图像数据。

RGB/IR 双路搜索接口见 `hiface_rgbir.h`。以 1:N 和 `need_liveness=0` 调用 `hiface_session_search_start_rgbir_v1`。标定 RGB 到 IR 的坐标映射，显式提供大于 0、小于等于 1 的红外门槛。双帧时间差上限为 1–200 ms，帧龄上限从该值到 1,000 ms。使用同一个单调时钟。只有本轮同时命中身份且 `HIFACE_SEARCH_IR_PASSED` 才通过，红外缺失或拒绝时不会匹配。

人脸特征应原样保存。更换不兼容的模型时，从原照片重新提取特征并导入。应用负责取得用户同意，以及保护和删除照片与特征。

## 错误处理与资源释放

| 状态 | 处理方式 |
|---|---|
| `HIFACE_STATUS_OK` | 调用成功。业务是否通过由 `outcome` 或 `end_reason` 决定。 |
| `HIFACE_STATUS_FRAME_SKIPPED` | 丢弃本帧，继续送入最新帧。 |
| `HIFACE_STATUS_BUSY` | 先结束冲突的会话流程再重试。初始化遇到该状态时释放未完成的会话，稍后重试。 |
| `HIFACE_STATUS_INVALID_ARGUMENT` | 检查结构体大小、版本、参数和缓冲区。 |
| `HIFACE_STATUS_MODEL_LOAD_FAILED`、`HIFACE_STATUS_LICENSE_EXPIRED` | 检查模型加载报告或授权有效期。 |

在工作线程串行调用同一个会话。关闭前等待在途调用结束，并在结果销毁前复制需要保留的数据。用对应的 SDK 函数销毁搜索结果、批次和会话，关闭数据库。

当前模型不支持 12 周岁以下儿童人脸识别，不能用于金融场景。分发时保留许可及附带声明。
