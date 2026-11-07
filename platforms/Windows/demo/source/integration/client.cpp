#include "hiface/client.hpp"
#include "hiface/database.hpp"
#include <cmath>
#include <algorithm>
#include <chrono>
#include <memory>
#include <thread>
#include "hiface/hiface_windows.h"
namespace hiface {
namespace {
// Scratch references are cleared on success, cancellation and exceptions.
// 临时参考特征在成功、取消和异常退出时都清理；返回结果另持有自身数据。
struct ClearFeature {
    Feature& value;
    ~ClearFeature() { value.fill(0); }
};
int64_t nowMilliseconds() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}
HiFaceFrameResultV1 frameResult(HiFaceFaceV1* faces, uint32_t capacity) {
    HiFaceFrameResultV1 result{};
    result.struct_size = sizeof(result); result.faces = faces; result.capacity = capacity;
    return result;
}
void validateImage(const Image& image) {
    if (image.width < 2 || image.height < 2 || (image.width & 1) || (image.height & 1)
        || image.width > static_cast<int>(HIFACE_MAX_IMAGE_DIMENSION)
        || image.height > static_cast<int>(HIFACE_MAX_IMAGE_DIMENSION)
        || image.rgba.size() != static_cast<size_t>(image.width) * image.height * 4)
        throw std::runtime_error("Expected an even-sized, tightly packed RGBA image, at most 4096x4096");
}
}
// Configure CPU, open the gallery and load only detection/feature capabilities.
// Flow/search-specific models are loaded lazily by their start methods.
// 创建 CPU 会话并打开人脸库；动作/活体能力到实际使用时再加载。
Client::Client(const std::filesystem::path& database) {
    const auto path = database.u8string();
    if (path.find('\0') != std::string::npos) throw std::invalid_argument("Database path contains NUL");
    if (hiface_get_api_version_v1() != HIFACE_C_API_VERSION_V1)
        throw std::runtime_error("HiFace DLL/header version mismatch");
    HiFaceRuntimeConfigV1 runtime{sizeof(runtime), HIFACE_C_API_VERSION_V1, 0, 0};
    check(hiface_runtime_configure_v1(&runtime), "configure CPU runtime");
    HiFaceConfigV1 config{};
    config.struct_size = sizeof(config); config.api_version = HIFACE_C_API_VERSION_V1;
    config.compute_mode = HIFACE_COMPUTE_CPU;
    config.enable_feature = config.enable_landmark = 1;
    config.eye_closed_ear_threshold = HIFACE_DEFAULT_EYE_CLOSED_EAR_THRESHOLD;
    config.mouth_open_mar_threshold = HIFACE_DEFAULT_MOUTH_OPEN_MAR_THRESHOLD;
    auto clear = [&] {
        hiface_search_close_v1(database_); hiface_session_destroy_v1(session_);
        database_ = nullptr; session_ = nullptr; loaded_.fill(false);
    };
    constexpr int delays[] = {100, 300, 900};
    for (unsigned attempt = 0;; ++attempt) {
        try {
            check(hiface_session_create_v1(&config, &session_), "create session");
            if (database.has_parent_path()) std::filesystem::create_directories(database.parent_path());
            check(hiface_search_open_v1(path.c_str(), &database_), "open face database");
            load(HIFACE_MODEL_DETECTOR);
            load(HIFACE_MODEL_FEATURE);
            startSearch();
            break;
        } catch (const Error& error) {
            clear();
            if (error.status != HIFACE_STATUS_BUSY || attempt >= 3) throw;
            // Release failed handles before a bounded retry, off the UI thread.
            // 仅重试临时占用；先释放失败句柄，后台退避期间不持有会话或数据库。
            std::this_thread::sleep_for(std::chrono::milliseconds(delays[attempt]));
        } catch (...) { clear(); throw; }
    }
}
Client::~Client() {
    if (session_) {
        hiface_session_search_stop_v1(session_);
        hiface_session_face_flow_stop_v1(session_);
        hiface_session_destroy_v1(session_);
    }
    hiface_search_close_v1(database_);
}
void Client::load(HiFaceModelIdV1 id) {
    if (loaded_.at(static_cast<size_t>(id))) return;
    HiFaceModelLoadReportV1 report{}; report.struct_size = sizeof(report);
    check(hiface_windows_session_load_model_v1(session_, id, &report), "load built-in model");
    check(hiface_session_prepare_loaded_models_v1(session_, &report), "prepare models");
    if (report.gpu_fell_back) throw std::runtime_error("Unexpected GPU request in CPU client");
    loaded_.at(static_cast<size_t>(id)) = true;
}
void Client::loadAllModels() {
    load(HIFACE_MODEL_LANDMARKS);
    load(HIFACE_MODEL_SILENT_LIVENESS_S);
    load(HIFACE_MODEL_SILENT_LIVENESS_M);
}
HiFaceFlowConfigV1 flowConfig(const FlowOptions& options, const Feature* reference) {
    if (options.actions.size() > HIFACE_MAX_FACE_FLOW_ACTIONS || !std::isfinite(options.threshold)
        || options.threshold < 0 || options.threshold > 1)
        throw std::runtime_error("Expected at most four actions and a threshold in [0,1]");
    if (options.kind == FlowKind::Capture && !options.actions.empty())
        throw std::runtime_error("Guided capture does not accept actions");
    HiFaceFlowConfigV1 config{};
    config.struct_size = sizeof(config); config.api_version = HIFACE_C_API_VERSION_V1;
    config.mode = options.kind == FlowKind::Capture ? HIFACE_FLOW_GUIDED_CAPTURE
        : options.kind == FlowKind::Liveness ? HIFACE_FLOW_ACTION_LIVENESS
        : options.silent_liveness ? HIFACE_FLOW_FACE_AUTHENTICATION : HIFACE_FLOW_FACE_VERIFICATION;
    config.min_face_size_pixels = HIFACE_FLOW_DEFAULT_MIN_FACE_SIZE_PIXELS;
    config.verification_threshold = options.threshold;
    config.frontal_hold_ms = options.kind == FlowKind::Capture ? HIFACE_CAPTURE_FRONTAL_HOLD_MS : HIFACE_FLOW_DEFAULT_FRONTAL_HOLD_MS;
    config.multiple_faces_allowed = options.allow_multiple ? 1 : 0;
    if (options.kind != FlowKind::Capture) {
        config.action_count = static_cast<uint32_t>(options.actions.size());
        for (size_t i = 0; i < options.actions.size(); ++i) {
            const auto action = options.actions[i];
            if (action < HIFACE_ACTION_SHAKE_HEAD || action > HIFACE_ACTION_MOUTH_OPEN) throw std::runtime_error("Invalid action");
            config.actions[i] = action;
        }
        config.action_timeout_ms = HIFACE_FLOW_DEFAULT_ACTION_TIMEOUT_MS;
        config.face_acquisition_timeout_ms = HIFACE_FLOW_DEFAULT_FACE_ACQUISITION_TIMEOUT_MS;
        config.face_lost_timeout_ms = HIFACE_FLOW_DEFAULT_FACE_LOST_TIMEOUT_MS;
        config.multiple_faces_timeout_ms = HIFACE_FLOW_DEFAULT_MULTIPLE_FACES_TIMEOUT_MS;
        config.final_capture_timeout_ms = HIFACE_FLOW_DEFAULT_FINAL_CAPTURE_TIMEOUT_MS;
    }
    if (options.kind == FlowKind::Verification) {
        if (!reference) throw std::runtime_error("Verification requires a reference feature");
        config.verification_reference = reference->data(); config.verification_reference_count = reference->size();
    }
    return config;
}
void Client::startSearch() {
    if (!search_enabled_ || search_paused_ || flow_active_) return;
    if (search_.liveness) {
        load(HIFACE_MODEL_SILENT_LIVENESS_S);
        load(HIFACE_MODEL_SILENT_LIVENESS_M);
    }
    HiFaceSearchCameraConfigV1 config{};
    config.struct_size = sizeof(config); config.multi_face = search_.multi_face ? 1 : 0;
    config.max_faces = search_.max_faces; config.need_liveness = search_.liveness ? 1 : 0;
    config.threshold = search_.threshold; config.interval_ms = search_.interval_ms; config.timeout_ms = search_.timeout_ms;
    config.group = search_.group.c_str(); config.tag = search_.tag.c_str();
    check(hiface_session_search_start_v1(session_, &config), "start camera search");
}
void Client::configureSearch(const SearchOptions& options) {
    if (!std::isfinite(options.threshold) || options.threshold < .75f || options.threshold > .85f
        || options.max_faces < 1 || options.max_faces > 5 || options.interval_ms > 3000
        || options.timeout_ms < 1000 || options.timeout_ms > 3000 || (options.multi_face && options.liveness)
        || options.group.size() > HIFACE_SEARCH_MAX_TEXT_BYTES || options.tag.size() > HIFACE_SEARCH_MAX_TEXT_BYTES
        || options.group.find('\0') != std::string::npos || options.tag.find('\0') != std::string::npos)
        throw std::runtime_error("Search: threshold .75-.85, max faces 1-5, interval 0-3000 ms, timeout 1000-3000 ms; M:N disables liveness");
    if (flow_active_) throw std::runtime_error("Cancel the active camera flow before changing search settings");
    if (options.liveness) { load(HIFACE_MODEL_SILENT_LIVENESS_S); load(HIFACE_MODEL_SILENT_LIVENESS_M); }
    check(hiface_session_search_stop_v1(session_), "stop search");
    const auto previous = search_; search_ = options;
    try { startSearch(); } catch (...) { search_ = previous; startSearch(); throw; }
}
void Client::setLiveness(bool enabled) {
    if (enabled == search_.liveness) return;
    auto options = search_; options.liveness = enabled; configureSearch(options);
}
void Client::pauseSearch(bool paused) {
    if (search_paused_ == paused) return;
    check(hiface_session_search_stop_v1(session_), "pause search");
    search_paused_ = paused;
    if (paused) check(hiface_search_release_memory_v1(database_), "release search cache");
    else startSearch();
}
void Client::useSearch(bool enabled) {
    if (flow_active_) cancelFlow();
    check(hiface_session_search_stop_v1(session_), "switch camera mode");
    search_enabled_ = enabled; startSearch();
}
void Client::configureDetection(uint32_t max_faces, bool detailed) {
    if (max_faces < 1 || max_faces > HIFACE_MAX_FACES) throw std::runtime_error("Detection supports 1-10 faces");
    if (detailed) load(HIFACE_MODEL_LANDMARKS);
    detection_max_ = max_faces; detailed_ = detailed;
}
void Client::beginFlow(const FlowOptions& options) {
    if (flow_active_) throw std::runtime_error("A camera flow is already running; cancel it first");
    Feature reference{};
    ClearFeature clear{reference};
    if (options.kind == FlowKind::Verification) reference = decodeFeature(options.reference);
    const auto config = flowConfig(options, options.kind == FlowKind::Verification ? &reference : nullptr);
    load(HIFACE_MODEL_LANDMARKS);
    if (options.kind == FlowKind::Liveness || (options.kind == FlowKind::Verification && options.silent_liveness)) {
        load(HIFACE_MODEL_SILENT_LIVENESS_S); load(HIFACE_MODEL_SILENT_LIVENESS_M);
    }
    check(hiface_session_search_stop_v1(session_), "stop search for flow");
    const auto status = hiface_session_face_flow_start_v1(session_, &config, nowMilliseconds());
    if (status != HIFACE_STATUS_OK) { startSearch(); check(status, "start camera flow"); }
    flow_mode_ = config.mode; flow_active_ = true;
}
void Client::stopFlow() {
    check(hiface_session_face_flow_stop_v1(session_), "stop camera flow");
    flow_active_ = false;
}
void Client::cancelFlow() {
    if (!flow_active_) return;
    stopFlow(); startSearch();
}
namespace {
void copyFace(FrameUpdate& update, const HiFaceFaceV1& face) {
    HiFaceSearchCameraFaceV1 box{};
    box.x = face.x; box.y = face.y; box.width = face.width; box.height = face.height; box.confidence = face.confidence;
    for (size_t j = 0; j < HIFACE_MAX_LANDMARKS; ++j) { box.landmarks[j * 2] = face.landmarks[j].x; box.landmarks[j * 2 + 1] = face.landmarks[j].y; }
    update.faces.push_back(box);
    DetailedFace detail; detail.face = face; detail.face.mesh = nullptr;
    if (face.mesh_valid && face.mesh) detail.mesh.assign(face.mesh, face.mesh + face.mesh_count);
    update.details.push_back(std::move(detail));
}
}
// Copy the SDK-owned result before stopping the flow. A page change may still
// cancel publication; required result flags are checked before exposing data.
// 停止流程前复制 SDK 结果；旧页面取消后不发布，必要标志缺失时不伪造成功。
void Client::completeFlow(FrameUpdate& update, const std::function<bool()>& current) {
    FlowResult completed; completed.metadata.struct_size = sizeof(completed.metadata);
    Feature feature{};
    ClearFeature clear{feature};
    completed.preview = {HIFACE_ALIGNED_PREVIEW_SIDE, HIFACE_ALIGNED_PREVIEW_SIDE, std::vector<uint8_t>(HIFACE_ALIGNED_PREVIEW_RGBA_BYTES)};
    check(hiface_session_face_flow_copy_result_v1(session_, &completed.metadata, feature.data(), feature.size(),
        completed.preview.rgba.data(), completed.preview.rgba.size()), "copy flow result");
    const auto mode = flow_mode_;
    stopFlow();
    if (current && !current()) { startSearch(); update.flow_active = false; update.cancelled = true; return; }
    const auto flags = completed.metadata.flags;
    if (!(flags & HIFACE_FLOW_RESULT_HAS_PREVIEW)) completed.preview = {};
    if (flags & HIFACE_FLOW_RESULT_HAS_FEATURE) {
        if (completed.metadata.feature_count != feature.size()) throw std::runtime_error("Incomplete flow feature");
        completed.feature = encodeFeature(feature);
    }
    const bool compared = completed.metadata.outcome == HIFACE_FLOW_OUTCOME_PASSED || completed.metadata.outcome == HIFACE_FLOW_OUTCOME_NOT_MATCHED;
    if ((mode == HIFACE_FLOW_GUIDED_CAPTURE && (!(flags & HIFACE_FLOW_RESULT_HAS_FEATURE) || !(flags & HIFACE_FLOW_RESULT_HAS_PREVIEW)))
        || ((mode == HIFACE_FLOW_FACE_VERIFICATION || mode == HIFACE_FLOW_FACE_AUTHENTICATION) && compared && !(flags & HIFACE_FLOW_RESULT_HAS_SIMILARITY))
        || ((mode == HIFACE_FLOW_ACTION_LIVENESS || mode == HIFACE_FLOW_FACE_AUTHENTICATION) && compared && !(flags & HIFACE_FLOW_RESULT_HAS_LIVENESS)))
        throw std::runtime_error("Core flow result is missing required data");
    update.matched = completed.metadata.outcome == HIFACE_FLOW_OUTCOME_PASSED;
    update.result = std::move(completed); update.flow_active = false;
    startSearch();
}
FrameUpdate Client::process(const CameraFrame& input, const std::function<bool()>& current) {
    const auto frame = input.view();
    FrameUpdate update; update.flow_active = flow_active_; update.paused = search_paused_;
    if (flow_active_ || !search_enabled_ || search_paused_) {
        if (flow_active_ && current && !current()) {
            cancelFlow(); update.flow_active = false; update.cancelled = true; return update;
        }
        // Detection and guided/action flows share the Core camera pipeline.
        // 检测与采集/动作流程复用 Core 相机管线；返回前拷贝借用的 mesh 数据。
        std::vector<HiFaceFaceV1> faces(detection_max_);
        auto result = frameResult(faces.data(), detection_max_);
        HiFaceDetectionRequestV1 request{sizeof(request), HIFACE_C_API_VERSION_V1, detection_max_, detailed_ ? 1u : 0u};
        HiFaceFlowEventV1 event{}; event.struct_size = sizeof(event);
        const auto status = hiface_session_process_camera_yuv420_v1(session_, &frame, &request, nowMilliseconds(), &result, &event);
        if (status == HIFACE_STATUS_FRAME_SKIPPED) { update.skipped = true; return update; }
        check(status, "process camera frame");
        for (uint32_t i = 0; i < result.count; ++i) copyFace(update, faces[i]);
        update.event = event;
        if (event.kind == HIFACE_FLOW_EVENT_ERROR) { cancelFlow(); check(event.flow_status, "camera flow"); }
        if (event.kind == HIFACE_FLOW_EVENT_RESULT_AVAILABLE) {
            completeFlow(update, current);
        }
        return update;
    }
    // Search has three stages: prepare frames, resolve against the gallery, then
    // complete liveness/interval state. The batch owns all borrowed C result pointers.
    // 搜索依次准备帧、查询人脸库、完成本轮；结果指针只在 batch 存活期间有效。
    HiFaceSearchBatchHandle raw = nullptr;
    const auto status = hiface_session_search_prepare_yuv420_v1(session_, database_, &frame, nowMilliseconds(), &raw);
    if (status == HIFACE_STATUS_FRAME_SKIPPED) { update.skipped = true; return update; }
    check(status, "prepare camera search");
    std::unique_ptr<HiFaceSearchBatchOpaque, decltype(&hiface_search_batch_destroy_v1)> batch(raw, hiface_search_batch_destroy_v1);
    check(hiface_search_batch_resolve_v1(raw, database_), "resolve camera search");
    check(hiface_session_search_complete_v1(session_, raw), "complete camera search");
    HiFaceSearchCameraResultV1 result{}; result.struct_size = sizeof(result);
    check(hiface_search_batch_read_v1(raw, &result), "read camera search");
    update.faces.assign(result.faces, result.faces + result.face_count);
    update.end_reason = result.end_reason; update.has_liveness = result.has_liveness_score != 0; update.liveness_score = result.liveness_score;
    update.matched = result.end_reason == HIFACE_SEARCH_END_MATCH_FOUND;
    update.searching = true; update.search_progress = result.progress;
    return update;
}
std::vector<HiFaceFaceV1> Client::detect(const Image& image) {
    validateImage(image);
    std::vector<HiFaceFaceV1> faces(HIFACE_MAX_FACES);
    auto result = frameResult(faces.data(), static_cast<uint32_t>(faces.size()));
    HiFaceDetectionRequestV1 request{sizeof(request), HIFACE_C_API_VERSION_V1, HIFACE_MAX_FACES, 0};
    check(hiface_session_process_rgba_v1(session_, image.rgba.data(), image.rgba.size(),
        image.width, image.height, &request, &result), "detect image");
    faces.resize(result.count);
    return faces;
}
FrameUpdate Client::detectDetailed(const Image& image, uint32_t max_faces, bool detailed) {
    validateImage(image);
    configureDetection(max_faces, detailed);
    std::vector<HiFaceFaceV1> faces(max_faces);
    auto result = frameResult(faces.data(), max_faces);
    HiFaceDetectionRequestV1 request{sizeof(request), HIFACE_C_API_VERSION_V1, max_faces, detailed ? 1u : 0u};
    check(hiface_session_process_rgba_v1(session_, image.rgba.data(), image.rgba.size(), image.width, image.height, &request, &result), "detect image");
    FrameUpdate update;
    for (uint32_t i = 0; i < result.count; ++i) copyFace(update, faces[i]);
    return update;
}
CaptureResult Client::captureWithPreview(const Image& image) {
    validateImage(image);
    CaptureResult result;
    result.preview = {HIFACE_ALIGNED_PREVIEW_SIDE, HIFACE_ALIGNED_PREVIEW_SIDE, std::vector<uint8_t>(HIFACE_ALIGNED_PREVIEW_RGBA_BYTES)};
    check(hiface_session_capture_rgba_v1(session_, image.rgba.data(), image.rgba.size(), image.width,
        image.height, result.feature.data(), result.feature.size(), result.preview.rgba.data(), result.preview.rgba.size()), "capture image");
    result.text = encodeFeature(result.feature); return result;
}
Feature Client::capture(const Image& image) {
    validateImage(image);
    Feature feature{};
    check(hiface_session_capture_rgba_v1(session_, image.rgba.data(), image.rgba.size(), image.width,
        image.height, feature.data(), feature.size(), nullptr, 0), "capture image");
    return feature;
}
std::vector<ImageFaceCapture> Client::captureFaces(const Image& image, uint32_t maximum, bool previews) {
    validateImage(image);
    if (maximum < 1 || maximum > HIFACE_MAX_FACES)
        throw std::invalid_argument("Image capture supports 1-10 faces");
    std::vector<HiFaceFaceV1> faces(maximum);
    std::vector<HiFaceStatus> statuses(maximum);
    std::vector<float> features(maximum * HIFACE_FACE_FEATURE_DIMENSION);
    // Feature buffers are temporary; the returned successful captures own copies.
    // 特征缓冲仅临时使用；成功返回的采集结果持有独立副本。
    struct Clear { std::vector<float>& values; ~Clear() { std::fill(values.begin(), values.end(), 0); } } clear{features};
    std::vector<uint8_t> pixels(previews ? maximum * size_t{HIFACE_ALIGNED_PREVIEW_RGBA_BYTES} : 0);
    uint32_t count = 0;
    check(hiface_session_capture_faces_rgba_v1(session_, image.rgba.data(), image.rgba.size(), image.width, image.height,
        faces.data(), statuses.data(), features.data(), maximum, &count,
        previews ? pixels.data() : nullptr, pixels.size()), "capture image faces");
    if (count > maximum) throw std::runtime_error("Invalid image capture count");
    std::vector<ImageFaceCapture> result;
    result.reserve(count);
    for (uint32_t i = 0; i < count; ++i) {
        ImageFaceCapture face; face.face = faces[i]; face.face.mesh = nullptr; face.status = statuses[i];
        if (face.status == HIFACE_STATUS_OK) {
            CaptureResult captured;
            std::copy_n(features.data() + i * HIFACE_FACE_FEATURE_DIMENSION, captured.feature.size(), captured.feature.begin());
            captured.text = encodeFeature(captured.feature);
            if (previews) {
                const auto first = pixels.begin() + i * HIFACE_ALIGNED_PREVIEW_RGBA_BYTES;
                captured.preview = {HIFACE_ALIGNED_PREVIEW_SIDE, HIFACE_ALIGNED_PREVIEW_SIDE,
                    std::vector<uint8_t>(first, first + HIFACE_ALIGNED_PREVIEW_RGBA_BYTES)};
            }
            face.capture = std::move(captured);
        }
        result.push_back(std::move(face));
    }
    return result;
}
void Client::insertFeature(const std::string& id, const Feature& feature) {
    if (id.empty() || id.size() > HIFACE_SEARCH_MAX_TEXT_BYTES || id.find('\0') != std::string::npos)
        throw std::invalid_argument("Invalid face ID");
    const auto text = encodeFeature(feature);
    HiFaceSearchFeatureEntryV1 entry{sizeof(entry), id.c_str(), "", "", text.c_str(),
        HIFACE_FEATURE_TEXT_LENGTH, 0, HIFACE_FEATURE_SPACE_ID};
    const HiFaceSearchFeatureEntryV1* entries[] = {&entry};
    check(hiface_search_insert_v1(database_, entries, 1), "insert person");
}
std::vector<std::pair<std::string, float>> Client::query(const Feature& feature) {
    HiFaceSearchResultsHandle raw = nullptr;
    check(hiface_search_query_v1(database_, feature.data(), feature.size(), search_.group.c_str(), search_.tag.c_str(),
        5, search_.threshold, &raw), "search gallery");
    std::unique_ptr<HiFaceSearchResultsOpaque, decltype(&hiface_search_results_destroy_v1)>
        results(raw, hiface_search_results_destroy_v1);
    std::vector<std::pair<std::string, float>> matches;
    for (uint32_t i = 0; i < hiface_search_results_count_v1(raw); ++i) {
        HiFaceSearchEntryV1 entry{}; entry.struct_size = sizeof(entry);
        float score = 0;
        check(hiface_search_results_get_v1(raw, i, &entry, &score), "read match");
        matches.emplace_back(entry.face_id, score);
    }
    return matches;
}
uint64_t Client::count() const {
    uint64_t count = 0;
    check(hiface_search_count_v1(database_, nullptr, nullptr, &count), "count gallery");
    return count;
}
}
