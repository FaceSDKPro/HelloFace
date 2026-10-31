#pragma once
#include <cstdint>

namespace hiface_demo {
// UI cadence only; the SDK retains its own no-face analysis and authorization policy.
// 仅控制 UI 节奏；SDK 保留自身的无人脸分析与授权策略。
class SearchPreviewPower {
public:
    static constexpr int64_t preview_interval_ms = 100;
    static constexpr int64_t analysis_interval_ms = 200;
    void observe(int64_t now, bool has_face) {
        if (now < 0) { reset(); return; }
        if (last_detection_ >= 0 && (now < last_detection_ || now - last_detection_ >= 3000)) reset();
        last_detection_ = now;
        if (has_face) { no_face_since_ = -1; idle_ = false; return; }
        if (no_face_since_ < 0) no_face_since_ = now;
        idle_ = now - no_face_since_ >= 10000;
    }
    void reset() { last_detection_ = no_face_since_ = -1; idle_ = false; }
    bool idle() const { return idle_; }
private:
    int64_t last_detection_ = -1, no_face_since_ = -1;
    bool idle_ = false;
};
}
