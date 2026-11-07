#pragma once
#include "sdk_helpers.h"
#include <memory>

namespace hiface_linux_demo {
struct CameraFrame;

// Preview frames update independently of the current analyzed pair's result.
struct RgbIrView {
    bool running = true;
    bool idle = false; // The renderer can reduce paint cadence while both previews remain live.
    std::string guidance = "Waiting...";
    CameraSearchScores scores;
    std::shared_ptr<const CameraFrame> rgb, ir;
};

struct RgbIrSearchPage {
    static constexpr const char* route = "uvc-camera-face-search";
    static constexpr const char* title = "Dual-Camera Face Search";
    static constexpr const char* status = "Connect both cameras, then select their devices in Settings.";
};
}
