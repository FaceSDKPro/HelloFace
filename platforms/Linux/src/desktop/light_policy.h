#pragma once
#include <cstdint>

namespace hiface_linux_demo {
inline constexpr int64_t kSearchLightFreshnessMs = 1500;
// Wait for a face before lighting up, then use the search's idle transition
// to switch off. Brief missed detections do not flicker the light.
class SearchLightPolicy {
public:
    void observe(bool has_face, bool idle) { on_ = !idle && (on_ || has_face); }
    void reset() { on_ = false; }
    bool on() const { return on_; }
private:
    bool on_ = false;
};
}
