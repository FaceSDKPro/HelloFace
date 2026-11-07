#pragma once
#include "camera.h"
#include "lighting.h"
#include "rgbir/settings.h"
#include "hiface/hiface_linux.h"
#include <optional>

#if !HIFACE_LINUX_HAS_RGBIR_SEARCH_V1
#error "This Demo requires the Linux SDK with public RGB/IR paired search v1"
#endif

namespace hiface_linux_demo::rgbir {
struct Pair;

struct Sample {
    HiFaceSearchCameraResultV1 search{};
    HiFaceSearchInfraredResultV1 infrared{};
};

// One worker owns the session. The caller keeps the database alive for its lifetime.
class SearchSession {
public:
    SearchSession(Database& database, const RgbIrSettings& settings);
    std::optional<Sample> process(const CameraFrame& rgb, const CameraFrame& ir, const Pair& pair, int64_t now);
    bool detectInfraredPresence(CameraFrame& ir);
private:
    Database& database_;
    Session session;
};

CameraSearchScores searchScores(const Sample& sample);
SearchLightColor searchStatusColor(const Sample& sample);
std::string searchGuidance(const Sample& sample);
}
