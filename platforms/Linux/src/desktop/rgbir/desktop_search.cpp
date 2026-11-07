#include "desktop_search.h"
#include "live_search.h"
#include "frame_pool.h"
#include "lighting.h"
#include "search_power.h"

namespace hiface_linux_demo::rgbir {

DesktopSearch::DesktopSearch(std::string database, RgbIrSettings settings, Publish publish, bool diagnostics)
    : worker_(&DesktopSearch::run, this, std::move(database), std::move(settings), std::move(publish), diagnostics) {}

DesktopSearch::~DesktopSearch() {
    stop_.store(true, std::memory_order_relaxed);
    worker_.join();
}

void DesktopSearch::run(const std::string& database, const RgbIrSettings& settings,
                        const Publish& publish, bool diagnostics) {
    // Preview and inference have different writers. Publish both through one
    // snapshot so neither overwrites the other's latest state.
    std::mutex mutex;
    RgbIrView state;
    CameraFramePool rgb_pool, ir_pool;
    auto update = [&](auto change) {
        std::lock_guard<std::mutex> lock(mutex);
        if (stop_.load(std::memory_order_relaxed)) return;
        change();
        publish(std::make_shared<const RgbIrView>(state));
    };
    const auto fail = [&](const std::string& message) {
        update([&] {
            state = {};
            state.running = false;
            state.guidance = message;
        });
    };

    try {
        SearchBacklight backlight; // Search thread owns backlight until stop or failure.
        InfraredLighting infrared_light(settings.ir_device);
        SearchStatusLighting status_light;
        status_light.setColor(SearchLightColor::blue);
        update([] {});
        SearchCallbacks callbacks;
        callbacks.interruption_grace_ms = pair_gap_ms;
        if (infrared_light.configured())
            callbacks.lighting = [&](bool active) { infrared_light.setActive(active); };
        callbacks.preview = [&](const RawCameraFrame& rgb, const RawCameraFrame& ir) {
            // Skip the entire display pair if the renderer still holds a buffer.
            auto color = rgb_pool.acquire(), infrared = ir_pool.acquire();
            if (!color || !infrared) return;
            try {
                Camera::decodePreview(rgb, *color);
                Camera::decodePreview(ir, *infrared);
            } catch (const DemoError&) {
                return; // Inference handles decode failures separately.
            }
            update([&] {
                if (!state.rgb) state.guidance = "Searching...";
                state.rgb = std::move(color);
                state.ir = std::move(infrared);
            });
        };
        callbacks.sample = [&](const Sample& sample, bool idle) {
            backlight.update(true, idle);
            status_light.setColor(searchStatusColor(sample));
            auto scores = searchScores(sample);
            update([&] {
                state.idle = idle;
                state.guidance = searchGuidance(sample);
                state.scores = std::move(scores);
            });
        };
        callbacks.interrupted = [&] {
            backlight.restore();
            status_light.setColor(SearchLightColor::blue);
            update([&] {
                state.idle = false;
                state.guidance = "Waiting for RGB/IR frames";
                state.scores = {};
                state.rgb.reset();
                state.ir.reset();
            });
        };
        runSearch(database, settings, CameraRotation::settings, stop_, diagnostics, callbacks);
    } catch (const DemoError& error) {
        fail(error.message);
    } catch (const std::exception& error) {
        fail(error.what());
    }
}
}
