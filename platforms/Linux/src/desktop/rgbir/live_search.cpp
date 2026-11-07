#include "live_search.h"
#include "search_power.h"
#include <iostream>

namespace hiface_linux_demo::rgbir {
namespace {
constexpr int64_t active_interval_ms = 100; // Same admission interval as the Core camera search.
constexpr int64_t report_interval_ms = 2000;

struct TimingWindow {
    std::array<int64_t, 120> values{};
    size_t samples = 0, cursor = 0;
    void add(int64_t value) {
        values[cursor] = value;
        cursor = (cursor + 1) % values.size();
        samples = std::min(samples + 1, values.size());
    }
    std::string p95() const {
        if (!samples) return "-";
        auto sorted = values;
        std::sort(sorted.begin(), sorted.begin() + samples);
        return std::to_string(sorted[(samples * 95 + 99) / 100 - 1]);
    }
};
struct SearchStats {
    uint64_t accepted = 0, skipped = 0, decode_errors = 0, stale_after_decode = 0;
    uint64_t ir_passed = 0, ir_rejected = 0, ir_stale = 0;
    uint64_t rgb_faces = 0, ir_only_faces = 0;
    TimingWindow skew, age, decode, sdk;
    void report(const CaptureProgress& capture, bool idle) const {
        std::cerr << "[RGB/IR] idle=" << idle << " paired=" << capture.paired << " replaced=" << capture.replaced
            << " expired=" << capture.expired << " accepted=" << accepted << " skipped=" << skipped
            << " decode_errors=" << decode_errors << " stale_after_decode=" << stale_after_decode
            << " ir_passed=" << ir_passed << " ir_rejected=" << ir_rejected << " ir_stale=" << ir_stale
            << " rgb_faces=" << rgb_faces << " ir_only_faces=" << ir_only_faces
            << " | P95 ms skew=" << skew.p95() << " age=" << age.p95()
            << " decode=" << decode.p95() << " SDK=" << sdk.p95() << '\n';
    }
};

void openCamera(Camera& camera, const std::string& path, RgbIrCameraRole role, int rotation) {
    try {
        camera.openRgbIr(path, role, rotation);
    } catch (const DemoError& error) {
        throw DemoError{std::string(role == RgbIrCameraRole::rgb ? "RGB camera: " : "IR camera: ") + error.message};
    }
}
}

void runSearch(const std::string& database, const RgbIrSettings& settings, CameraRotation rotation,
               const std::atomic<bool>& stopping, bool diagnostics, const SearchCallbacks& callbacks) {
    verifyRgbIrDevices(settings);
    Database gallery(database.c_str());
    SearchSession search(gallery, settings);
    Camera rgb, ir;
    const bool saved_rotation = rotation == CameraRotation::settings;
    openCamera(rgb, settings.rgb_device, RgbIrCameraRole::rgb, saved_rotation ? settings.rgb_rotation : -1);
    openCamera(ir, settings.ir_device, RgbIrCameraRole::infrared, saved_rotation ? settings.ir_rotation : -1);
    Camera::verifyDistinct(rgb, ir);
    if (callbacks.opened) callbacks.opened(rgb.description(), ir.description());
    const auto start = nowMs();
    LatestPair latest(start);
    Capture capture(rgb, ir, latest, callbacks.preview, callbacks.lighting);
    CapturedPair pair;
    CameraFrame rgb_frame, ir_frame;
    SearchPowerPolicy power;
    SearchLightPolicy infrared_light;
    SearchStats stats;
    auto due = start, last_usable = start, next_report = start + report_interval_ms;
    int64_t power_stream = 0;
    int64_t interval = active_interval_ms;
    bool waiting_for_pair = true;
    while (!stopping.load(std::memory_order_relaxed)) {
        const bool available = latest.waitTake(due, pair);
        const auto progress = latest.progress();
        const auto now = nowMs();
        if (stopping.load(std::memory_order_relaxed)) break;
        if (diagnostics && now >= next_report) {
            stats.report(progress, power.idle());
            next_report = now + report_interval_ms;
        }
        if (now - progress.last_pair_at > pair_timeout_ms)
            throw DemoError{"No usable RGB/IR pair. Check both streams and V4L2 monotonic timestamps."};
        if (progress.paired && now - progress.last_pair_at <= callbacks.interruption_grace_ms)
            waiting_for_pair = false;
        else if (!waiting_for_pair) {
            // Reset standby and the view during a gap, while keeping the last IR lamp decision.
            power.reset();
            capture.setSearchState(false, infrared_light.on());
            if (callbacks.interrupted) callbacks.interrupted();
            waiting_for_pair = true;
        }
        if (!available) {
            if (now - last_usable > pair_timeout_ms)
                throw DemoError{"RGB/IR pairs expired before analysis. Check system load and camera mode."};
            continue;
        }
        try {
            Camera::decodeAnalysis(pair.rgb, rgb_frame);
            Camera::decodeAnalysis(pair.ir, ir_frame);
        } catch (const DemoError& error) {
            // A damaged frame is recoverable. Persistent decode failure is a
            // camera error and must never be displayed as an IR rejection.
            ++stats.decode_errors;
            if (nowMs() - last_usable > pair_timeout_ms)
                throw DemoError{"Repeated RGB/IR decode failure: " + error.message};
            due = nowMs() + active_interval_ms;
            continue;
        }
        const auto submitted = nowMs();
        stats.decode.add(submitted - now);
        // A fresh pair can expire during decoding. Keep the original camera timestamps.
        const auto age = pair.stamp.age(submitted);
        if (age > max_age_ms) {
            ++stats.stale_after_decode;
            if (submitted - last_usable > pair_timeout_ms)
                throw DemoError{"RGB/IR pairs keep expiring during frame preparation. Check system load and camera mode."};
            // Nothing reached the SDK. Take the next fresh pair without adding a throttle interval.
            continue;
        }
        last_usable = submitted;
        stats.age.add(age);
        stats.skew.add(pair.stamp.skew());
        const auto sample = search.process(rgb_frame, ir_frame, pair.stamp, submitted);
        bool has_face = false;
        bool ir_only_face = false;
        if (sample) {
            ++stats.accepted;
            const auto ir_status = sample->infrared.input_status;
            stats.ir_passed += ir_status == HIFACE_SEARCH_IR_PASSED;
            stats.ir_rejected += ir_status == HIFACE_SEARCH_IR_REJECTED;
            stats.ir_stale += ir_status == HIFACE_SEARCH_IR_STALE_PAIR;
            const bool rgb_face = (callbacks.lighting ? sample->search.detected_count : sample->search.face_count) != 0;
            // The search may skip IR detection when RGB has no face. Probe only for lamp wakeup.
            ir_only_face = callbacks.lighting && !rgb_face &&
                (sample->infrared.ir_detected_count != 0 || search.detectInfraredPresence(ir_frame));
            has_face = rgb_face || ir_only_face;
            interval = has_face ? active_interval_ms : HIFACE_IDLE_FRAME_INTERVAL_MS;
        } else ++stats.skipped;
        stats.sdk.add(nowMs() - submitted);
        due = submitted + interval;
        // Suppress completions after capture stalls. Inference can be slower
        // than max_age_ms while the capture thread continues producing fresh pairs.
        if (!sample || stopping.load(std::memory_order_relaxed)) continue;
        const auto current = latest.progress();
        const auto frame_time = pair.stamp.captureTime();
        const auto completed_at = nowMs();
        if (completed_at - current.last_pair_at > max_age_ms || frame_time < current.stream_started_at) continue;
        if (power_stream != current.stream_started_at) {
            power.reset();
            power_stream = current.stream_started_at;
        }
        if (completed_at - frame_time < kSearchLightFreshnessMs) {
            stats.rgb_faces += sample->search.detected_count != 0;
            stats.ir_only_faces += ir_only_face;
            power.observe(frame_time, has_face);
            infrared_light.observe(has_face, power.idle());
        } else power.reset();
        capture.setSearchState(power.idle(), infrared_light.on());
        if (callbacks.sample) callbacks.sample(*sample, power.idle());
    }
    if (diagnostics) stats.report(latest.progress(), power.idle());
}
}
