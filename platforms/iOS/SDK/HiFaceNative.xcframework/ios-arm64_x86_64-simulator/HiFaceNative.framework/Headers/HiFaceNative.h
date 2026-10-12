#ifndef HIFACE_NATIVE_FRAMEWORK_H
#define HIFACE_NATIVE_FRAMEWORK_H

#if __has_include(<HiFaceNative/hiface/hiface_c_api.h>)
#include <HiFaceNative/hiface/hiface_c_api.h>
#else
#include "hiface/hiface_c_api.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/** Link anchor and runtime compatibility probe used by the Objective-C++ adapter. */
HIFACE_API uint32_t HIFACE_CALL hiface_ios_native_api_version(void);

#ifdef __cplusplus
}
#endif

#endif /* HIFACE_NATIVE_FRAMEWORK_H */
