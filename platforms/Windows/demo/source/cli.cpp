#include "demo_service.h"
#include "data_exchange.h"
#include "win_util.h"
#include <iostream>

namespace {
using namespace hiface_demo;
void usage() {
    std::cout << "HiFace Windows x64 / CPU\n"
        "  hiface_cli self-test\n"
        "  hiface_cli detect IMAGE [--detailed]\n"
        "  hiface_cli capture IMAGE FEATURE.hf1 [PREVIEW.png]\n"
        "  hiface_cli compare IMAGE_A IMAGE_B\n"
        "  hiface_cli compare-features FEATURE_A.hf1 FEATURE_B.hf1\n"
        "  hiface_cli enroll DATABASE PERSON_ID IMAGE\n"
        "  hiface_cli upsert DATABASE PERSON_ID IMAGE [GROUP TAG]\n"
        "  hiface_cli search DATABASE IMAGE [GROUP TAG]\n"
        "  hiface_cli count DATABASE [GROUP TAG]\n"
        "  hiface_cli list DATABASE [GROUP TAG]\n"
        "  hiface_cli get DATABASE PERSON_ID\n"
        "  hiface_cli delete DATABASE PERSON_ID\n"
        "  hiface_cli metadata DATABASE PERSON_ID GROUP TAG\n"
        "  hiface_cli import-json DATABASE DATASET.json\n"
        "  hiface_cli export-json DATABASE DATASET.json [GROUP TAG]\n"
        "  image-search DATABASE IMAGE  (up to 10 faces, Top-1 / 0.80, no liveness)\n"
        "Images: JPEG/PNG/BMP/TIFF via Windows WIC. HF1 uses the shared Core codec.\n"
        "enroll rejects duplicate IDs; upsert/import-json overwrite by Face ID.\n";
}
}
int wmain(int argc, wchar_t** argv) {
    using namespace hiface_demo;
    if (argc == 2 && std::wstring(argv[1]) == L"--help") { usage(); return 0; }
    if (argc < 2) { usage(); return 2; }
    const std::wstring command = argv[1];
    try {
        SetConsoleOutputCP(CP_UTF8); ComApartment com; initializeLog("cli");
        if (command == L"self-test" && argc == 2) { testWindowsImageDecoder(); runSelfTest(); return 0; }
        if (command == L"compare-features" && argc == 4) {
            const auto score = compareFeatureText(readFeatureFile(argv[2]), readFeatureFile(argv[3]));
            std::cout << "similarity=" << score << '\n'; return 0;
        }
        if (command == L"image-search" && argc == 4) {
            DemoService sdk(argv[2]);
            const auto result = sdk.searchImage(readImage(argv[3], true));
            if (!result) throw std::runtime_error("Image search cancelled");
            std::cout << "faces=" << result->faces.size() << " matched=" << result->matched
                << " emptyLibrary=" << result->empty_library << " topK=1 threshold=0.80 liveness=off\n";
            for (size_t i = 0; i < result->faces.size(); ++i) {
                const auto& face = result->faces[i];
                std::cout << "face=" << i + 1 << " box=" << face.face.x << ',' << face.face.y << ',' << face.face.width << ',' << face.face.height
                    << " status=" << face.status << " result=" << face.label << '\n';
            }
            return 0;
        }
        // Metadata commands open only the database; inference is created only for image work.
        // 资料管理只开数据库；仅图片能力创建推理会话。
        const bool database_command = command == L"count" || command == L"list" || command == L"get" || command == L"delete"
            || command == L"metadata" || command == L"import-json" || command == L"export-json";
        if (database_command) {
            const bool valid = ((command == L"count" || command == L"list") && (argc == 3 || argc == 5))
                || ((command == L"get" || command == L"delete" || command == L"import-json") && argc == 4)
                || (command == L"metadata" && argc == 6) || (command == L"export-json" && (argc == 4 || argc == 6));
            if (!valid) { usage(); return 2; }
            Gallery gallery(argv[2]);
            if (command == L"count" || command == L"list") {
                const std::string group = argc == 5 ? utf8(argv[3]) : "", tag = argc == 5 ? utf8(argv[4]) : "";
                if (command == L"list") for (uint32_t offset = 0;;) {
                    const auto page = gallery.list(offset, 1000, group, tag); if (page.empty()) break;
                    for (const auto& person : page) std::cout << "id=" << person.id << " group=" << person.group << " tag=" << person.tag << " updated=" << person.updated << '\n';
                    offset += static_cast<uint32_t>(page.size());
                }
                std::cout << "count=" << gallery.count(group, tag) << '\n';
            } else if (command == L"get") std::cout << gallery.get(utf8(argv[3])).feature << '\n';
            else if (command == L"delete") std::cout << "deleted=" << gallery.remove(utf8(argv[3])) << '\n';
            else if (command == L"metadata") gallery.updateMetadata(utf8(argv[3]), utf8(argv[4]), utf8(argv[5]));
            else if (command == L"import-json") {
                const auto result = importDataset(gallery, argv[3]);
                std::cout << "processed=" << result.processed << " saved=" << result.saved << " failed=" << result.failed << '\n';
                if (result.failed) return 1;
            } else std::cout << "exported=" << exportDataset(gallery, argv[3], argc == 6 ? utf8(argv[4]) : "", argc == 6 ? utf8(argv[5]) : "") << '\n';
            return 0;
        }
        if (!((command == L"detect" && (argc == 3 || (argc == 4 && std::wstring(argv[3]) == L"--detailed")))
            || (command == L"capture" && (argc == 4 || argc == 5)) || (command == L"compare" && argc == 4)
            || (command == L"enroll" && argc == 5) || (command == L"upsert" && (argc == 5 || argc == 7))
            || (command == L"search" && (argc == 4 || argc == 6)))) { usage(); return 2; }
        const bool gallery_command = command == L"enroll" || command == L"upsert" || command == L"search";
        DemoService sdk(gallery_command ? std::filesystem::path(argv[2]) : std::filesystem::path(L":memory:"));
        sdk.useSearch(false);
        if (command == L"detect") {
            const auto result = sdk.detectDetailed(readImage(argv[2]), 10, argc == 4);
            std::cout << "faces=" << result.faces.size() << '\n';
            for (const auto& detail : result.details) std::cout << "box=" << detail.face.x << ',' << detail.face.y << ',' << detail.face.width << ',' << detail.face.height
                << " confidence=" << detail.face.confidence << " mesh=" << detail.mesh.size() << " poseValid=" << detail.face.pose_valid << " metricsValid=" << detail.face.metrics_valid << '\n';
        } else if (command == L"capture") {
            const auto result = sdk.captureWithPreview(readImage(argv[2]));
            writeFeatureFile(argv[3], result.text);
            if (argc == 5) writeImage(argv[4], result.preview);
            std::cout << "captured=1 featureFormat=HF1 alignedSide=" << result.preview.width << '\n';
        } else if (command == L"compare") {
            const auto a = encodeFeature(sdk.capture(readImage(argv[2]))), b = encodeFeature(sdk.capture(readImage(argv[3])));
            std::cout << "similarity=" << compareFeatureText(a, b) << '\n';
        } else {
            const auto feature = sdk.capture(readImage(argv[command == L"search" ? 3 : 4]));
            if (command == L"search") {
                if (argc == 6) { SearchOptions options; options.group = utf8(argv[4]); options.tag = utf8(argv[5]); sdk.configureSearch(options); }
                const auto matches = sdk.query(decodeFeature(encodeFeature(feature)));
                for (const auto& match : matches) std::cout << "id=" << match.first << " score=" << match.second << '\n';
                std::cout << "matches=" << matches.size() << '\n';
            } else {
                Gallery gallery(argv[2]);
                gallery.save({{utf8(argv[3]), argc == 7 ? utf8(argv[5]) : "", argc == 7 ? utf8(argv[6]) : "", encodeFeature(feature), 0}}, command == L"upsert");
                std::cout << "enrolled=" << utf8(argv[3]) << " gallery=" << gallery.count() << '\n';
            }
        }
        return 0;
    } catch (const std::exception& error) { writeLog(error.what()); std::cerr << error.what() << '\n'; return 1; }
}
