#ifndef HIFACE_WINDOWS_H
#define HIFACE_WINDOWS_H
#include "hiface/hiface_c_api.h"
#ifdef __cplusplus
extern "C" {
#endif
/** Load one built-in model into a session. No model files or downloads are required.
 * Call prepare_loaded_models after loading the capabilities your application uses.
 * Initialize out_report->struct_size before each call. Load only required model IDs,
 * then prepare once before processing frames; errors remain the common C API statuses.
 * The session is owned by the caller and must be accessed serially on its worker.
 * 先设置报告 struct_size，按需加载能力后执行 prepare，再开始处理帧；
 * session 由调用方持有，同一会话在工作线程串行调用。
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_windows_session_load_model_v1(
        HiFaceSessionHandle session, HiFaceModelIdV1 model_id,
        HiFaceModelLoadReportV1* out_report);
/** Export verified product information as UTF-8 JSON; does not grant access.
 * Output requires room for the terminating NUL; out_size excludes that NUL.
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_windows_license_profile_v1(
        char* output, size_t capacity, size_t* out_size);
#ifdef __cplusplus
}
#endif
#endif
