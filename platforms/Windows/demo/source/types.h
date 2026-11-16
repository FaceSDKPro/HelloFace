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

// Keep the SDK error for diagnostics and use one prompt for unavailable features.
inline std::string demoErrorMessage(const SdkError& error, const char* prefix = "") {
    if ((error.status >= HIFACE_STATUS_LICENSE_MISSING && error.status <= HIFACE_STATUS_LICENSE_FEATURE_DENIED) ||
        error.status == HIFACE_STATUS_LICENSE_CLOCK_INVALID) {
        return u8"功能不可用,请升级或联系技术支持";
    }
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
