#ifndef HIFACE_C_API_H
#define HIFACE_C_API_H

/*
 * HiFace 跨平台 C ABI。当前只保留完整的首发 V1 基线。
 *
 * 坐标与有效性契约：
 *   1. 所有人脸坐标是**左上角** x/y 加宽高，不是中心点，位于旋转后、未镜像的图像空间。
 *   2. pose_valid 门的是**平滑后**的头姿，不是单帧 PnP 解算的 valid。
 *   3. metrics_valid 与 mesh_valid 是两个独立标志：一张脸可以有完整可信的 mesh，
 *      同时 EAR/MAR 因几何退化而无效。不要用其中一个推断另一个。
 *
 * 本文件只描述**形状与调用**（结构体、函数、所有权）。共用的具名常量与枚举值在
 * hiface_contract_v1.h，由 core/abi/contract.json 生成 —— 改数值改那份契约。
 * ABI 枚举类型固定为 int32_t，不使用实现决定宽度的 C enum。
 *
 * 带 struct_size 的结构体以 HIFACE_*_V1_MIN_SIZE 冻结 V1 前缀。调用方应把它设置为
 * sizeof(自身编译时的结构体)；被调方接受不小于冻结前缀的值并忽略未知尾部。以后只能在尾部
 * 追加字段，而且访问新增字段前必须先检查 struct_size，不能增删、重排或改写现有字段。
 *
 * 线程安全（ABI 决策 1）：同一个 session 上的所有函数调用都由实现内部串行化，
 * 可以从多个线程调用。唯一例外是 hiface_session_destroy_v1 —— 见其说明。
 */

#include <stddef.h>
#include <stdint.h>

/* ABI 的共用具名常量与枚举由 core/abi/contract.json 生成。搜索字段的取值见下方结构说明。 */
#include "hiface/hiface_contract_v1.h"

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  if defined(HIFACE_C_API_STATIC)
#    define HIFACE_API
#  elif defined(HIFACE_C_API_BUILD)
#    define HIFACE_API __declspec(dllexport)
#  else
#    define HIFACE_API __declspec(dllimport)
#  endif
#  define HIFACE_CALL __cdecl
#elif defined(__GNUC__)
#  define HIFACE_API __attribute__((visibility("default")))
#  define HIFACE_CALL
#else
#  define HIFACE_API
#  define HIFACE_CALL
#endif

#if defined(_MSC_VER) || defined(__clang__) || defined(__GNUC__)
#  pragma pack(push, 8)
#endif

typedef struct HiFaceSessionOpaque* HiFaceSessionHandle;

/* 人脸库独立于推理 session：打开、CRUD、搜索均不加载或初始化任何模型。 */
typedef struct HiFaceSearchDatabaseOpaque* HiFaceSearchDatabaseHandle;
typedef struct HiFaceSearchResultsOpaque* HiFaceSearchResultsHandle;

/** 读取结果中的元数据和解码向量；写入使用 HiFaceSearchFeatureEntryV1。 */
typedef struct HiFaceSearchEntryV1 {
    uint32_t struct_size;
    /** 非空 UTF-8，最多 HIFACE_SEARCH_MAX_TEXT_BYTES 字节。 */
    const char* face_id;
    /** NULL 与空串统一保存空串，表示未设置标签/分组。 */
    const char* tag;
    const char* group;
    const float* embedding;
    uint32_t embedding_count;
    /** Unix epoch 毫秒；写入为 0 时由 core 填当前时间，负数非法。 */
    int64_t update_time_ms;
    /** 完整读取/搜索为原始 HF1；轻量 list/list_recent 为 NULL/0。 */
    const char* feature_text;
    uint32_t feature_text_length;
    const char* feature_space_id;
} HiFaceSearchEntryV1;

/** 写入使用原始 HF1 文本，保留其中的 Q7 payload，不再解码后重新量化。 */
typedef struct HiFaceSearchFeatureEntryV1 {
    uint32_t struct_size;
    /** 非空 UTF-8，最多 HIFACE_SEARCH_MAX_TEXT_BYTES 字节。 */
    const char* face_id;
    /** NULL 与空串统一保存空串；非空时遵循搜索文本字节上限。 */
    const char* tag;
    const char* group;
    /** 精确 HIFACE_FEATURE_TEXT_LENGTH 字符；文本与成员仅借用到写入返回。 */
    const char* feature_text;
    uint32_t feature_text_length;
    /** Unix epoch 毫秒；0 由 Core 填当前时间，负数拒绝。 */
    int64_t update_time_ms;
    /** 必须是 HIFACE_FEATURE_SPACE_ID；HF1 本身不能证明模型兼容。 */
    const char* feature_space_id;
} HiFaceSearchFeatureEntryV1;

#if UINTPTR_MAX == UINT64_MAX
#  define HIFACE_SEARCH_ENTRY_V1_MIN_SIZE 80u
#  define HIFACE_SEARCH_FEATURE_ENTRY_V1_MIN_SIZE 64u
#elif UINTPTR_MAX == UINT32_MAX
#  define HIFACE_SEARCH_ENTRY_V1_MIN_SIZE 48u
#  define HIFACE_SEARCH_FEATURE_ENTRY_V1_MIN_SIZE 40u
#endif

/**
 * 打开/新建 SDK 专用 SQLite 库，只接受 SDK 自身 schema；path 是非空 UTF-8 文件路径。
 * 表字段为 faceID/tag/group/embedding/updateTime；embedding 是 HF1 原始 450 字节 Q7 BLOB。
 * 读取/预热时恢复为 512 维 Float32；保存 HF1 不引入再次量化，搜索算法与分数定义保持一致。
 * 单库最多 HIFACE_SEARCH_MAX_ENTRIES 条，使用当前 HiFace 特征空间；其他模型的同维度特征不能混用。
 * 文件使用普通 SQLite，不提供数据库加密。父目录由宿主创建，建议应用私有目录。
 * 同一 handle 的操作内部串行化；与推理 session 无共享锁。所有操作同步，应在工作线程调用。
 * 失败时 *out_database 为 NULL；已有非本 SDK 库或较新版本拒绝打开，不覆盖或自动迁移。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_open_v1(
        const char* path, HiFaceSearchDatabaseHandle* out_database);
/** 关闭并擦除内存特征缓存。NULL 安全；销毁前宿主必须停止对此 handle 的并发调用。 */
HIFACE_API void HIFACE_CALL hiface_search_close_v1(HiFaceSearchDatabaseHandle database);
/**
 * 原子批量新增；任何重复 ID（含批内重复）使整批以 ALREADY_EXISTS 回滚。
 * count 为 1..HIFACE_SEARCH_MAX_BATCH_ENTRIES；entries 及成员仅借用到返回。
 * NULL tag/group 写为空串；各批独立提交。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_insert_v1(
        HiFaceSearchDatabaseHandle database, const HiFaceSearchFeatureEntryV1* const* entries, uint32_t count);

/**
 * 原子批量 upsert，faceID 为全库主键，同 ID 最后一次输入生效。任一失败整批回滚。
 * entries 是结构体指针数组，输入及成员仅借用到返回，count 为 1..HIFACE_SEARCH_MAX_BATCH_ENTRIES。
 * NULL tag/group 写为空串；大库分批导入、各批独立提交，全部完成后按实际 group/tag 范围 warm_up 一次。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_upsert_v1(
        HiFaceSearchDatabaseHandle database, const HiFaceSearchFeatureEntryV1* const* entries,
        uint32_t count);
/** 找不到返回 NOT_FOUND；失败时 *out_results 为 NULL。成功结果持有一条独立记录。 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_get_v1(
        HiFaceSearchDatabaseHandle database, const char* face_id, HiFaceSearchResultsHandle* out_results);
/** 仅查主键，不读取或解码特征；不存在仍成功并返回 0。 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_contains_v1(
        HiFaceSearchDatabaseHandle database, const char* face_id, uint32_t* out_exists);
/** 原子更新元数据；NULL 保留原字段、空串清空；至少提供 group/tag 之一。0 时间取当前时间。 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_update_metadata_v1(
        HiFaceSearchDatabaseHandle database, const char* face_id, const char* group,
        const char* tag, int64_t update_time_ms);
/** 删除不存在的 ID 也是成功，*out_deleted 为 0；已有记录删除后为 1。 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_delete_v1(
        HiFaceSearchDatabaseHandle database, const char* face_id, uint64_t* out_deleted);
/** 过滤参数 NULL 或空串均表示不限；非空字符串精确匹配，两个条件为 AND。 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_count_v1(
        HiFaceSearchDatabaseHandle database, const char* group, const char* tag, uint64_t* out_count);
/** 仅返回元数据，按 faceID 的 UTF-8 二进制顺序分页，limit 为 1..HIFACE_SEARCH_MAX_PAGE_SIZE。 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_list_v1(
        HiFaceSearchDatabaseHandle database, const char* group, const char* tag,
        uint32_t offset, uint32_t limit, HiFaceSearchResultsHandle* out_results);
/** 按 updateTime 从新到旧分页，同时间按 faceID 二进制升序稳定排列；过滤与 limit 规则同 list。 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_list_recent_v1(
        HiFaceSearchDatabaseHandle database, const char* group, const char* tag,
        uint32_t offset, uint32_t limit, HiFaceSearchResultsHandle* out_results);
/** 按 ID 分页读取完整原始 HF1，供批量导出/同步；过滤、limit 规则同 list。 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_list_features_v1(
        HiFaceSearchDatabaseHandle database, const char* group, const char* tag,
        uint32_t offset, uint32_t limit, HiFaceSearchResultsHandle* out_results);
/**
 * 仅加载指定 group/tag 范围，过滤语义同 count；每个句柄只缓存一个范围，切换时释放旧容量并重读。
 * 同范围的本句柄少量变动增量更新；外部提交自动重读当前范围。仅校验所选范围的特征。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_warm_up_v1(
        HiFaceSearchDatabaseHandle database, const char* group, const char* tag);
/**
 * 擦除并释放本句柄的特征缓存，尝试归还 SQLite 可释放的页缓存；保留连接和磁盘数据。
 * 适合内存压力/后台切换，由宿主在工作线程主动调用；下次 warm_up/search 自动重建缓存。
 * 已返回的结果仍独立有效；不关闭或重新初始化任何推理模型。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_release_memory_v1(HiFaceSearchDatabaseHandle database);
/**
 * 精确 1:N 搜索，分数与 hiface_feature_compare_v1 一致，threshold 为有限 [0,1]。
 * 返回 score >= threshold 的前 top_k 条（1..HIFACE_SEARCH_MAX_TOP_K）；无匹配为成功空结果。
 * 分数降序，同分按 faceID UTF-8 二进制升序；group/tag 过滤语义同 count。
 * 缓存只属于数据库，不加载模型、不改变相机待机节流。首次、切换 group/tag 或写后刷新可能有磁盘 I/O。
 * 查询自动准备与过滤条件一致的缓存；仅校验该范围内的特征，无筛选时校验全库。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_query_v1(
        HiFaceSearchDatabaseHandle database, const float* embedding, uint32_t embedding_count,
        const char* group, const char* tag, uint32_t top_k, float threshold,
        HiFaceSearchResultsHandle* out_results);
/** 不可变结果独立于 database 生命周期；NULL 返回 0。 */
HIFACE_API uint32_t HIFACE_CALL hiface_search_results_count_v1(HiFaceSearchResultsHandle results);
/**
 * out_entry.struct_size 必须有效。返回的字符串/特征指针借用到 results_destroy，宿主不得写入。
 * get/list 的 score 为 0，只有 query 的 score 有相似度含义。失败清零有效的输出字段。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_results_get_v1(
        HiFaceSearchResultsHandle results, uint32_t index, HiFaceSearchEntryV1* out_entry, float* out_score);
/** 释放结果并擦除特征；NULL 安全，销毁前须停止对此 results 的访问。 */
HIFACE_API void HIFACE_CALL hiface_search_results_destroy_v1(HiFaceSearchResultsHandle results);

typedef struct HiFacePlaneV1 {
    const uint8_t* data;
    size_t data_size;
    int32_t row_stride;
    /* y 平面必须为 1；u/v 平面必须使用相同的 pixel_stride。 */
    int32_t pixel_stride;
} HiFacePlaneV1;

typedef struct HiFaceYuv420FrameV1 {
    uint32_t struct_size;
    HiFacePlaneV1 y;
    HiFacePlaneV1 u;
    HiFacePlaneV1 v;
    /*
     * 必须是正偶数，且长边不超过 HIFACE_MAX_CAMERA_FRAME_LONG_SIDE、
     * 短边不超过 HIFACE_MAX_CAMERA_FRAME_SHORT_SIDE（横竖屏统一限制到 1080p）。
     */
    int32_t width;
    int32_t height;
    /* 只允许 0、90、180、270。 */
    int32_t rotation_degrees;
    /**
     * YUV 数值范围与颜色矩阵。两者都是必填协议，不允许由 core 按平台、尺寸或相机来源猜测。
     * 检测、468 点裁剪和最终 RGBA 抓拍使用同一份颜色定义。
     */
    HiFaceYuvRangeV1 range;
    HiFaceYuvMatrixV1 matrix;
} HiFaceYuv420FrameV1;

#if UINTPTR_MAX == UINT64_MAX
#  define HIFACE_YUV420_FRAME_V1_MIN_SIZE 100u
#elif UINTPTR_MAX == UINT32_MAX
#  define HIFACE_YUV420_FRAME_V1_MIN_SIZE 72u
#else
#  error "HiFace C ABI supports only 32-bit and 64-bit pointer models"
#endif

typedef struct HiFacePointV1 {
    float x;
    float y;
} HiFacePointV1;

HIFACE_API uint32_t HIFACE_CALL hiface_get_api_version_v1(void);

/**
 * 进程级 NCNN 运行时配置。必须在首次创建 session 前调用；同一配置可重复调用。
 * 首个 session 创建后再请求不同配置返回 INVALID_STATE，避免把进程级 SimpleOMP 状态
 * 伪装成互相独立的 session 参数。
 */
typedef struct HiFaceRuntimeConfigV1 {
    uint32_t struct_size;
    uint32_t api_version;
    /* 当前接受 0（按物理大核数自动选择）、2、4。 */
    int32_t cpu_threads;
    /* 必须为 0。 */
    uint32_t reserved0;
} HiFaceRuntimeConfigV1;

#define HIFACE_RUNTIME_CONFIG_V1_MIN_SIZE 16u

HIFACE_API HiFaceStatus HIFACE_CALL hiface_runtime_configure_v1(
        const HiFaceRuntimeConfigV1* config);

/**
 * 销毁 Session。调用前必须停止新任务，并保证没有任何线程正在或即将使用该 handle；本函数
 * 不是运行中推理的取消接口。平台 Wrapper 应先关闭回调/任务准入，再把 destroy 排到其串行
 * Native worker 的队尾。返回后 handle 立即失效。
 *
 * session mutex 只串行化存活句柄上的调用，销毁与在途调用的互斥由平台绑定保证。
 * Android 的 EngineHost 通过 nativeGate 串行化 Native 调用，并在关闭时禁止新任务、
 * 等待在途调用退出后释放；EngineHostNativeSessionTest 验证该生命周期契约。
 * iOS/鸿蒙绑定须提供等价保证。
 */
HIFACE_API void HIFACE_CALL hiface_session_destroy_v1(HiFaceSessionHandle session);

/**
 * V1 session 配置。
 *
 * enable_feature / enable_landmark 决定这个 session 可加载哪些能力：关闭的能力不分配
 * 后端对象，也不接受对应模型。基础就绪只要求 check；landmarks、feature 和
 * silent_s/silent_m 可在业务需要时延迟推入（见 hiface_session_load_model_bundle_v1）。
 *
 * CPU 线程上限属于进程级运行时配置，见 hiface_runtime_configure_v1；这里不再重复表达。
 */
typedef struct HiFaceConfigV1 {
    /* 调用方必须设置为 sizeof(HiFaceConfigV1)。 */
    uint32_t struct_size;
    /* 必须 >= HIFACE_C_API_VERSION_V1。 */
    uint32_t api_version;
    /**
     * GPU 决策由平台层做出后传入（ABI 决策 4）；公共 core 不判断具体平台和驱动是否适合启用。
     * 请求 GPU 时若运行时不可用或单个模型的 GPU 加载失败，该模型回落 CPU，最终后端通过
     * HiFaceModelLoadReportV1 回报。
     */
    HiFaceComputeMode compute_mode;
    /**
     * 非 0 表示需要特征后端：用于 extract_feature、capture_face 的特征/预览
     * 输出以及 align_preview。预览对齐只复用该后端的对齐能力，不运行特征模型。
     */
    uint32_t enable_feature;
    /* 非 0 表示需要 468 点、EAR/MAR 与头姿。 */
    uint32_t enable_landmark;
    /* 0.05..0.45，推荐 0.18。enable_landmark 为 0 时忽略。 */
    float eye_closed_ear_threshold;
    /* 0.05..0.80，推荐 0.22。enable_landmark 为 0 时忽略。 */
    float mouth_open_mar_threshold;
} HiFaceConfigV1;

#define HIFACE_CONFIG_V1_MIN_SIZE 28u

/**
 * 单次检测请求。它只描述调用方希望收到的检测结果，不限制同帧业务流程的内部分析。
 * 活跃流程会自动要求详细关键点；拒绝多人时也会至少检测两张脸，但超出 max_faces 的内部
 * 结果不会写入公开帧结果。
 */
typedef struct HiFaceDetectionRequestV1 {
    uint32_t struct_size;
    uint32_t api_version;
    /* 取值 1..HIFACE_MAX_FACES；只限制本次调用写入 out_result 的人脸数。 */
    uint32_t max_faces;
    /* 只能为 0 或 1。非 0 时返回 468 点与头姿；检测模型固定五点始终返回。 */
    uint32_t detailed_landmarks;
} HiFaceDetectionRequestV1;

#define HIFACE_DETECTION_REQUEST_V1_MIN_SIZE 16u

/**
 * 完整逐模型加载报告。状态值是稳定的 HiFaceModelLoadStateV1，不暴露 NCNN 或解密器原始返回码；
 * 未请求/未启用与加载成功是两个不同状态。
 */
typedef struct HiFaceModelLoadReportV1 {
    uint32_t struct_size;
    HiFaceModelLoadStateV1 detector;
    HiFaceModelLoadStateV1 feature;
    HiFaceModelLoadStateV1 landmarks;
    HiFaceModelLoadStateV1 silent_liveness_s;
    HiFaceModelLoadStateV1 silent_liveness_m;
    /* 非 0 表示请求了 GPU，但至少一个模型实际回落到 CPU 执行。 */
    uint32_t gpu_fell_back;
    /* 逐模型报告最终实际执行后端。 */
    HiFaceModelBackendV1 detector_backend;
    HiFaceModelBackendV1 feature_backend;
    HiFaceModelBackendV1 landmarks_backend;
    HiFaceModelBackendV1 silent_liveness_s_backend;
    HiFaceModelBackendV1 silent_liveness_m_backend;
} HiFaceModelLoadReportV1;

#define HIFACE_MODEL_LOAD_REPORT_V1_MIN_SIZE 48u

/** Face Mesh 顶点，位于旋转后、未镜像的图像像素空间；z 是模型相对深度。 */
typedef struct HiFaceMeshPointV1 {
    float x;
    float y;
    float z;
} HiFaceMeshPointV1;

/** 一张脸的完整结果。三个有效性标志互相独立，见头部契约第 3 条。 */
typedef struct HiFaceFaceV1 {
    /* 左上角与宽高，旋转后、未镜像的图像像素空间。 */
    float x;
    float y;
    float width;
    float height;
    float confidence;
    /* 检测模型的固定 5 点：左眼、右眼、鼻尖、左嘴角、右嘴角。 */
    HiFacePointV1 landmarks[HIFACE_MAX_LANDMARKS];

    /* 平滑后的头姿是否可用；为 0 时 pitch/yaw/roll 无意义。 */
    uint32_t pose_valid;
    float pitch;
    float yaw;
    float roll;

    /* EAR/MAR 与闭眼/张嘴判定是否可用。 */
    uint32_t metrics_valid;
    float presence_score;
    float left_ear;
    float right_ear;
    float mar;
    uint32_t left_eye_closed;
    uint32_t right_eye_closed;
    uint32_t mouth_open;

    /* 468 点是否可用。可以为 1 而 metrics_valid 为 0。 */
    uint32_t mesh_valid;
    /**
     * 借用 session 内部缓冲（ABI 决策 2）：避免每帧把 468*3 个 float 再拷一遍。
     * 仅在下一次针对同一 session 的调用之前有效，session 销毁后立即失效。
     * 需要留存必须自行复制。mesh_valid 为 0 时为 NULL。
     */
    const HiFaceMeshPointV1* mesh;
    uint32_t mesh_count;
} HiFaceFaceV1;

/** 帧结果。faces 由调用方预分配（ABI 决策 2），mesh 除外。 */
typedef struct HiFaceFrameResultV1 {
    uint32_t struct_size;
    HiFaceFaceV1* faces;
    uint32_t capacity;
    uint32_t count;
    int32_t image_width;
    int32_t image_height;
    /**
     * 本帧序号，每次成功处理递增，从 1 开始；失败时为 0。
     * 只用于识别帧次序；流程内抓拍由 core 在同一次相机帧调用中完成。
     */
    uint64_t frame_id;
} HiFaceFrameResultV1;

#if UINTPTR_MAX == UINT64_MAX
#  define HIFACE_FRAME_RESULT_V1_MIN_SIZE 40u
#else
#  define HIFACE_FRAME_RESULT_V1_MIN_SIZE 32u
#endif

/**
 * 创建 session。失败时 *out_session 被置为 NULL，不存在半初始化对象。
 * 创建后必须按需加载模型并调用 hiface_session_prepare_loaded_models_v1 才能送帧。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_create_v1(
        const HiFaceConfigV1* config,
        HiFaceSessionHandle* out_session);

/**
 * 推入一份 BPHFM1 密文模型包。每个 .bphfm 文件固定包含 param、bin 两份 HFM2 认证密文；
 * model_id 是固定宽度枚举，具体文件名归平台所有
 * （Android 的 assets 命名、iOS 的 bundle 资源名、鸿蒙的 rawfile 名都不进 ABI）。
 *
 * 一次一个（ABI 决策 3）：调用方只需在本次调用期间保持字节有效，因此可以复用同一块
 * 缓冲逐个推入，任一时刻只在内存里持有一份模型密文。调用顺序不限。
 * 对未启用能力的 model_id 返回 INVALID_STATE。基础模型就绪后仍可按需推入尚未加载的
 * landmarks / feature / silent-liveness 模型；已加载 model_id 的重复推入是幂等成功，不替换权重，
 * 也不清除相机的无人脸待机计时。
 * out_report 可为 NULL；非 NULL 时按模型回填稳定状态，跨多次调用累积。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_load_model_bundle_v1(
        HiFaceSessionHandle session,
        HiFaceModelIdV1 model_id,
        const uint8_t* encrypted_bundle_data,
        size_t encrypted_bundle_size,
        HiFaceModelLoadReportV1* out_report);

/**
 * 准备当前已加载模型：首次调用会校验检测器是否齐备，
 * 成功后 session 可送帧；随后可继续按能力加载关键点、特征与静默活体模型。
 * 本函数不运行模型推理；首次实际送帧或采样自然承担 NCNN lazy allocation。重复调用幂等，
 * 已就绪时再次准备不会清除相机的无人脸待机计时。
 * 缺模型时返回 MODEL_LOAD_FAILED，session 保持不可用，可以补推后重试。
 * out_report 可为 NULL。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_prepare_loaded_models_v1(
        HiFaceSessionHandle session,
        HiFaceModelLoadReportV1* out_report);

/**
 * 处理一帧静态 RGBA8888（内存中的 R,G,B,A 字节序）。
 * 用于静态图检测：调用方不必先在自己那侧做 RGBA->YUV 往返。方向由调用方在传入前处理，
 * 因此没有 rotation 参数；输出坐标就在传入图像的像素空间里。
 *
 * **与实时链路完全隔离**：使用独立缓冲与姿态缓存，不打断相机的跨帧历史。
 * 因此返回结果的 frame_id 恒为 0；如需录入，调用方本来就握着原始像素，
 * 可通过 capture_rgba 一次完成最大脸选择与采集。
 * width/height 必须是 1..HIFACE_MAX_IMAGE_DIMENSION 内的偶数。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_process_rgba_v1(
        HiFaceSessionHandle session,
        const uint8_t* rgba,
        size_t rgba_size,
        int32_t width,
        int32_t height,
        const HiFaceDetectionRequestV1* request,
        HiFaceFrameResultV1* out_result);

/**
 * 按五点对齐并提取 512 维 L2 归一化特征。landmarks 必须是 10 个 float
 * （5 组 x, y），坐标位于传入图像自身的像素空间。
 * out_feature_count 必须等于 HIFACE_FACE_FEATURE_DIMENSION。
 * 需要 enable_feature；否则返回 INVALID_STATE。
 * width/height 必须在 1..HIFACE_MAX_IMAGE_DIMENSION 内；NV21 还必须是偶数。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_extract_feature_v1(
        HiFaceSessionHandle session,
        const uint8_t* image,
        size_t image_size,
        int32_t width,
        int32_t height,
        HiFaceImageFormatV1 format,
        const float* landmarks,
        size_t landmarks_count,
        float* out_feature,
        size_t out_feature_count);

/**
 * 从静态 RGBA8888 图片选择面积最大的人脸并提取特征，可选生成对齐预览。
 * 无人脸返回 IMAGE_NO_FACE；最大脸宽或高小于 HIFACE_FEATURE_MIN_FACE_SIZE_PIXELS
 * 返回 IMAGE_FACE_TOO_SMALL，恰好达到阈值可通过。尺寸按输入像素计算，不放大小脸。
 * 多人脸不报错，不执行活体或头姿门禁。需已加载检测和特征模型。
 * width/height 必须是 2..HIFACE_MAX_IMAGE_DIMENSION 内的偶数，方向由调用方处理。
 * out_feature_count 必须为 HIFACE_FACE_FEATURE_DIMENSION。
 * 只需特征时传 out_preview_rgba=NULL、out_preview_size=0，不生成预览；否则缓冲至少
 * HIFACE_ALIGNED_PREVIEW_RGBA_BYTES 字节。有效输出缓冲在失败时清零。
 * 检测和提取在同一 Session 锁内完成，不改变相机跨帧状态。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_capture_rgba_v1(
        HiFaceSessionHandle session,
        const uint8_t* rgba, size_t rgba_size, int32_t width, int32_t height,
        float* out_feature, size_t out_feature_count,
        uint8_t* out_preview_rgba, size_t out_preview_size);

/**
 * 生成 333x333 RGBA 对齐预览，不运行特征模型，但依赖特征后端的对齐能力。
 * session 必须启用 enable_feature，否则返回 INVALID_STATE。输入固定 RGBA8888。
 * face_bounds 是 4 个 float：左上角 x、y 与宽、高。
 * out_size 必须至少为 333*333*4；out_side 可为 NULL，非 NULL 时回填边长。
 * width/height 必须在 1..HIFACE_MAX_IMAGE_DIMENSION 内，不要求偶数。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_align_preview_v1(
        HiFaceSessionHandle session,
        const uint8_t* rgba,
        size_t rgba_size,
        int32_t width,
        int32_t height,
        const float* landmarks,
        size_t landmarks_count,
        const float* face_bounds,
        size_t face_bounds_count,
        uint8_t* out_rgba,
        size_t out_size,
        int32_t* out_side);

/* ----------------------------- 统一人脸流程 ----------------------------- *
 * 引导采集、动作活体、动态验证与复合认证共用同一个状态机内核，mode 显式选择行为。
 * 动作集合上限、阶段/失败枚举与全部默认值见 hiface_contract_v1.h。
 * ----------------------------------------------------------------------- */

/**
 * 一次流程的配置。
 *
 * 全部时限取值 <= 0 表示该项停用，不是「立即失败」。引导采集把这些值及
 * final_capture_timeout_ms 置 0，得到「永不超时、只汇报状态」的行为。动作活体、动态验证和复合认证的
 * final_capture_timeout_ms 必须大于 0，保证最终阶段一定收口。
 */
typedef struct HiFaceFlowConfigV1 {
    uint32_t struct_size;
    uint32_t api_version;
    HiFaceFlowModeV1 mode;
    HiFaceFlowActionV1 actions[HIFACE_MAX_FACE_FLOW_ACTIONS];
    /* GUIDED_CAPTURE 必须为 0；其余模式允许为 0。 */
    uint32_t action_count;
    /* 单个动作的额度；整组总时限为它乘以动作数。 */
    int64_t action_timeout_ms;
    int64_t face_acquisition_timeout_ms;
    int64_t face_lost_timeout_ms;
    uint32_t multiple_faces_allowed;
    /* 固定后续 int64_t 在所有 32 位 ABI 上的偏移；必须为 0。 */
    uint32_t reserved0;
    int64_t multiple_faces_timeout_ms;
    int64_t final_capture_timeout_ms;
    int64_t frontal_hold_ms;
    /*
     * 这里曾有一个 require_behavior_metrics 开关。现在由 core 按待执行动作自行判定：
     * 只有眨眼和张嘴需要 EAR/MAR，其余阶段不再因指标缺失而整帧跳过。平台不需要、
     * 也不应该再表达这个选择。
     */
    /* 必须 > 0；动态验证最终阶段低于该值仍可采样。 */
    float min_face_size_pixels;
    /* 必须是 [0,1] 内有限值，包括不使用该值的其他 mode。 */
    float verification_threshold;
    /* FaceVerification/FaceAuthentication only. Borrowed for start() and securely copied. */
    const float* verification_reference;
    size_t verification_reference_count;
} HiFaceFlowConfigV1;

#if UINTPTR_MAX == UINT64_MAX
#  define HIFACE_FLOW_CONFIG_V1_MIN_SIZE 112u
#else
#  define HIFACE_FLOW_CONFIG_V1_MIN_SIZE 104u
#endif

/**
 * 一次原子相机帧调用产生的公开事件。采样、抓拍和比对命令全部留在 core 内部；平台只会
 * 看到进度、可复制的终态结果，或独立于检测结果的 flow 技术错误。
 */
typedef struct HiFaceFlowEventV1 {
    uint32_t struct_size;
    HiFaceFlowEventKindV1 kind;
    /* kind == ERROR 时是非 OK 的 HiFaceStatus；其他事件恒为 OK。 */
    HiFaceStatus flow_status;
    HiFaceFlowStageV1 stage;
    uint32_t has_action;
    HiFaceFlowActionV1 action;
    int32_t step_number;
    int32_t step_count;
} HiFaceFlowEventV1;

#define HIFACE_FLOW_EVENT_V1_MIN_SIZE 32u

/** 终态元数据。可选数据是否存在只能读 flags，不能从浮点零值推断。 */
typedef struct HiFaceFlowResultV1 {
    uint32_t struct_size;
    HiFaceFlowOutcomeV1 outcome;
    uint32_t flags;
    uint32_t reserved0;
    float liveness_score;
    float similarity;
    uint32_t preview_rgba_bytes;
    uint32_t feature_count;
} HiFaceFlowResultV1;

#define HIFACE_FLOW_RESULT_V1_MIN_SIZE 32u

#if defined(_MSC_VER) || defined(__clang__) || defined(__GNUC__)
#  pragma pack(pop)
#endif

/**
 * 开始一次流程；成功的重复调用会重置状态机，失败则保留原流程。
 * now_ms 必须是非负的单调时钟毫秒值；后续相机帧使用同一时钟源。
 * 后续实时送帧的公开检测请求不会限制流程：拒绝多人时 core 自动检查第二张脸，流程所需
 * 的详细关键点也会自动执行。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_face_flow_start_v1(
        HiFaceSessionHandle session,
        const HiFaceFlowConfigV1* config,
        int64_t now_ms);

/**
 * 唯一的实时 YUV 相机入口。在同一次 session 锁内完成检测，并在 flow 活跃时继续完成状态
 * 推进、本帧所需的静默活体、特征比对或抓拍。返回值只描述帧/检测；检测成功后发生的 flow
 * 技术错误通过 out_event 的 ERROR 事件返回，因此检测结果不会被一并丢弃。
 *
 * out_result 的容量不足时返回 RESOURCE_EXHAUSTED 且不会推进 flow，避免调用方收到失败
 * 返回却已经改变业务状态。
 * count == 0 且返回 OK 表示本帧确实没有人脸。now_ms 必须来自与 start 相同的单调时钟。
 * 无活动 flow、连续 HIFACE_IDLE_NO_FACE_TIMEOUT_MS 无人脸后，core 将分析开始间隔限制到
 * HIFACE_IDLE_FRAME_INTERVAL_MS（约 5 FPS）。跳帧返回 FRAME_SKIPPED，out_result 的
 * count/frame_id/尺寸为 0、out_event 为 NONE；不缓存输入或复用上一帧结果，不推进 flow。
 * 检出人脸、成功 start 或停止活动 flow 后清除待机计时；活动 flow 不节流，静态 RGBA 不受影响。
 * 进入 core 的检测失败、实际新增模型、首次就绪、模型加载失败以及至少 10 秒无相机输入会重置窗口。
 * 重复准备、重复加载已存在模型或清理已结束流程不会重置窗口。
 * FRAME_SKIPPED 是暂时跳帧，宿主释放当前输入并继续送入最新帧，不等待就绪或重试旧帧。
 * 输入长边最多 1920、短边最多 1080；静态图入口仍可使用 HIFACE_MAX_IMAGE_DIMENSION。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_process_camera_yuv420_v1(
        HiFaceSessionHandle session,
        const HiFaceYuv420FrameV1* frame,
        const HiFaceDetectionRequestV1* request,
        int64_t now_ms,
        HiFaceFrameResultV1* out_result,
        HiFaceFlowEventV1* out_event);

/**
 * 复制 RESULT_AVAILABLE 对应的终态。out_result 总会回填 flags 与所需长度；存在的输出缓冲
 * 必须达到对应固定长度，否则返回 RESOURCE_EXHAUSTED 且不复制任何敏感数据。没有 feature
 * 的流程允许 out_feature 为 NULL，没有 preview 的流程允许 out_preview_rgba 为 NULL。
 * 结果由 core 持有到 stop、下一次成功 start 或 session 销毁。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_face_flow_copy_result_v1(
        HiFaceSessionHandle session,
        HiFaceFlowResultV1* out_result,
        float* out_feature,
        size_t out_feature_count,
        uint8_t* out_preview_rgba,
        size_t out_preview_size);

/** 放弃当前流程并清零全部敏感中间数据；未在进行中时也是安全的，且不重置待机计时。 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_face_flow_stop_v1(HiFaceSessionHandle session);

typedef void (HIFACE_CALL *HiFaceLogCallback)(
        HiFaceLogLevel level, const char* tag, const char* message, void* user_data);

/**
 * 把 core 的日志接到宿主平台的日志系统。**每个平台绑定都必须在创建任何 session 之前
 * 调用一次**，否则 core 的日志会落到 fprintf(stderr)：Android 直接丢弃，
 * iOS 也不会进统一日志。编排下沉之后，全部初始化诊断与逐帧计时都在 core 里产生，
 * 少了这一步就等于没有日志。
 *
 * 传 NULL 恢复默认的 stderr 行为。回调可能从任意线程调用，实现必须自己保证线程安全。
 * 这是进程级全局设置，不属于任何 session。
 */
HIFACE_API void HIFACE_CALL hiface_set_log_callback_v1(
        HiFaceLogCallback callback,
        void* user_data);

/**
 * 1:1 相似度。feature_count 必须为 HIFACE_FACE_FEATURE_DIMENSION，两条特征都必须
 * 有限且非零向量，否则返回 INVALID_ARGUMENT 且 *out_score 置 0。
 *
 * 输出是把原始余弦从 [-1, 1] 线性映射后的 [0, 1] 分数 —— 注意阈值换算：
 * 分数 0.80 对应原始余弦 0.60。这个函数不依赖 session，也不需要任何模型。
 * 三端必须共用它而不是各自实现，否则同一对人脸会在不同平台得到不同分数。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_feature_compare_v1(
        const float* probe,
        const float* reference,
        size_t feature_count,
        float* out_score);

/* ---------------------------- 特征文本形式 ------------------------------- *
 * HF1 文本格式、长度与前缀都是 ABI 的一部分，定义在 hiface_contract_v1.h。
 * ------------------------------------------------------------------------- */

/**
 * 把 512 维非零有限特征按方向归一化、量化并编码为 HF1 文本。
 * out_text 由调用方预分配，容量必须 >= HIFACE_FEATURE_TEXT_BUFFER_SIZE；
 * 成功时写入 604 个字符加结尾 '\0'，失败时写入空字符串并返回 INVALID_ARGUMENT。
 * 本函数不依赖 session，也不需要任何模型。
 *
 * 注意：HF1 文本**不是规范形式**。解码再编码会重新量化和舍入，字符串可能不同。
 * 数据库完整读取直接返回原始 Q7 的 HF1，不使用本函数重编码。
 * 因此宿主不能用字符串相等来判断「是不是同一条特征」，必须解码后用 hiface_feature_compare_v1。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_feature_encode_text_v1(
        const float* feature,
        size_t feature_count,
        char* out_text,
        size_t out_text_capacity);

/**
 * 解析 HF1 文本并输出 L2 归一化的 512 维特征。text_length 必须是精确长度，
 * 实现不依赖结尾 '\0'。out_feature_count 必须等于 HIFACE_FACE_FEATURE_DIMENSION。
 * 任何格式、长度、字母表或 payload 错误都返回 INVALID_ARGUMENT，并把输出清零 ——
 * 不区分具体原因是有意的：区分会把「这条文本哪里不合法」变成可探测的信息。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_feature_decode_text_v1(
        const char* text,
        size_t text_length,
        float* out_feature,
        size_t out_feature_count);


/** Lock-free local write revision, for change notification only. Remote connections are polled separately. */
HIFACE_API uint64_t HIFACE_CALL hiface_search_local_revision_v1(HiFaceSearchDatabaseHandle database);

/* Camera search v1.
 * Calls borrow session/database; destroy them only after in-flight calls finish.
 * One batch at a time: prepare -> read detection geometry -> resolve (outside engine lock)
 * -> complete -> read final state -> destroy. Stop invalidates outstanding batches.
 * Destroying an unfinished batch releases admission; it is safe after Session destruction.
 * Continuous search admits at most one frame per 100 ms; skipped frames return FRAME_SKIPPED.
 * All timestamps use a monotonic millisecond clock; resolve includes elapsed I/O.
 * Bounds are rotated, unmirrored image pixels. No cross-frame identity tracking.
 */
typedef struct HiFaceSearchBatchOpaque* HiFaceSearchBatchHandle;
typedef struct HiFaceSearchCameraConfigV1 {
    uint32_t struct_size;
    uint32_t multi_face; /* 0 = 1:N, 1 = M:N; neither mode checks head pose */
    uint32_t need_liveness; /* only 1:N; single-frame S/M silent liveness */
    uint32_t max_faces; /* 1..5; single mode always selects one */
    float threshold; /* finite [0.75, 0.85], inclusive match */
    uint32_t interval_ms; /* success only, 0..3000; default 0 */
    uint32_t timeout_ms; /* 1000..3000; default 3000 */
    const char* group; /* null/empty = unrestricted, otherwise exact */
    const char* tag;
} HiFaceSearchCameraConfigV1;
typedef struct HiFaceSearchCameraFaceV1 {
    float x, y, width, height;
    uint32_t has_similarity;
    float similarity;
    uint32_t threshold_passed; /* similarity only; SPOOF_DETECTED still rejects the overall result */
    char face_id[HIFACE_SEARCH_MAX_TEXT_BYTES + 1u]; /* empty unless similarity passes; may exist with liveness rejection; UTF-8 */
    char group[HIFACE_SEARCH_MAX_TEXT_BYTES + 1u];
    char tag[HIFACE_SEARCH_MAX_TEXT_BYTES + 1u];
    /* Detection adapter data; not repeated in the public Android search DTO. */
    float confidence;
    float landmarks[HIFACE_FACE_LANDMARK_FLOAT_COUNT];
} HiFaceSearchCameraFaceV1;
typedef struct HiFaceSearchCameraResultV1 {
    uint32_t struct_size;
    uint64_t frame_id;
    uint32_t image_width, image_height;
    uint32_t face_count, detected_count;
    /* HiFaceSearchEndReasonV1; HIFACE_SEARCH_END_NONE means the round is still in progress. */
    uint32_t end_reason;
    /* HiFaceSearchStageV1; SEARCHING includes optional liveness. */
    uint32_t progress;
    /* 1 only for a finite same-batch S/M mean completed before the deadline.
       0 when disabled, missing, invalid or late; never inherits another batch's score. */
    uint32_t has_liveness_score;
    float liveness_score; /* [0,1] when present, including zero; otherwise zero */
    HiFaceSearchCameraFaceV1 faces[HIFACE_SEARCH_MAX_FACES];
} HiFaceSearchCameraResultV1;
/**
 * 开始连续搜索。连续 HIFACE_IDLE_NO_FACE_TIMEOUT_MS 无人脸后，Core
 * 自动把分析间隔限制到 HIFACE_IDLE_FRAME_INTERVAL_MS（约 5 FPS）；
 * 重新检出人脸后立即恢复。无人脸低功耗是固定行为，不需要额外配置。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_search_start_v1(
        HiFaceSessionHandle session, const HiFaceSearchCameraConfigV1* config);
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_search_stop_v1(HiFaceSessionHandle session);
/* Detects even with an empty gallery; rechecks filtered count once per second or immediately
 * when this database handle reports a new local revision. */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_search_prepare_yuv420_v1(
        HiFaceSessionHandle session, HiFaceSearchDatabaseHandle database,
        const HiFaceYuv420FrameV1* frame, int64_t now_ms, HiFaceSearchBatchHandle* out_batch);
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_batch_resolve_v1(
        HiFaceSearchBatchHandle batch, HiFaceSearchDatabaseHandle database);
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_search_complete_v1(
        HiFaceSessionHandle session, HiFaceSearchBatchHandle batch);
HIFACE_API HiFaceStatus HIFACE_CALL hiface_search_batch_read_v1(
        HiFaceSearchBatchHandle batch, HiFaceSearchCameraResultV1* out_result);
HIFACE_API void HIFACE_CALL hiface_search_batch_destroy_v1(HiFaceSearchBatchHandle batch);

#ifdef __cplusplus
}
#endif

#endif /* HIFACE_C_API_H */
