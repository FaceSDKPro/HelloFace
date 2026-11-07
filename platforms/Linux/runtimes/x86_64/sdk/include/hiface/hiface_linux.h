#ifndef HIFACE_LINUX_H
#define HIFACE_LINUX_H

#include <hiface/hiface_c_api.h>
#include <hiface/hiface_rgbir.h>

#define HIFACE_LINUX_HAS_RGBIR_SEARCH_V1 1

#ifdef __cplusplus
extern "C" {
#endif

/** Load and prepare the SDK's protected built-in CPU models for this Session.
 * Create the Session with enable_feature=1 and enable_landmark=1.
 * Synchronous; serialize with other Session calls. No model files are required.
 * out_report may be NULL; otherwise set its struct_size before calling.
 */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_linux_load_builtin_models_v1(
        HiFaceSessionHandle session, HiFaceModelLoadReportV1* out_report);

/** Load only protected FLIR. No detector, feature or landmarks are needed.
 * Then call hiface_session_evaluate_infrared_liveness_v1. Does not start a flow. */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_linux_load_infrared_model_v1(
        HiFaceSessionHandle session, HiFaceModelLoadReportV1* out_report);

/** Prepare only permanent detector/landmark capabilities. No feature/liveness
 * key is released. Advanced operations still enforce their own license gates. */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_linux_load_base_models_v1(
        HiFaceSessionHandle session, HiFaceModelLoadReportV1* out_report);

/** SDK-verified native package identity reference (<=4096 UTF-8 bytes).
 * Does not contain a machine ID, key, boot ID or biometric data. No host facts,
 * storage path, clock or backend override can be registered through this API. */
HIFACE_API HiFaceStatus HIFACE_CALL hiface_linux_license_profile_v1(
        char* output, size_t capacity, size_t* size);

#ifdef __cplusplus
}
#endif
#endif
