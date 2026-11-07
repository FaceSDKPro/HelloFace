#include "search_session.h"
#include "capture_pipeline.h"
#include <cmath>
#include <cstring>
#include <memory>

namespace hiface_linux_demo::rgbir {
SearchSession::SearchSession(Database& database, const RgbIrSettings& settings) : database_(database) {
    loadModels(session, "");
    HiFaceModelLoadReportV1 report{};
    report.struct_size = sizeof(report);
    check(hiface_linux_load_infrared_model_v1(session.handle, &report), "load infrared model");
    HiFaceSearchCameraConfigV1 config{sizeof(config), 0, 0, 1, settings.similarity,
        settings.interval_ms, settings.timeout_ms, settings.group.c_str(), nullptr};
    // The board starts with identity alignment in normalized coordinates.
    // Rigs with different fields of view may need their own calibration.
    HiFaceSearchInfraredConfigV1 infrared{sizeof(infrared), settings.ir_threshold, max_skew_ms, max_age_ms,
        {1, 0, 0, 0, 1, 0, 0, 0, 1}, .25f, 80};
    check(hiface_session_search_start_rgbir_v1(session.handle, &config, &infrared), "start RGB/IR search");
}

std::optional<Sample> SearchSession::process(const CameraFrame& rgb_frame, const CameraFrame& ir, const Pair& pair, int64_t now) {
    const auto rgb = rgb_frame.view();
    // The frames outlive the synchronous prepare call. No frame is retained by the search.
    constexpr uint64_t source_id = 1; // A SearchSession is bound to one opened pair of streams.
    HiFaceSearchInfraredFrameV1 infrared{sizeof(infrared), ir.gray.data(), ir.gray.size(),
        ir.width, ir.height, ir.width, source_id, pair.id, pair.rgb.sequence, pair.ir.sequence, pair.rgb.time, pair.ir.time};
    HiFaceSearchBatchHandle raw = nullptr;
    const auto status = hiface_session_search_prepare_rgbir_v1(session.handle, database_.handle,
        &rgb, &infrared, now, &raw);
    if (status == HIFACE_STATUS_FRAME_SKIPPED) return std::nullopt;
    check(status, "prepare RGB/IR search");
    std::unique_ptr<HiFaceSearchBatchOpaque, decltype(&hiface_search_batch_destroy_v1)>
        batch(raw, hiface_search_batch_destroy_v1);
    check(hiface_search_batch_resolve_v1(raw, database_.handle), "resolve RGB/IR search");
    check(hiface_session_search_complete_v1(session.handle, raw), "complete RGB/IR search");
    Sample sample;
    sample.search.struct_size = sizeof(sample.search);
    sample.infrared.struct_size = sizeof(sample.infrared);
    check(hiface_search_batch_read_v1(raw, &sample.search), "read identity result");
    check(hiface_search_batch_read_infrared_v1(raw, &sample.infrared), "read infrared result");
    require(sample.infrared.source_id == source_id && sample.infrared.pair_id == pair.id,
        "Core returned an IR result for a different frame pair");
    return sample;
}

bool SearchSession::detectInfraredPresence(CameraFrame& ir) {
    // Static detection uses an isolated Core pipeline. Its result only drives lighting and standby.
    ir.expandInfraredRgba();
    const HiFaceDetectionRequestV1 request{sizeof(request), HIFACE_C_API_VERSION_V1, 1, 0};
    HiFaceFaceV1 face{};
    HiFaceFrameResultV1 result{sizeof(result), &face, 1, 0, 0, 0, 0};
    check(hiface_session_process_rgba_v1(session.handle, ir.rgba.data(), ir.rgba.size(),
        ir.width, ir.height, &request, &result), "detect IR face for illumination");
    return result.count != 0;
}

CameraSearchScores searchScores(const Sample& sample) {
    const auto& result = sample.search;
    const auto& ir = sample.infrared;
    CameraSearchScores scores;
    if (ir.has_score && std::isfinite(ir.real_score)) scores.liveness = ir.real_score;
    if (result.face_count != 1) return scores;
    const auto& face = result.faces[0];
    if (face.has_similarity && std::isfinite(face.similarity)) scores.similarity = face.similarity;
    // Core may return a candidate for diagnostics on rejection. Display an ID
    // only when this same batch has both a confirmed match and a valid IR pass.
    if (result.end_reason == HIFACE_SEARCH_END_MATCH_FOUND && ir.input_status == HIFACE_SEARCH_IR_PASSED &&
            face.threshold_passed && scores.similarity && scores.liveness)
        scores.face_id.assign(face.face_id, strnlen(face.face_id, sizeof(face.face_id)));
    return scores;
}

SearchLightColor searchStatusColor(const Sample& sample) {
    const auto& search = sample.search;
    if (sample.infrared.input_status == HIFACE_SEARCH_IR_REJECTED) return SearchLightColor::red;
    if (!searchScores(sample).face_id.empty()) return SearchLightColor::green;
    if (search.face_count == 1 && search.faces[0].has_similarity && !search.faces[0].threshold_passed)
        return SearchLightColor::red;
    return SearchLightColor::blue;
}

std::string searchGuidance(const Sample& sample) {
    const auto& result = sample.search;
    const auto& ir = sample.infrared;
    if (ir.input_status == HIFACE_SEARCH_IR_REJECTED) return "No match";
    if (result.end_reason) return cameraSearchStatus(result);
    switch (ir.input_status) {
        case HIFACE_SEARCH_IR_MULTIPLE_FACES: return "One person at a time";
        case HIFACE_SEARCH_IR_NO_FACE: return "No face in IR view";
        case HIFACE_SEARCH_IR_FACE_MISMATCH: return "Move to the center";
        case HIFACE_SEARCH_IR_FACE_TOO_SMALL: return "Move closer";
        case HIFACE_SEARCH_IR_WAITING_PAIR:
        case HIFACE_SEARCH_IR_STALE_PAIR: return "Waiting for RGB/IR frames";
        default: break;
    }
    return cameraSearchStatus(result);
}
}
