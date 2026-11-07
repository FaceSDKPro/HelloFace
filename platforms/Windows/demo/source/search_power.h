#pragma once
#include <cstdint>

namespace hiface_demo {
inline bool searchOverlayFresh(int64_t now, int64_t preview, int64_t analysis) {
    return preview >= 0 && analysis >= 0 && now >= preview && now >= analysis
        && now - preview <= 500 && now - analysis <= 1200;
}
// UI cadence only; the SDK retains its own no-face analysis and authorization policy.
// 仅控制 UI 节奏；SDK 保留自身的无人脸分析与授权策略。
class SearchPreviewPower {
public:
    static constexpr int64_t freshness_ms = 3000;
    int64_t previewInterval() const { return idle_ ? 100 : 40; }
    int64_t analysisInterval() const { return idle_ ? 200 : 125; }
    // Refresh even when the SDK skips frames: a stalled detector cannot prove absence.
    // SDK 连续跳帧时也检查时效；检测停滞不能证明持续无人脸。
    void expire(int64_t now) {
        if (now < 0 || (last_detection_ >= 0 && (now < last_detection_ || now - last_detection_ >= freshness_ms))) reset();
    }
    void observeFrame(int64_t captured, int64_t completed, bool has_face) {
        expire(completed);
        if (captured < 0 || completed < captured || completed - captured >= freshness_ms) { reset(); return; }
        observe(captured, has_face);
    }
    void observe(int64_t now, bool has_face) {
        expire(now);
        if (now < 0 || now == last_detection_) return;
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
