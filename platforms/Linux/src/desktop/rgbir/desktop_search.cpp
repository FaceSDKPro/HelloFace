#include "desktop_search.h"
#include "camera_recovery.h"
#include "live_search.h"
#include "frame_pool.h"
#include "lighting.h"
#include "search_power.h"
#include <chrono>
#include <cstdio>

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
    CameraFramePool rgb_pool;
    auto update = [&](auto change) {
        std::lock_guard<std::mutex> lock(mutex);
        if (stop_.load(std::memory_order_relaxed)) return;
        change();
        publish(std::make_shared<const RgbIrView>(state));
    };
    const auto fail = [&](const std::string& message) {
        std::fprintf(stderr, "[RGB/IR] search stopped: %s\n", message.c_str());
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
        CameraRecovery recovery;
        SearchCallbacks callbacks;
        callbacks.interruption_grace_ms = pair_gap_ms;
        if (diagnostics)
            callbacks.opened = [](const std::string& rgb, const std::string& ir) {
                std::fprintf(stderr, "[RGB/IR] streams open: RGB=%s; IR=%s\n", rgb.c_str(), ir.c_str());
            };
        if (infrared_light.configured())
            callbacks.lighting = [&](bool active) {
                require(infrared_light.setActive(active), "Infrared light GPIO write failed; search stopped");
            };
        callbacks.preview = [&](const RawCameraFrame& rgb, const RawCameraFrame&) {
            // Drop a preview if the renderer still holds all display buffers.
            auto color = rgb_pool.acquire();
            if (!color) return;
            try {
                Camera::decodePreview(rgb, *color);
            } catch (const DemoError&) {
                return; // Inference handles decode failures separately.
            }
            update([&] {
                if (!state.rgb) state.guidance = "Searching...";
                state.rgb = std::move(color);
            });
        };
        callbacks.sample = [&](const Sample& sample, bool idle) {
            recovery.retry(nowMs(), true);
            backlight.update(true, idle);
            status_light.setColor(searchStatusColor(sample));
            auto scores = searchScores(sample);
            update([&] {
                state.idle = idle;
                state.guidance = searchGuidance(sample);
                state.scores = std::move(scores);
                state.frame_image = sample.frame_image;
            });
        };
        const auto clear_preview = [&](const std::string& guidance) {
            backlight.restore();
            status_light.setColor(SearchLightColor::blue);
            update([&] {
                state.idle = false;
                state.guidance = guidance;
                state.scores = {};
                state.frame_image.reset();
                state.rgb.reset();
            });
        };
        callbacks.interrupted = [&] { clear_preview("Waiting for RGB/IR frames"); };
        while (!stop_.load(std::memory_order_relaxed)) {
            try {
                runSearch(database, settings, CameraRotation::settings, stop_, diagnostics, callbacks);
                break;
            } catch (const CameraStreamError& error) {
                if (stop_.load(std::memory_order_relaxed)) break;
                // Both streams and the old SDK search session have closed before retrying.
                std::fprintf(stderr, "[RGB/IR] camera recovery: %s\n", error.message.c_str());
                clear_preview("Reconnecting both cameras...");
                while (!stop_.load(std::memory_order_relaxed) && !recovery.retry(nowMs(), false))
                    std::this_thread::sleep_for(std::chrono::milliseconds(100));
                if (!stop_.load(std::memory_order_relaxed))
                    std::fprintf(stderr, "[RGB/IR] reopening cameras, attempt=%u\n", recovery.attempt());
            }
        }
    } catch (const DemoError& error) {
        fail(error.message);
    } catch (const std::exception& error) {
        fail(error.what());
    }
}
}
