#pragma once
#include <memory>
#include <string>

namespace hiface_linux_demo {
struct CameraFrame;

enum class LivenessState { pending, passed, rejected };
// An immutable view of one run. The current liveness badge and last confirmed
// identity have separate lifetimes while the RGB and IR previews update.
struct RgbIrView {
    bool running = true;
    bool idle = false; // The renderer can reduce paint cadence while both previews remain live.
    LivenessState liveness = LivenessState::pending;
    std::string guidance = "Opening RGB and IR cameras...";
    std::string latest_match;
    std::shared_ptr<const CameraFrame> rgb, ir;
};

struct RgbIrSearchPage {
    static constexpr const char* route = "uvc-camera-face-search";
    static constexpr const char* title = "Dual-Camera Face Search";
    static constexpr const char* description = "RGB identity search | IR liveness";
    static constexpr const char* status = "Connect both cameras, then select their devices in Settings.";
};
}
