#pragma once
#include "capture_pipeline.h"
#include "search_session.h"

namespace hiface_linux_demo::rgbir {
enum class CameraRotation { settings, environment };

struct SearchCallbacks {
    // Preview runs on the capture thread. Other callbacks run on the thread
    // that calls runSearch. The callback arguments are borrowed.
    std::function<void(const std::string&, const std::string&)> opened;
    Capture::Preview preview;
    // Applied on the capture thread, which switches it off when capture exits.
    Capture::Lighting lighting;
    // With lighting configured, idle describes sustained face absence in both cameras.
    std::function<void(const Sample&, bool idle)> sample;
    std::function<void()> interrupted;
    // A display can wait longer before clearing the view without changing frame admission.
    int64_t interruption_grace_ms = max_age_ms;
};

void runSearch(const std::string& database, const RgbIrSettings& settings, CameraRotation rotation,
               const std::atomic<bool>& stopping, bool diagnostics, const SearchCallbacks& callbacks);
}
