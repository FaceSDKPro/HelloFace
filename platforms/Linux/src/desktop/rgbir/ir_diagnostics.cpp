#include "ir_diagnostics.h"
#include <algorithm>
#include <array>
#include <cinttypes>
#include <cmath>

namespace hiface_linux_demo::rgbir {
namespace {
constexpr uint32_t fourcc(char a, char b, char c, char d) {
    return uint32_t(a) | (uint32_t(b) << 8) | (uint32_t(c) << 16) | (uint32_t(d) << 24);
}

const char* formatName(uint32_t format) {
    switch (format) {
        case fourcc('G', 'R', 'E', 'Y'): return "GREY";
        case fourcc('Y', 'U', 'Y', 'V'): return "YUYV";
        case fourcc('N', 'V', '1', '2'): return "NV12";
        case fourcc('N', 'V', '2', '1'): return "NV21";
        default: return "unknown";
    }
}

const char* inputStatus(uint32_t status) {
    switch (status) {
        case HIFACE_SEARCH_IR_NOT_EVALUATED: return "NOT_EVALUATED";
        case HIFACE_SEARCH_IR_WAITING_PAIR: return "WAITING_PAIR";
        case HIFACE_SEARCH_IR_STALE_PAIR: return "STALE_PAIR";
        case HIFACE_SEARCH_IR_MULTIPLE_FACES: return "MULTIPLE_FACES";
        case HIFACE_SEARCH_IR_NO_FACE: return "NO_FACE";
        case HIFACE_SEARCH_IR_FACE_MISMATCH: return "FACE_MISMATCH";
        case HIFACE_SEARCH_IR_FACE_TOO_SMALL: return "FACE_TOO_SMALL";
        case HIFACE_SEARCH_IR_PASSED: return "PASSED";
        case HIFACE_SEARCH_IR_REJECTED: return "REJECTED";
        default: return "unknown";
    }
}

const char* endReason(HiFaceSearchEndReasonV1 reason) {
    switch (reason) {
        case HIFACE_SEARCH_END_NONE: return "NONE";
        case HIFACE_SEARCH_END_MATCH_FOUND: return "MATCH_FOUND";
        case HIFACE_SEARCH_END_TIMEOUT: return "TIMEOUT";
        case HIFACE_SEARCH_END_NO_FACE: return "NO_FACE";
        case HIFACE_SEARCH_END_SPOOF_DETECTED: return "SPOOF_DETECTED";
        default: return "unknown";
    }
}

void describeLuma(char* output, size_t capacity, const CameraFrame& frame,
                  const HiFaceSearchInfraredResultV1& ir, bool video_range) {
    const double left = ir.face_x, top = ir.face_y;
    const double right = left + ir.face_width, bottom = top + ir.face_height;
    if (frame.width <= 0 || frame.height <= 0 ||
        frame.gray.size() / size_t(frame.width) < size_t(frame.height) ||
        ir.image_width != uint32_t(frame.width) || ir.image_height != uint32_t(frame.height) ||
        !std::isfinite(left) || !std::isfinite(top) || !std::isfinite(right) || !std::isfinite(bottom) ||
        left < 0 || top < 0 || right <= left || bottom <= top || right > frame.width || bottom > frame.height) {
        std::snprintf(output, capacity, "face_luma=unavailable");
        return;
    }

    const int x0 = int(std::floor(left)), y0 = int(std::floor(top));
    const int x1 = int(std::ceil(right)), y1 = int(std::ceil(bottom));
    std::array<size_t, 256> histogram{};
    for (int y = y0; y < y1; ++y) {
        const auto* row = frame.gray.data() + size_t(y) * frame.width;
        for (int x = x0; x < x1; ++x) ++histogram[row[x]];
    }
    const size_t count = size_t(x1 - x0) * (y1 - y0);
    // Near-endpoint pixel fractions are clipping indicators, not exposure measurements.
    const int dark_max = video_range ? 18 : 2, bright_min = video_range ? 233 : 253;
    size_t dark = 0, bright = 0;
    for (int value = 0; value <= dark_max; ++value) dark += histogram[value];
    for (int value = bright_min; value <= 255; ++value) bright += histogram[value];
    const auto percentile = [&](int percent) {
        const auto rank = std::max<size_t>(1, (count * percent + 99) / 100);
        size_t seen = 0;
        for (int value = 0; value <= 255; ++value) {
            seen += histogram[value];
            if (seen >= rank) return value;
        }
        return 255;
    };
    std::snprintf(output, capacity,
        "face_luma_min=%d p05=%d p50=%d p95=%d max=%d dark_pct=%.2f bright_pct=%.2f",
        percentile(0), percentile(5), percentile(50), percentile(95), percentile(100),
        100.0 * dark / count, 100.0 * bright / count);
}
}

void reportIrDiagnostic(std::FILE* output, const RawCameraFrame& raw, const CameraFrame& frame,
                        const HiFaceSearchInfraredResultV1& ir, HiFaceSearchEndReasonV1 end_reason,
                        float threshold) noexcept {
    const bool gray = raw.format == fourcc('G', 'R', 'E', 'Y');
    const bool video_range = !gray && raw.range == HIFACE_YUV_RANGE_VIDEO;
    char score[24] = "unavailable";
    if (ir.has_score && std::isfinite(ir.real_score)) std::snprintf(score, sizeof(score), "%.9g", ir.real_score);
    char luma[160];
    describeLuma(luma, sizeof(luma), frame, ir, video_range);
    std::fprintf(output,
        "[IR-DIAG] pair=%" PRIu64 " format=%s luma_range=%s stride=%d upright=%dx%d "
        "ir_status=%s end_reason=%s real_score=%s threshold=%.9g %s\n",
        ir.pair_id, formatName(raw.format), gray ? "gray8" : video_range ? "video" : "full",
        raw.stride, frame.width, frame.height, inputStatus(ir.input_status), endReason(end_reason),
        score, threshold, luma);
}
}
