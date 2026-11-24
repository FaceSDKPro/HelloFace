#include "image_search.h"
#include <iomanip>
#include <sstream>
namespace hiface_linux_demo {
ImageSearchReport searchImage(Session& session, Database& database, const Image& image, const std::function<bool()>& cancelled) {
    ImageSearchReport report;
    auto stopped = [&] { if (cancelled && cancelled()) { report.cancelled = true; report.faces.clear(); report.matched = 0; return true; } return false; };
    if (stopped()) return report;
    check(hiface_search_count_v1(database.handle, nullptr, nullptr, &report.library_count), "count image search library");
    std::array<HiFaceFaceV1, HIFACE_MAX_FACES> faces{};
    std::array<HiFaceStatus, HIFACE_MAX_FACES> statuses{};
    std::vector<float> features(HIFACE_MAX_FACES * HIFACE_FACE_FEATURE_DIMENSION);
    std::vector<uint8_t> previews(HIFACE_MAX_FACES * HIFACE_ALIGNED_PREVIEW_RGBA_BYTES);
    uint32_t count = 0;
    check(hiface_session_capture_faces_rgba_v1(session.handle, image.rgba.data(), image.rgba.size(), image.width, image.height,
        faces.data(), statuses.data(), features.data(), HIFACE_MAX_FACES, &count, previews.data(), previews.size()), "capture photo faces");
    if (stopped()) return report;
    require(count <= HIFACE_MAX_FACES, "SDK returned too many image faces");
    for (uint32_t i = 0; i < count; ++i) {
        if (stopped()) return report;
        const auto& face = faces[i];
        ImageFaceMatch result; result.x = face.x; result.y = face.y; result.width = face.width; result.height = face.height; result.capture_status = statuses[i];
        if (result.capture_status != HIFACE_STATUS_OK) {
            result.label = accessMessage(result.capture_status);
            if (result.label.empty()) result.label = result.capture_status == HIFACE_STATUS_IMAGE_FACE_TOO_SMALL
                ? "Face too small (100px required)" : std::string("Capture failed: ") + statusName(result.capture_status);
        } else {
            const auto* pixels = previews.data() + size_t(i) * HIFACE_ALIGNED_PREVIEW_RGBA_BYTES;
            result.preview = {HIFACE_ALIGNED_PREVIEW_SIDE, HIFACE_ALIGNED_PREVIEW_SIDE, std::vector<uint8_t>(pixels, pixels + HIFACE_ALIGNED_PREVIEW_RGBA_BYTES)};
            HiFaceSearchResultsHandle raw = nullptr;
            result.search_status = hiface_search_query_v1(database.handle, features.data() + i * HIFACE_FACE_FEATURE_DIMENSION,
                HIFACE_FACE_FEATURE_DIMENSION, nullptr, nullptr, 1, HIFACE_DEFAULT_VERIFICATION_THRESHOLD, &raw);
            SearchResults owned(raw, hiface_search_results_destroy_v1);
            if (result.search_status != HIFACE_STATUS_OK) {
                result.label = accessMessage(result.search_status);
                if (result.label.empty()) result.label = std::string("Search failed: ") + statusName(result.search_status);
            } else {
                result.matches = readResults(raw);
                if (result.matches.empty()) result.label = "Not matched";
                else { const auto& match = result.matches.front(); std::ostringstream text; text << match.id << ", " << std::fixed << std::setprecision(2) << match.similarity; result.label = text.str(); ++report.matched; }
            }
        }
        report.faces.push_back(std::move(result));
    }
    stopped(); return report;
}
}
