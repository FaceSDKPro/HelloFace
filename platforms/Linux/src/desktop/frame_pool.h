#pragma once
#include "camera.h"
#include <array>
#include <memory>
namespace hiface_linux_demo {
// Capture is the sole writer. Never recycle a frame retained by the SDK, UI,
// or a caller's snapshot; overload drops frames instead of growing memory.
// 采集线程是唯一写入方；SDK、UI 或调用方快照仍持有的帧不可复用，过载时丢帧而不扩张内存。
class CameraFramePool {
public:
    // Return no frame when all five slots are retained, allowing capture to drop work under load.
    std::shared_ptr<CameraFrame> acquire() {
        for (auto& frame : frames_) {
            if (!frame) frame = std::make_shared<CameraFrame>();
            if (frame.use_count() == 1) return frame;
        }
        return {};
    }
private:
    std::array<std::shared_ptr<CameraFrame>, 5> frames_{};
};
}
