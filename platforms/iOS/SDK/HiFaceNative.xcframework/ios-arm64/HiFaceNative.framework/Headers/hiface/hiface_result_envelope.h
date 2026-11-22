#ifndef HIFACE_RESULT_ENVELOPE_H
#define HIFACE_RESULT_ENVELOPE_H

#include "hiface_c_api.h"

#ifdef __cplusplus
extern "C" {
#endif

#define HIFACE_RESULT_ENVELOPE_SESSION_ID_MAX_BYTES 22u
#define HIFACE_RESULT_ENVELOPE_PUBLIC_KEY_MAX_BYTES 768u
/* 342 个无填充 Base64URL 字符及结尾 NUL。 */
#define HIFACE_RESULT_ENVELOPE_BUFFER_BYTES 343u

/**
 * 可选加密的流程启动。两段字符串均为 ASCII，长度不含结尾 NUL，调用期间借用。
 * 两段均为 NULL 且长度均为 0 时等同于原接口。启用时仅支持活体、验证和认证。
 * session_id 为 16 字节随机编号的无填充 Base64URL 表示（Demo 可用 yourSessionId）。
 * public_key 为 RSA-2048 SPKI DER 的无填充 Base64URL 表示。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_face_flow_start_with_envelope_v1(
        HiFaceSessionHandle session,
        const HiFaceFlowConfigV1* config,
        int64_t now_ms,
        const char* session_id,
        size_t session_id_size,
        const char* public_key,
        size_t public_key_size);

/**
 * 同时复制同一轮的终态与结果密文。开启加密时须提供至少
 * HIFACE_RESULT_ENVELOPE_BUFFER_BYTES 字节的缓冲区，重复读取返回同一份密文。
 * 未开启时字符串为空（允许 NULL / 0）。启用后须用本入口读取结果，封装失败不会返回明文。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_session_face_flow_copy_result_with_envelope_v1(
        HiFaceSessionHandle session,
        HiFaceFlowResultV1* out_result,
        float* out_feature,
        size_t out_feature_count,
        uint8_t* out_preview_rgba,
        size_t out_preview_size,
        char* out_envelope,
        size_t out_envelope_size);

#ifdef __cplusplus
}
#endif

#endif
