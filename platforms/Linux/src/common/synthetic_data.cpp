#include "synthetic_data.h"
#include "gallery.h"
#include <cmath>
#include <filesystem>
#include <sstream>

namespace hiface_linux_demo {
void writeSyntheticDemoFeatures(const std::string& path) {
    require(!std::filesystem::exists(path), "Demo data output already exists");
    std::ostringstream json;
    json << "{\"schemaVersion\":1,\"featureFormat\":\"HF1\",\"featureSpaceId\":"
         << jsonQuote(HIFACE_FEATURE_SPACE_ID)
         << ",\"entryCount\":10000,\"dataKind\":\"synthetic-random-v1\",\"entries\":[";
    uint32_t state = 0x48494641u;
    for (unsigned i = 1; i <= 10000; ++i) {
        Feature feature{};
        double norm = 0;
        for (auto& value : feature) {
            state = state * 1664525u + 1013904223u;
            value = float(int32_t(state >> 8) - 8388608) / 8388608.f;
            norm += double(value) * value;
        }
        const auto scale = 1. / std::sqrt(norm);
        for (auto& value : feature) value = float(value * scale);
        const auto text = encodeFeature(feature);
        if (i != 1) json << ',';
        json << "{\"faceId\":\"synthetic-" << i << "\",\"feature\":" << jsonQuote(text.data())
             << ",\"group\":\"synthetic-demo\",\"tag\":\"not-a-person\",\"updateTimeMillis\":1}";
    }
    json << "]}\n";
    atomicWrite(path, json.str(), false);
}
}
