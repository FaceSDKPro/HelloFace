#pragma once
#include "hiface/hiface_linux.h"
#include <array>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <locale>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>
namespace hiface_linux_demo {
using Feature = std::array<float, HIFACE_FACE_FEATURE_DIMENSION>;
using FeatureText = std::array<char, HIFACE_FEATURE_TEXT_BUFFER_SIZE>;
struct DemoError {
    std::string message;
    HiFaceStatus status = HIFACE_STATUS_INTERNAL_ERROR;
    bool sdk_status_known = false;
    explicit DemoError(std::string text) : message(std::move(text)) {}
    DemoError(std::string text, HiFaceStatus code) : message(std::move(text)), status(code), sdk_status_known(true) {}
};

inline const char* statusName(HiFaceStatus status) {
    switch (status) {
        case HIFACE_STATUS_OK: return "OK";
        case HIFACE_STATUS_INVALID_ARGUMENT: return "INVALID_ARGUMENT";
        case HIFACE_STATUS_INVALID_STATE: return "INVALID_STATE";
        case HIFACE_STATUS_MODEL_LOAD_FAILED: return "MODEL_LOAD_FAILED";
        case HIFACE_STATUS_UNSUPPORTED_FORMAT: return "UNSUPPORTED_FORMAT";
        case HIFACE_STATUS_RESOURCE_EXHAUSTED: return "RESOURCE_EXHAUSTED";
        case HIFACE_STATUS_FRAME_SKIPPED: return "FRAME_SKIPPED";
        case HIFACE_STATUS_BUSY: return "BUSY";
        case HIFACE_STATUS_DATABASE_ERROR: return "DATABASE_ERROR";
        case HIFACE_STATUS_NOT_FOUND: return "NOT_FOUND";
        case HIFACE_STATUS_ALREADY_EXISTS: return "ALREADY_EXISTS";
        case HIFACE_STATUS_IMAGE_NO_FACE: return "IMAGE_NO_FACE";
        case HIFACE_STATUS_IMAGE_FACE_TOO_SMALL: return "IMAGE_FACE_TOO_SMALL";
        case HIFACE_STATUS_LICENSE_MISSING: return "LICENSE_MISSING";
        case HIFACE_STATUS_LICENSE_INVALID: return "LICENSE_INVALID";
        case HIFACE_STATUS_LICENSE_NOT_YET_VALID: return "LICENSE_NOT_YET_VALID";
        case HIFACE_STATUS_LICENSE_EXPIRED: return "LICENSE_EXPIRED";
        case HIFACE_STATUS_LICENSE_FEATURE_DENIED: return "LICENSE_FEATURE_DENIED";
        case HIFACE_STATUS_LICENSE_CLOCK_INVALID: return "LICENSE_CLOCK_INVALID";
        default: return "INTERNAL_ERROR";
    }
}

inline void require(bool condition, const std::string& message) {
    if (!condition) throw DemoError{message};
}

inline void check(HiFaceStatus status, const char* operation) {
    if (status != HIFACE_STATUS_OK)
        throw DemoError{std::string(operation) + ": " + statusName(status) + " (" + std::to_string(status) + ")", status};
}

inline const char* cameraSearchStatus(const HiFaceSearchCameraResultV1& result) {
    switch (result.end_reason) {
        case HIFACE_SEARCH_END_MATCH_FOUND: return "Match found";
        case HIFACE_SEARCH_END_TIMEOUT: return "No match (timeout)";
        case HIFACE_SEARCH_END_NO_FACE: return "No face";
        case HIFACE_SEARCH_END_SPOOF_DETECTED: return "No match";
        default: break;
    }
    switch (result.progress) {
        case HIFACE_SEARCH_STAGE_EMPTY_GALLERY: return "No faces in scope";
        case HIFACE_SEARCH_STAGE_FACE_TOO_SMALL: return "Move closer";
        case HIFACE_SEARCH_STAGE_SEARCHING: return "Searching...";
        case HIFACE_SEARCH_STAGE_SUCCESS_INTERVAL: return "Waiting...";
        default: return "No face";
    }
}

struct CameraSearchScores {
    std::optional<float> similarity, liveness;
    std::string face_id;

    bool available() const { return similarity || liveness; }

    bool exceeds(float similarity_threshold, std::optional<float> liveness_threshold) const {
        return similarity && *similarity > similarity_threshold &&
            (!liveness_threshold || (liveness && *liveness > *liveness_threshold));
    }

    std::string caption(bool show_liveness = true) const {
        std::ostringstream text;
        text.imbue(std::locale::classic());
        text << (face_id.empty() ? "Similarity" : face_id) << '=' << std::fixed << std::setprecision(2);
        if (similarity) text << *similarity;
        else text << "—";
        if (show_liveness) {
            text << ", Liveness=";
            if (liveness) text << *liveness;
            else text << "—";
        }
        return text.str();
    }
};

// Own one SDK session; configure the runtime before creation and destroy the handle on scope exit.
// 管理单个 SDK 会话；创建前配置运行时，离开作用域时销毁句柄。
struct Session {
    HiFaceSessionHandle handle = nullptr;
    Session() {
        HiFaceRuntimeConfigV1 runtime{sizeof(runtime), HIFACE_C_API_VERSION_V1, 0, 0};
        if (const char* threads = std::getenv("HIFACE_CPU_THREADS")) {
            require(std::string(threads) == "2" || std::string(threads) == "4",
                "HIFACE_CPU_THREADS must be 2 or 4");
            runtime.cpu_threads = threads[0] - '0';
        }
        check(hiface_runtime_configure_v1(&runtime), "configure runtime");
        HiFaceConfigV1 config{};
        config.struct_size = sizeof(config);
        config.api_version = HIFACE_C_API_VERSION_V1;
        config.compute_mode = HIFACE_COMPUTE_CPU;
        config.enable_feature = config.enable_landmark = 1;
        config.eye_closed_ear_threshold = HIFACE_DEFAULT_EYE_CLOSED_EAR_THRESHOLD;
        config.mouth_open_mar_threshold = HIFACE_DEFAULT_MOUTH_OPEN_MAR_THRESHOLD;
        check(hiface_session_create_v1(&config, &handle), "create session");
    }
    ~Session() { hiface_session_destroy_v1(handle); }
    Session(const Session&) = delete;
    Session& operator=(const Session&) = delete;
};

// Own one database handle; callers serialize access and never copy the owner.
// 管理单个数据库句柄；调用方串行访问，持有者不可复制。
struct Database {
    HiFaceSearchDatabaseHandle handle = nullptr;
    explicit Database(const char* path) { check(hiface_search_open_v1(path, &handle), "open database"); }
    ~Database() { hiface_search_close_v1(handle); }
    Database(const Database&) = delete;
    Database& operator=(const Database&) = delete;
};

inline void loadModels(Session& session, const std::string&) {
    HiFaceModelLoadReportV1 report{};
    report.struct_size = sizeof(report);
    check(hiface_linux_load_builtin_models_v1(session.handle, &report), "initialize SDK models");
    require(report.detector_backend == HIFACE_MODEL_BACKEND_CPU
            && report.feature_backend == HIFACE_MODEL_BACKEND_CPU
            && report.landmarks_backend == HIFACE_MODEL_BACKEND_CPU
            && report.silent_liveness_s_backend == HIFACE_MODEL_BACKEND_CPU
            && report.silent_liveness_m_backend == HIFACE_MODEL_BACKEND_CPU,
            "Expected CPU models");
}

struct Image {
    int width = 0, height = 0;
    std::vector<uint8_t> rgba;
};

inline Feature captureFeature(Session& session, const Image& image, std::vector<uint8_t>* preview = nullptr) {
    Feature feature{};
    if (preview) preview->resize(HIFACE_ALIGNED_PREVIEW_RGBA_BYTES);
    check(hiface_session_capture_rgba_v1(session.handle, image.rgba.data(), image.rgba.size(),
        image.width, image.height, feature.data(), feature.size(),
        preview ? preview->data() : nullptr, preview ? preview->size() : 0), "capture largest face");
    return feature;
}

inline FeatureText encodeFeature(const Feature& feature) {
    FeatureText text{};
    check(hiface_feature_encode_text_v1(feature.data(), feature.size(), text.data(), text.size()), "encode HF1");
    return text;
}

}
