[English](README.md) | **简体中文**

# HiFace Windows SDK · 0.8.17


## 快速开始

使用 Windows 10/11 x64、Visual Studio 2022 桌面 C++ 工具和 CMake 3.22.1+。在 PowerShell 中进入 SDK 目录并运行：

```powershell
cmake -S ../examples -B build -G "Visual Studio 17 2022" -A x64 -DCMAKE_PREFIX_PATH="$PWD"
cmake --build build --config Release --target hiface_model_consumer
./build/bin/Release/hiface_model_consumer.exe
```

[model_consumer.cpp](../examples/model_consumer.cpp) 加载内置 CPU 模型并检测空白图。成功时输出 `Built-in CPU models and blank RGBA detection passed without external model files`。示例构建会把 DLL 复制到可执行文件所在目录。

在自己的项目中，将 `CMAKE_PREFIX_PATH` 指向 SDK 目录，调用 `find_package(HiFace 0.8.17 CONFIG REQUIRED COMPONENTS C)` 并链接 `HiFace::HiFace`。先用 `hiface_runtime_configure_v1` 配置运行时，再用 `hiface_session_create_v1` 创建会话，通过 `hiface_windows_session_load_model_v1` 加载需要的模型，最后调用 `hiface_session_prepare_loaded_models_v1`。部署时把 `bin/` 的 x64 DLL 放到程序旁，并部署应用所需的 CRT。

## API 参考

函数签名和结构体定义见 `include/hiface/hiface_c_api.h` 与平台头文件。含 `struct_size` 的结构体填 `sizeof(...)`。 带 `api_version` 的结构体填 `HIFACE_C_API_VERSION_V1`。C API 的配置由调用方填写，下表中的建议值可作为初始配置。

先将配置清零，再显式设置必填字段。初始化与模型加载是同步调用，放在工作线程；每次模型报告都先设置 `struct_size`。首个 Session 创建后，进程级配置不能改成另一组值。

| 配置字段 | 范围与建议值 | 用途 |
|---|---|---|
| `HiFaceRuntimeConfigV1.cpu_threads` | 0、2、4，推荐 0 | 0 自动选择线程数；同一进程须保持一致。 |
| `HiFaceConfigV1.compute_mode` | `HIFACE_COMPUTE_CPU` | 当前交付使用 CPU。 |
| `HiFaceConfigV1.enable_feature` | 0 或 1 | 提取、采集及相机身份验证/搜索所需的特征能力；使用前设为 1 并加载相应模型。 |
| `HiFaceConfigV1.enable_landmark` | 0 或 1 | 详细关键点与动作所需能力；开启时还须填写下面两个门槛。 |
| `HiFaceConfigV1.eye_closed_ear_threshold` | 0.05–0.45，推荐 0.18 | 眨眼判定门槛，关闭关键点能力时忽略。 |
| `HiFaceConfigV1.mouth_open_mar_threshold` | 0.05–0.80，推荐 0.22 | 张嘴判定门槛，关闭关键点能力时忽略。 |

先加载检测模型；提取/采集/搜索再加载特征模型，详细关键点和动作再加载关键点模型，RGB 活体同时需要两份静默活体模型。仅把能力字段设为 1 不代表模型已加载，加载后仍须检查 prepare 结果。

### 人脸检测

照片用 `hiface_session_process_rgba_v1`，相机用 `hiface_session_process_camera_yuv420_v1`。传入实际行步长和旋转角度。成功时读取 `faces[0..count)`；无人脸时 `count=0`。人脸框为左上角和宽高，单位是像素。相机结果对应旋转后、未镜像的画面。

| `HiFaceDetectionRequestV1` 参数 | 范围与建议值 | 用途 |
|---|---|---|
| `max_faces` | 1–10，建议从 1 开始 | 限制返回的人脸数，`capacity` 至少等于此值。 |
| `detailed_landmarks` | 0 或 1，建议从 0 开始 | 开启后附带详细关键点及头部角度，须启用对应模型。 |

`HiFaceFrameResultV1.faces` 指向调用方的人脸数组，`capacity` 填数组容量，结果结构体先填 `struct_size`。`pose_valid`、`mesh_valid`、`metrics_valid` 分别表示对应字段是否有效，不从数值 0 推断有效性；头部角度单位为度。输入像素及步长仅在同步调用期间借用，返回后可复用。

### 人脸录入与照片采集

- `hiface_session_capture_rgba_v1` 采集最大人脸，返回用于比对的特征，可选对齐图。无人脸或人脸过小分别返回 `HIFACE_STATUS_IMAGE_NO_FACE` 或 `HIFACE_STATUS_IMAGE_FACE_TOO_SMALL`。
- `hiface_session_capture_faces_rgba_v1` 采集多张脸。调用方提供容量 1–10，逐张读取状态，无人脸时成功返回 `count=0`。
- 相机引导录入使用 `hiface_session_face_flow_start_v1` 与 `HIFACE_FLOW_GUIDED_CAPTURE`。照片采集无活体判定，用户确认后再保存特征。

特征输出容量按 `HIFACE_FACE_FEATURE_DIMENSION` 个 `float` 计算，对齐图容量按 `HIFACE_ALIGNED_PREVIEW_RGBA_BYTES` 字节计算；两者单位不同。不要预览时传 `NULL/0`。严格单人录入用多脸接口、容量设为 10，并要求返回一张且该条状态为 `OK`；最大脸接口不会拒绝多人照片。

### 活体与 1:1 验证

用 `hiface_session_face_flow_start_v1` 选择流程并持续送帧。独立静默或动作活体用 `HIFACE_FLOW_ACTION_LIVENESS`；1:1 用 `HIFACE_FLOW_FACE_VERIFICATION`，需要叠加静默活体时用 `HIFACE_FLOW_FACE_AUTHENTICATION`。已有两份特征可用 `hiface_feature_compare_v1` 取得 0–1 相似度。

| `HiFaceFlowConfigV1` 参数 | 范围与建议值 | 用途 |
|---|---|---|
| `action_count` | 0–4，录入必须为 0 | 动作数量，独立活体设 0 时仅执行静默活体。 |
| `verification_threshold` | 建议 0.75–0.85，推荐 0.80（须显式填写） | 完成比对且低于门槛时返回身份不匹配。验证还须传入 `verification_reference` 与特征长度。 |
| `action_timeout_ms` | 推荐 3,000 ms | 单个动作时限；小于等于 0 时停用该计时。 |
| `face_acquisition_timeout_ms` | 推荐 10,000 ms | 首次取脸时限；小于等于 0 时停用该计时。 |
| `face_lost_timeout_ms` | 推荐 300 ms，小于等于 0 时停用 | 已锁定的人脸离开画面的最长等待时间。 |
| `multiple_faces_allowed` | 0 或 1，推荐 0 | 是否允许其他人脸同时出现；不提供跨帧身份跟踪。 |
| `multiple_faces_timeout_ms` | 推荐 500 ms，小于等于 0 时停用 | 不允许多人时，持续多人画面的最长等待时间。 |
| `final_capture_timeout_ms` | 除引导录入外须大于 0，推荐 3,000 ms | 最终取样的时限。 |
| `min_face_size_pixels` | 必须为有限值且大于 0，建议 100 px | 采集所需的最小人脸宽、高；最终动态验证仍可采样较小的人脸。必须显式填写。 |
| `frontal_hold_ms` | 大于等于 0，建议 1,000 ms | 静默活体从合格正脸后 400 ms 开始，在本时长内均匀取 7 帧。设为 0 仍需等待 400 ms 并取得 7 帧。 |

下面使用已就绪的 `session`；`now_ms` 是与后续送帧相同单调时钟的当前毫秒值。所有数值为调用方配置，不是零初始化后的默认值。

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

每帧除检查返回状态外，还要检查 `out_event.kind`：`HIFACE_FLOW_EVENT_ERROR` 时读取 `flow_status`；`HIFACE_FLOW_EVENT_RESULT_AVAILABLE` 时才复制终态。帧调用返回 `OK` 不代表流程也通过。`flags` 中的 `HIFACE_FLOW_RESULT_HAS_FEATURE`、`HIFACE_FLOW_RESULT_HAS_PREVIEW`、`HIFACE_FLOW_RESULT_HAS_LIVENESS`、`HIFACE_FLOW_RESULT_HAS_SIMILARITY` 分别决定对应数据是否可用。

用 `hiface_session_face_flow_copy_frame_v1(session, NULL, 0, &width, &height)` 探测尺寸：有图时返回 `RESOURCE_EXHAUSTED`，按返回的 `width * height * 4` 字节分配后，对同一结果再复制；无图时为 `OK` 且宽高为 0。这种容量探测不是内存分配失败。完成后调用 `hiface_session_face_flow_stop_v1`；取消也使用 stop，不会产生一个“通过”结果。

相似度建议范围为 0.75–0.85，默认配置值为 0.80；1:1 验证和按特征查库的 API 实际允许 0–1，相机连续搜索仅允许 0.75–0.85。C API 没有隐式默认值，配置项须显式填写。

RGB/IR 活体建议门槛为 0.80–0.99，建议值为 0.90。当前 RGB 静默活体固定使用 0.90，未开放门槛设置；IR 门槛须显式传入，没有隐式默认值。流程结束时用 `hiface_session_face_flow_copy_result_v1` 读取 `outcome`，按 `flags` 检查分数或附带结果是否有效。独立红外活体先通过 `hiface_windows_session_load_model_v1` 加载红外模型，再调用 `hiface_session_evaluate_infrared_liveness_v1`。传入真实 GRAY8 红外帧、图中人脸框及按设备标定的阈值（建议 0.80–0.99，初始值 0.90，API 实际允许大于 0 且不超过 1）。阈值必填。

### 人脸库与搜索

`hiface_search_open_v1` 打开数据库，`hiface_search_upsert_v1` 保存记录。相同 Face ID 会更新该记录，单批最多 1,000 条。

单库最多 50,000 条。upsert 同一批全部提交或全部回滚，同 ID 以最后一条为准。分页 `offset` 从 0 开始，`limit` 为 1–1,000；普通/特征列表按 ID 排序，recent 列表按更新时间倒序。`update_time_ms` 为 Unix 毫秒，0 使用当前时间，负数无效；更新元数据时 `NULL` 保留原字段，空串清空。

C 采集输出浮点特征，存库前用 `hiface_feature_encode_text_v1` 转成 SDK 文本；文本缓冲容量用 `HIFACE_FEATURE_TEXT_BUFFER_SIZE`，存储时保留原文本。查库使用浮点数组；已有文本时先用 `hiface_feature_decode_text_v1`，数组长度用 `HIFACE_FACE_FEATURE_DIMENSION`。写入记录的 `feature_space_id` 使用 `HIFACE_FEATURE_SPACE_ID`，不自行拼写其内容。

**人脸记录与筛选**

| 参数 | 范围与建议值 | 用途 |
|---|---|---|
| Face ID（`face_id`） | 必填，1–1024 个 UTF-8 字节，末尾以 NUL 结束 | 应用指定的记录标识。用于保存、更新或按 ID 读取；不是分组或标签筛选条件。 |
| `group` | 可选，最多 1024 个 UTF-8 字节 | 人脸所属分组。查询时精确匹配；`NULL` 或空串表示不限分组。 |
| `tag` | 可选，最多 1024 个 UTF-8 字节 | 应用自定义的业务标签。查询时精确匹配；`NULL` 或空串表示不限标签。 |

同时指定分组和标签时，两项都必须匹配；均不指定时搜索全库。

**按已有特征查库（`hiface_search_query_v1`）**

| 参数 | 范围与建议值 | 用途 |
|---|---|---|
| `top_k` | 必填，1–100，建议从 1 开始 | 最多返回的匹配数。 |
| `threshold` | 必填；建议 0.75–0.85，推荐 0.80 | 按已有特征查库的相似度下限。返回达到门槛的记录，无匹配为成功空结果；相机连续搜索使用下表的范围。 |

以 `hiface_session_search_start_v1` 启动连续搜索。使用同一单调时钟，逐帧执行 prepare → resolve → complete → read → destroy。

| `HiFaceSearchCameraConfigV1` 参数 | 范围与建议值 | 用途 |
|---|---|---|
| `multi_face` | 0 或 1，推荐 0 | 0 为单人搜索，只处理最大人脸；1 为多人搜索，按 `max_faces` 限制处理人数。 |
| `need_liveness` | 0 或 1，单人推荐 1 | 1 开启 RGB 静默活体，0 关闭；多人搜索必须为 0。 |
| `threshold` | 必填，0.75–0.85（含端点），推荐 0.80 | 相机连续搜索的身份匹配门槛；相似度大于等于该值才算身份匹配，活体仍须单独通过。 |
| `max_faces` | 1–5，多人可从 3 开始 | 多人模式每帧处理上限。单人仅处理最大脸。 |
| `interval_ms` | 0–3,000 ms，推荐 0 | 匹配成功后到下一轮搜索的等待间隔。 |
| `timeout_ms` | 1,000–3,000 ms，推荐 3,000 | 从首次选中人脸开始计算的单轮时限。 |

prepare 成功且返回非空 batch 后，才继续 resolve、complete、read；任一步失败仍销毁已创建的 batch。`end_reason == HIFACE_SEARCH_END_NONE` 表示本轮未结束，不能凭当前分数放行。`image_width` / `image_height` 是检测图尺寸，JPEG 回调中的宽高是输出图片尺寸，绘框时须换算。

先读 `end_reason`，再按 `has_similarity` 和 `has_liveness_score` 读取分数。活体拒绝时，即使相似度达标也不能放行。需要结束帧整图时，在释放批次或送入下一帧前调用 `hiface_session_search_copy_jpeg_v1`，在回调内复制图像数据。

人脸特征应原样保存。更换不兼容的模型时，从原照片重新提取特征并导入。应用负责取得用户同意，以及保护和删除照片与特征。

查询/读取结果用 `hiface_search_results_count_v1` 计数，再调用 `hiface_search_results_get_v1`；先填 `out_entry.struct_size`。其中字符串和特征指针只借用到结果销毁，需保留时先复制；只有 query 的 `score` 有相似度含义。`get` 缺失返回 `NOT_FOUND`，无匹配 query 返回 `OK` 加空结果；`contains` 和 `delete` 用输出值表示是否存在/实际删除。

## 错误处理与资源释放

| 状态 | 处理方式 |
|---|---|
| `HIFACE_STATUS_OK` | 调用成功。业务是否通过由 `outcome` 或 `end_reason` 决定。 |
| `HIFACE_STATUS_FRAME_SKIPPED` | 丢弃本帧，继续送入最新帧。 |
| `HIFACE_STATUS_BUSY` | 先结束冲突的会话流程再重试。初始化遇到该状态时释放未完成的会话，稍后重试。 |
| `HIFACE_STATUS_INVALID_ARGUMENT` | 检查结构体大小、版本、参数和缓冲区。 |
| `HIFACE_STATUS_RESOURCE_EXHAUSTED` | 减少并发任务并检查内存、磁盘和容量，处理后再重试。 |
| `HIFACE_STATUS_DATABASE_ERROR` | 检查人脸库路径、权限及存储状态；保留原数据，避免自动删库。 |
| `HIFACE_STATUS_INTERNAL_ERROR` | 停止本次请求，记录 SDK 版本及错误码并联系支持。 |
| `HIFACE_STATUS_MODEL_LOAD_FAILED` | 检查模型加载报告及所需能力的初始化结果。 |
| `HIFACE_STATUS_LICENSE_EXPIRED` | 核对授权有效期，必要时联系 SDK 支持。 |

在工作线程串行调用同一个会话。关闭前等待在途调用结束，并在结果销毁前复制需要保留的数据。用对应的 SDK 函数销毁搜索结果、批次和会话，关闭数据库。缺少 DLL 或遇到 `0xc000007b` 时，检查程序架构和 x64 DLL 是否齐全。

| 资源 | 对应释放入口 |
|---|---|
| `HiFaceSearchResultsHandle` | `hiface_search_results_destroy_v1` |
| `HiFaceSearchBatchHandle` | `hiface_search_batch_destroy_v1` |
| `HiFaceSearchDatabaseHandle` | `hiface_search_close_v1` |
| `HiFaceSessionHandle` | `hiface_session_destroy_v1` |

SDK 创建的句柄不可用 `free/delete` 释放。JPEG 回调的字节只在回调期间有效，返回前复制；回调不得抛出 C++ 异常或销毁正在借用的 session/batch。

当前模型不支持 12 周岁以下儿童人脸识别，不能用于金融场景。分发时保留许可及附带声明。
