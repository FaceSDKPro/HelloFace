#pragma once
#include "camera.h"
#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cstdlib>
#include <exception>
#include <functional>
#include <mutex>
#include <optional>
#include <thread>

namespace hiface_linux_demo::rgbir {
constexpr int64_t max_skew_ms = 50, max_age_ms = 150, pair_gap_ms = 500, pair_timeout_ms = 5000;

int64_t nowMs();

struct Stamp {
    uint64_t sequence = 0;
    int64_t time = 0;
};
struct Pair {
    uint64_t id = 0;
    Stamp rgb, ir;
    int64_t captureTime() const { return std::min(rgb.time, ir.time); }
    int64_t age(int64_t now) const { return now - captureTime(); }
    int64_t skew() const { return std::abs(rgb.time - ir.time); }
};
struct Slot {
    RawCameraFrame frame;
    Stamp pending, last;
    void received(int64_t now);
};

class Pairing {
public:
    Slot rgb, ir;
    std::optional<Pair> take(int64_t now);
private:
    static void expire(Stamp& stamp, int64_t now);
    uint64_t pair_id_ = 0;
};

struct CapturedPair {
    Pair stamp;
    RawCameraFrame rgb, ir;
};
struct CaptureProgress {
    int64_t last_pair_at;
    int64_t stream_started_at = 0;
    uint64_t paired = 0, replaced = 0, expired = 0;
};

// One complete pending pair. Swaps recycle raw buffers and isolate the pair
// borrowed by inference from capture. The capture thread never waits on Core.
class LatestPair {
public:
    explicit LatestPair(int64_t start) : progress_{start} {}
    void publish(const Pair& stamp, RawCameraFrame& rgb, RawCameraFrame& ir, int64_t now);
    void fail(std::exception_ptr error);
    bool waitTake(int64_t due, CapturedPair& output);
    CaptureProgress progress();
private:
    std::mutex mutex_;
    std::condition_variable changed_;
    std::exception_ptr error_;
    CapturedPair pair_;
    CaptureProgress progress_;
    bool ready_ = false;
};

class Capture {
public:
    using Preview = std::function<void(const RawCameraFrame&, const RawCameraFrame&)>;
    using Lighting = std::function<void(bool)>;
    Capture(Camera& rgb, Camera& ir, LatestPair& latest, Preview preview, Lighting lighting);
    ~Capture();
    // Preview may idle; infrared stays on for this capture worker's lifetime.
    void setSearchState(bool idle) {
        idle_.store(idle, std::memory_order_relaxed);
    }
private:
    std::atomic<bool> stop_{false};
    std::atomic<bool> idle_{false}; // Written by search, read by capture.
    std::thread worker_;
};
}
