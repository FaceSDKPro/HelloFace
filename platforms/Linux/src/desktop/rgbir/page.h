#pragma once
#include "sdk_helpers.h"
#include "search_frame_image.h"
#include <memory>

namespace hiface_linux_demo {
struct CameraFrame;

// Preview frames update independently of the current analyzed pair's result.
struct RgbIrView {
    std::shared_ptr<const SearchFrameImage> frame_image;
    bool running = true;
    bool idle = false; // The renderer can reduce paint cadence while the RGB preview remains live.
    std::string guidance = "Waiting...";
    CameraSearchScores scores;
    std::shared_ptr<const CameraFrame> rgb;
};

struct RgbIrSearchPage {
    static constexpr const char* route = "uvc-camera-face-search";
    static constexpr const char* title = "Dual-Camera Face Search";
    static constexpr const char* status = "Connect both cameras, then select their devices in Settings.";
};
}
