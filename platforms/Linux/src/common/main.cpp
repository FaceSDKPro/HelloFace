// Standalone consumer: public C ABI only; no OpenCV, camera or private Core headers.
// 独立接入示例：仅使用公开 C ABI，不依赖 OpenCV、相机或私有 Core 头文件。
#include "sdk_helpers.h"
#include "image_decode.h"
#include "gallery.h"
#include "image_search.h"
#include "synthetic_data.h"

#include <array>
#include <algorithm>
#include <cctype>
#include <cmath>
#include <exception>
#include <fstream>
#include <filesystem>
#include <iostream>
#include <limits>
#include <memory>
#include <string>
#include <vector>

namespace {
using namespace hiface_linux_demo;

Feature capture(Session& session, const Image& image) {
    Feature feature{};
    check(hiface_session_capture_rgba_v1(session.handle, image.rgba.data(), image.rgba.size(),
            image.width, image.height, feature.data(), feature.size(), nullptr, 0), "capture largest face");
    return feature;
}

void enroll(Database& database, const char* id, const Feature& feature) {
    FeatureText text{};
    check(hiface_feature_encode_text_v1(feature.data(), feature.size(), text.data(), text.size()), "encode HF1");
    HiFaceSearchFeatureEntryV1 entry{sizeof(entry), id, "", "", text.data(),
        HIFACE_FEATURE_TEXT_LENGTH, 0, HIFACE_FEATURE_SPACE_ID};
    const HiFaceSearchFeatureEntryV1* entries[] = {&entry};
    check(hiface_search_upsert_v1(database.handle, entries, 1), "upsert face");
}

uint32_t search(Database& database, const Feature& feature, bool expect_self = false) {
    HiFaceSearchResultsHandle raw = nullptr;
    check(hiface_search_query_v1(database.handle, feature.data(), feature.size(), nullptr, nullptr,
            5, .8f, &raw), "search faces");
    std::unique_ptr<HiFaceSearchResultsOpaque, decltype(&hiface_search_results_destroy_v1)>
        results(raw, hiface_search_results_destroy_v1);
    const auto count = hiface_search_results_count_v1(raw);
    if (expect_self) require(count == 1, "Expected one self-match");
    for (uint32_t i = 0; i < count; ++i) {
        HiFaceSearchEntryV1 entry{};
        entry.struct_size = sizeof(entry);
        float score = 0;
        check(hiface_search_results_get_v1(raw, i, &entry, &score), "read match");
        if (expect_self) require(std::string(entry.face_id) == "synthetic" && score > .9999f,
                "Unexpected self-match identity or score");
        std::cout << "match id=" << entry.face_id << " score=" << score << '\n';
    }
    std::cout << "matches=" << count << '\n';
    return count;
}

void detect(Session& session, const Image& image, bool expect_blank = false) {
    std::array<HiFaceFaceV1, HIFACE_MAX_FACES> faces{};
    HiFaceDetectionRequestV1 request{sizeof(request), HIFACE_C_API_VERSION_V1,
        HIFACE_MAX_FACES, 1};
    HiFaceFrameResultV1 result{};
    result.struct_size = sizeof(result);
    result.faces = faces.data();
    result.capacity = faces.size();
    check(hiface_session_process_rgba_v1(session.handle, image.rgba.data(), image.rgba.size(),
            image.width, image.height, &request, &result), "detect RGBA");
    if (expect_blank) require(result.count == 0, "Expected no faces in blank image");
    std::cout << "faces=" << result.count << '\n';
    for (uint32_t i = 0; i < result.count; ++i) {
        const auto& face = faces[i];
        std::cout << "face box=" << face.x << ',' << face.y << ',' << face.width << ',' << face.height
                  << " confidence=" << face.confidence << " mesh_points=" << face.mesh_count << '\n';
    }
}

void selfTest(Session& session) {
    constexpr int side = 112;
    Image blank{side, side, std::vector<uint8_t>(side * side * 4, 128)};
    detect(session, blank, true);
    Feature rejected{};
    require(hiface_session_capture_rgba_v1(session.handle, blank.rgba.data(), blank.rgba.size(),
            side, side, rejected.data(), rejected.size(), nullptr, 0) == HIFACE_STATUS_IMAGE_NO_FACE,
            "Expected IMAGE_NO_FACE from blank capture");

    std::vector<uint8_t> pixels(side * side * 3);
    uint32_t state = 17;
    for (auto& value : pixels) { state = state * 1664525u + 1013904223u; value = state >> 24; }
    const float landmarks[] = {38.2946f, 51.6963f, 73.5318f, 51.5014f,
        56.0252f, 71.7366f, 41.5493f, 92.3655f, 70.7299f, 92.2041f};
    Feature feature{};
    check(hiface_session_extract_feature_v1(session.handle, pixels.data(), pixels.size(), side, side,
            HIFACE_IMAGE_RGB, landmarks, 10, feature.data(), feature.size()), "extract synthetic feature");
    double norm = 0;
    for (float value : feature) { require(std::isfinite(value), "Non-finite feature"); norm += double(value) * value; }
    require(std::abs(norm - 1) < 1e-5, "Expected normalized feature");
    float score = 0;
    check(hiface_feature_compare_v1(feature.data(), feature.data(), feature.size(), &score), "compare feature");
    require(score > .9999f, "Expected self-comparison near 1");
    Database database(":memory:");
    enroll(database, "synthetic", feature);
    search(database, feature, true);

    std::vector<uint8_t> yuv(side * side * 3 / 2, 128);
    HiFaceYuv420FrameV1 frame{};
    frame.struct_size = sizeof(frame);
    frame.width = frame.height = side;
    frame.y = {yuv.data(), side * side, side, 1};
    frame.u = {yuv.data() + side * side, side * side / 4, side / 2, 1};
    frame.v = {yuv.data() + side * side * 5 / 4, side * side / 4, side / 2, 1};
    frame.range = HIFACE_YUV_RANGE_VIDEO;
    frame.matrix = HIFACE_YUV_MATRIX_BT601;
    HiFaceDetectionRequestV1 request{sizeof(request), HIFACE_C_API_VERSION_V1, 1, 0};
    HiFaceFaceV1 face{};
    HiFaceFrameResultV1 result{};
    result.struct_size = sizeof(result); result.faces = &face; result.capacity = 1;
    HiFaceFlowEventV1 event{}; event.struct_size = sizeof(event);
    check(hiface_session_process_camera_yuv420_v1(session.handle, &frame, &request, 0, &result, &event),
            "process synthetic YUV frame");
    require(result.count == 0 && result.frame_id == 1, "Unexpected YUV result");
    std::cout << "Synthetic self-test passed: five CPU models, RGBA/YUV, feature, 1:1, HF1 and SQLite search.\n";
}

void usage() {
    std::cerr << "Usage:\n"
        "  hiface_demo self-test --builtin\n"
        "  hiface_demo detect --builtin IMAGE\n"
        "  hiface_demo compare --builtin FIRST_IMAGE SECOND_IMAGE\n"
        "  hiface_demo enroll --builtin DATABASE FACE_ID IMAGE\n"
        "  hiface_demo search --builtin DATABASE IMAGE\n"
        "  hiface_demo search-faces --builtin DATABASE IMAGE (multi-face JSON)\n"
        "  hiface_demo feature --builtin IMAGE\n"
        "  hiface_demo capture --builtin IMAGE ALIGNED_PREVIEW.ppm\n"
        "  hiface_demo gallery-list DATABASE [GROUP TAG OFFSET]\n"
        "  hiface_demo gallery-get DATABASE FACE_ID\n"
        "  hiface_demo gallery-delete DATABASE FACE_ID\n"
        "  hiface_demo gallery-update DATABASE FACE_ID GROUP TAG\n"
        "  hiface_demo gallery-import DATABASE FEATURES.json\n"
        "  hiface_demo gallery-export DATABASE FEATURES.json [GROUP TAG]\n"
        "  hiface_demo generate-demo-features OUTPUT.json (10k synthetic vectors; no person data)\n"
        "Gallery commands do not load models. Import replaces matching IDs in independent batches.\n"
        "Images: JPEG, PNG, BMP or binary PPM.\n";
}
int galleryCommand(int argc, char** argv) {
    const std::string command = argv[1];
    require((command == "gallery-list" && (argc == 3 || argc == 6))
        || ((command == "gallery-get" || command == "gallery-delete" || command == "gallery-import") && argc == 4)
        || (command == "gallery-update" && argc == 6)
        || (command == "gallery-export" && (argc == 4 || argc == 6)), "Invalid gallery command. See --help");
    Database database(argv[2]);
    if (command == "gallery-list" || command == "gallery-get") {
        std::vector<GalleryEntry> rows;
        if (command == "gallery-get") rows.push_back(getEntry(database, argv[3]));
        else {
            uint32_t offset = 0;
            if (argc == 6) {
                const std::string value = argv[5]; size_t end = 0; const auto number = std::stoul(value, &end);
                require(end == value.size() && number <= UINT32_MAX && value.find_first_not_of("0123456789") == std::string::npos, "Invalid page offset");
                offset = static_cast<uint32_t>(number);
            }
            rows = listGallery(database, argc == 6 ? argv[3] : "", argc == 6 ? argv[4] : "", offset, 100);
        }
        for (const auto& row : rows) {
            std::cout << "{\"faceId\":" << jsonQuote(row.id) << ",\"group\":" << jsonQuote(row.group)
                << ",\"tag\":" << jsonQuote(row.tag) << ",\"updateTimeMillis\":" << row.updated;
            if (command == "gallery-get") std::cout << ",\"feature\":" << jsonQuote(row.feature) << ",\"featureSpaceId\":" << jsonQuote(HIFACE_FEATURE_SPACE_ID);
            std::cout << "}\n";
        }
        uint64_t count = 0; check(hiface_search_count_v1(database.handle, command == "gallery-list" && argc == 6 ? argv[3] : nullptr,
            command == "gallery-list" && argc == 6 ? argv[4] : nullptr, &count), "count gallery");
        std::cout << "total=" << count << " returned=" << rows.size() << '\n';
    } else if (command == "gallery-delete") {
        uint64_t deleted = 0; check(hiface_search_delete_v1(database.handle, argv[3], &deleted), "delete face"); std::cout << "deleted=" << deleted << '\n';
    } else if (command == "gallery-update") {
        check(hiface_search_update_metadata_v1(database.handle, argv[3], argv[4], argv[5], 0), "update metadata"); std::cout << "updated\n";
    } else if (command == "gallery-import") {
        const auto rows = readFeatureFile(argv[3]); size_t saved = 0;
        try {
            while (saved < rows.size()) { const auto count = std::min<size_t>(100, rows.size() - saved); saveEntries(database, rows, saved, count, true); saved += count; }
        } catch (...) { std::cerr << "Import stopped; previous batches saved=" << saved << '\n'; throw; }
        std::cout << "saved=" << saved << '\n';
    } else {
        require(!std::filesystem::exists(argv[3]), "Export file already exists; choose a new path");
        exportFeatureFile(database, argv[3], argc == 6 ? argv[4] : "", argc == 6 ? argv[5] : ""); std::cout << "exported\n";
    }
    return 0;
}
} // namespace

int main(int argc, char** argv) {
    if (argc == 2 && std::string(argv[1]) == "--help") { usage(); return 0; }
    if (argc < 3) { usage(); return 2; }
    const std::string command = argv[1];
    if (command.rfind("gallery-", 0) != 0 && command != "generate-demo-features"
            && std::string(argv[2]) != "--builtin") { usage(); return 2; }
    if (command.rfind("gallery-", 0) != 0 && !((command == "generate-demo-features" && argc == 3) || (command == "self-test" && argc == 3) || (command == "detect" && argc == 4)
            || (command == "compare" && argc == 5) || (command == "enroll" && argc == 6)
            || ((command == "search" || command == "search-faces") && argc == 5) || (command == "feature" && argc == 4)
            || (command == "capture" && argc == 5))) { usage(); return 2; }
    try {
        require(hiface_get_api_version_v1() == HIFACE_C_API_VERSION_V1, "C ABI version mismatch");
        if (command == "generate-demo-features") {
            writeSyntheticDemoFeatures(argv[2]);
            std::cout << "Generated 10000 synthetic vectors; no models, photos or biometric samples used.\n";
            return 0;
        }
        if (command.rfind("gallery-", 0) == 0) return galleryCommand(argc, argv);
        Session session;
        if (command == "detect") loadBaseModels(session);
        else loadModels(session, argv[2], command == "self-test");
        if (command == "self-test") selfTest(session);
        else if (command == "detect") detect(session, readImage(argv[3]));
        else if (command == "feature" || command == "capture") {
            std::vector<uint8_t> preview;
            const auto feature = captureFeature(session, readImage(argv[3]), command == "capture" ? &preview : nullptr);
            if (command == "capture") savePreview(argv[4], preview);
            const auto text = encodeFeature(feature);
            std::cout << "featureSpaceId=" << HIFACE_FEATURE_SPACE_ID << "\nfeature=" << text.data() << '\n';
        }
        else if (command == "search-faces") {
            Database database(argv[3]); const auto image = readSearchImage(argv[4]); const auto report = searchImage(session, database, image);
            std::cout << "{\"width\":" << image.width << ",\"height\":" << image.height << ",\"libraryCount\":" << report.library_count
                      << ",\"faceCount\":" << report.faces.size() << ",\"matchedCount\":" << report.matched << ",\"faces\":[";
            for (size_t i = 0; i < report.faces.size(); ++i) {
                const auto& face = report.faces[i]; if (i) std::cout << ',';
                std::cout << "{\"index\":" << i+1 << ",\"x\":" << face.x << ",\"y\":" << face.y << ",\"width\":" << face.width << ",\"height\":" << face.height
                          << ",\"captureStatus\":" << jsonQuote(statusName(face.capture_status)) << ",\"searchStatus\":" << (face.capture_status == HIFACE_STATUS_OK ? jsonQuote(statusName(face.search_status)) : "null")
                          << ",\"matched\":" << (face.matched() ? "true" : "false") << ",\"label\":" << jsonQuote(face.label);
                if (face.matched()) std::cout << ",\"faceId\":" << jsonQuote(face.matches.front().id) << ",\"score\":" << face.matches.front().similarity;
                std::cout << '}';
            }
            std::cout << "]}\n";
        }
        else if (command == "compare") {
            const auto first = capture(session, readImage(argv[3]));
            const auto second = capture(session, readImage(argv[4]));
            float score = 0;
            check(hiface_feature_compare_v1(first.data(), second.data(), first.size(), &score), "compare faces");
            std::cout << "similarity=" << score << '\n';
        } else {
            const auto image = readImage(argv[command == "enroll" ? 5 : 4]);
            const auto feature = command == "enroll" ? captureEnrollmentPhoto(session, image) : capture(session, image);
            Database database(argv[3]);
            if (command == "enroll") { enroll(database, argv[4], feature); std::cout << "enrolled id=" << argv[4] << '\n'; }
            else search(database, feature);
        }
        return 0;
    } catch (const DemoError& error) {
        std::cerr << error.message << '\n';
        return 1;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    } catch (...) {
        std::cerr << "Unexpected processing failure\n";
        return 1;
    }
}
