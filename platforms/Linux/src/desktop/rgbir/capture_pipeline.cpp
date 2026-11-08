#include "capture_pipeline.h"
#include "search_power.h"
#include <chrono>
#include <time.h>

namespace hiface_linux_demo::rgbir {
namespace {
constexpr int camera_poll_ms = 60;
constexpr int64_t preview_interval_ms = 80;
}

int64_t nowMs() {
    timespec time{};
    if (clock_gettime(CLOCK_MONOTONIC, &time) != 0) throw DemoError{"Cannot read the monotonic clock"};
    return static_cast<int64_t>(time.tv_sec) * 1000 + time.tv_nsec / 1000000;
}

void Slot::received(int64_t now) {
    pending = {};
    const auto time = frame.monotonic_timestamp_ms;
    // An invalid replacement has already overwritten the old pixels.
    if (time <= last.time || time > now) return;
    last = pending = {last.sequence + 1, time};
}

std::optional<Pair> Pairing::take(int64_t now) {
    expire(rgb.pending, now);
    expire(ir.pending, now);
    if (!rgb.pending.sequence || !ir.pending.sequence) return std::nullopt;
    const auto skew = rgb.pending.time - ir.pending.time;
    if (std::abs(skew) > max_skew_ms) {
        // The newer frame can still pair with the next frame from the other camera.
        (skew < 0 ? rgb.pending : ir.pending) = {};
        return std::nullopt;
    }
    Pair pair{++pair_id_, rgb.pending, ir.pending};
    rgb.pending = ir.pending = {};
    return pair;
}

void Pairing::expire(Stamp& stamp, int64_t now) {
    if (stamp.time > now || now - stamp.time > max_age_ms) stamp = {};
}

void LatestPair::publish(const Pair& stamp, RawCameraFrame& rgb, RawCameraFrame& ir, int64_t now) {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!progress_.paired || now - progress_.last_pair_at >= pair_gap_ms)
            progress_.stream_started_at = stamp.captureTime();
        if (ready_) ++progress_.replaced;
        ready_ = true;
        ++progress_.paired;
        progress_.last_pair_at = now;
        pair_.stamp = stamp;
        std::swap(rgb, pair_.rgb);
        std::swap(ir, pair_.ir);
    }
    changed_.notify_one();
}

void LatestPair::fail(std::exception_ptr error) {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        error_ = error;
    }
    changed_.notify_one();
}

bool LatestPair::waitTake(int64_t due, CapturedPair& output) {
    std::unique_lock<std::mutex> lock(mutex_);
    // Wake periodically to observe shutdown and transport timeouts even
    // when one camera never sends a buffer.
    const auto delay = due - nowMs();
    changed_.wait_for(lock, std::chrono::milliseconds(delay > 0 ? std::min<int64_t>(delay, 80) : 80), [&] {
        return error_ || (ready_ && nowMs() >= due);
    });
    if (error_) std::rethrow_exception(error_);
    const auto now = nowMs();
    if (!ready_ || now < due) return false;
    ready_ = false;
    if (pair_.stamp.age(now) > max_age_ms) { ++progress_.expired; return false; }
    std::swap(output, pair_);
    return true;
}

CaptureProgress LatestPair::progress() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (error_) std::rethrow_exception(error_);
    return progress_;
}

Capture::Capture(Camera& rgb, Camera& ir, LatestPair& latest, Preview preview, Lighting lighting)
    : worker_([this, &rgb, &ir, &latest, preview = std::move(preview), lighting = std::move(lighting)] {
    try {
        Pairing pending;
        int64_t next_preview = 0;
        while (!stop_.load(std::memory_order_relaxed)) {
            const auto ready = Camera::waitForFrames(rgb, ir, camera_poll_ms);
            if (stop_.load(std::memory_order_relaxed)) break;
            const bool read_rgb = (ready & 1u) && rgb.readRaw(pending.rgb.frame);
            const bool read_ir = (ready & 2u) && ir.readRaw(pending.ir.frame);
            if (!read_rgb && !read_ir && !lighting) continue;
            const auto now = nowMs();
            if (read_rgb) pending.rgb.received(now);
            if (read_ir) pending.ir.received(now);
            if (const auto pair = pending.take(now)) {
                // Preview borrows the raw frames before publish swaps out their buffers.
                // Its cadence is independent of inference.
                if (preview && now >= next_preview) {
                    next_preview = now + (idle_.load(std::memory_order_relaxed)
                        ? kSearchIdlePreviewIntervalMs : preview_interval_ms);
                    preview(pending.rgb.frame, pending.ir.frame);
                }
                latest.publish(*pair, pending.rgb.frame, pending.ir.frame, now);
            }
            if (lighting) lighting(light_on_.load(std::memory_order_relaxed));
        }
    } catch (...) { latest.fail(std::current_exception()); }
    try { if (lighting) lighting(false); }
    catch (...) { latest.fail(std::current_exception()); }
}) {}
Capture::~Capture() { stop_.store(true, std::memory_order_relaxed); worker_.join(); }
}
