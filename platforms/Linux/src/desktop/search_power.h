#pragma once
#include "hiface/hiface_contract_v1.h"
#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <utility>

namespace hiface_linux_demo {
// Preview is independent of the SDK's unchanged 200 ms idle analysis cadence.
// 预览独立于 SDK 保持不变的 200 ms 待机分析节奏。
inline constexpr int kSearchIdlePreviewFps = 10;
inline constexpr int64_t kSearchIdlePreviewIntervalMs = 1000 / kSearchIdlePreviewFps;
// Observe completed detections only. Skipped/failed/stale frames never prove absence.
// 只观察成功完成的检测；跳帧、错误和断流不能证明持续无人脸。
class SearchPowerPolicy {
public:
    void observe(int64_t now, bool has_face) {
        if (now < 0) { reset(); return; }
        if (last_frame_ >= 0 && (now < last_frame_ || now - last_frame_ >= 3000)) reset();
        last_frame_ = now;
        if (has_face) { no_face_since_ = -1; idle_ = false; return; }
        if (no_face_since_ < 0) no_face_since_ = now;
        idle_ = now - no_face_since_ >= HIFACE_IDLE_NO_FACE_TIMEOUT_MS;
    }
    void reset() { last_frame_ = no_face_since_ = -1; idle_ = false; }
    bool idle() const { return idle_; }
    int64_t analysisInterval() const { return idle_ ? HIFACE_IDLE_FRAME_INTERVAL_MS : 125; }
private:
    int64_t last_frame_ = -1, no_face_since_ = -1;
    bool idle_ = false;
};

// sysfs backlight is global: use an unambiguous writable device and restore on exit.
// sysfs 背光属于系统；仅使用唯一可写设备，离开搜索或析构时恢复，不覆盖外部亮度修改。
class SearchBacklight {
public:
    explicit SearchBacklight(std::filesystem::path root = "/sys/class/backlight") : root_(std::move(root)) {}
    ~SearchBacklight() { restore(); }
    SearchBacklight(const SearchBacklight&) = delete;
    SearchBacklight& operator=(const SearchBacklight&) = delete;
    void update(bool enabled, bool idle) {
        if (!enabled) { restore(); return; }
        if (!attempted_) {
            attempted_ = true;
            std::error_code error;
            std::filesystem::path selected;
            for (std::filesystem::directory_iterator it(root_, error), end; !error && it != end; it.increment(error)) {
                const auto path = it->path();
                int maximum = 0, current = 0;
                if (!read(path / "max_brightness", maximum) || maximum <= 0 ||
                    !read(path / "brightness", current) || current < 0 || current > maximum) continue;
                if (!selected.empty()) return; // Multiple screens require an explicit platform policy.
                selected = path;
            }
            if (error || selected.empty() || !read(selected / "max_brightness", maximum_) ||
                !read(selected / "brightness", saved_)) return;
            brightness_ = selected / "brightness";
        }
        if (brightness_.empty()) return;
        const int target = std::max(1, int((int64_t(maximum_) * (idle ? 10 : 90) + 50) / 100));
        if (target == applied_) return;
        int current = 0;
        if (applied_ >= 0 && read(brightness_, current) && current != applied_) saved_ = current;
        if (write(brightness_, target)) applied_ = target;
        else brightness_.clear(); // Unsupported permissions must not retry on every frame.
    }
    void restore() {
        int current = 0;
        if (applied_ >= 0 && read(brightness_, current) && current == applied_) write(brightness_, saved_);
        brightness_.clear(); attempted_ = false; applied_ = -1;
    }
private:
    static bool read(const std::filesystem::path& path, int& value) {
        std::ifstream input(path); return bool(input >> value);
    }
    static bool write(const std::filesystem::path& path, int value) {
        std::ofstream output(path); output << value << '\n'; output.close(); return bool(output);
    }
    std::filesystem::path root_, brightness_;
    bool attempted_ = false;
    int maximum_ = 0, saved_ = 0, applied_ = -1;
};
}
