#pragma once
#include "hiface/client.hpp"
#include "hiface/database.hpp"
#include <exception>
namespace hiface_demo {
using hiface::Image; using hiface::CameraFrame; using hiface::Feature;
using hiface::SearchOptions; using hiface::FlowKind; using hiface::FlowOptions;
using hiface::DetailedFace; using hiface::CaptureResult; using hiface::FlowResult;
using hiface::Person; using Gallery = hiface::Database; using SdkError = hiface::Error;
using hiface::check; using hiface::flowConfig;
using hiface::encodeFeature; using hiface::decodeFeature; using hiface::compareFeatureText;

inline int accessErrorCode(HiFaceStatus status) {
    switch (status) {
        case HIFACE_STATUS_LICENSE_MISSING: return 1602;
        case HIFACE_STATUS_LICENSE_INVALID: return 1603;
        case HIFACE_STATUS_LICENSE_NOT_YET_VALID: return 1604;
        case HIFACE_STATUS_LICENSE_EXPIRED: return 1605;
        case HIFACE_STATUS_LICENSE_FEATURE_DENIED: return 1606;
        case HIFACE_STATUS_LICENSE_CLOCK_INVALID: return 1608;
        default: return 0;
    }
}

inline bool isAccessError(HiFaceStatus status) {
    return accessErrorCode(status) != 0;
}

inline std::string accessMessage(HiFaceStatus status) {
    const int code = accessErrorCode(status);
    if (!code) return {};
    return u8"功能不可用（错误码 " + std::to_string(code) + u8"）";
}

// Keep the SDK error for diagnostics and use one prompt for unavailable features.
inline std::string demoErrorMessage(const SdkError& error, const char* prefix = "") {
    if (auto message = accessMessage(error.status); !message.empty()) return message;
    return std::string(prefix) + error.what();
}

inline std::string demoErrorMessage(std::exception_ptr error, const char* prefix = "") {
    try {
        std::rethrow_exception(error);
    } catch (const SdkError& sdk) {
        return demoErrorMessage(sdk, prefix);
    } catch (const std::exception& other) {
        return std::string(prefix) + other.what();
    }
}
}
