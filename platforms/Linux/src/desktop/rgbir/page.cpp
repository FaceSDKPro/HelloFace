#include "page.h"
#include "ui.h"
#include <algorithm>

namespace hiface_linux_demo {
namespace {
constexpr uint32_t background = 0x0e1522, panel_color = 0x172233;
constexpr uint32_t muted = 0xaebfd3;
}

void DemoUi::uvcCameraFaceSearch(const ViewState& state, Rect bounds) {
    scene_.box(bounds, background);
    const int result_height = search_result_height + search_control_gap + search_button_height + search_bottom_padding;
    const Rect preview{bounds.x, bounds.y, bounds.w,
        std::max(0, bounds.h - result_height)};
    const Rect panel{bounds.x, preview.y + preview.h, bounds.w, search_result_height};
    const auto* live = state.rgbir.get();
    const bool configured = state.rgbir_settings.hasDevices();
    const bool running = live && live->running;

    if (preview.w > 0 && preview.h > 0) {
        const auto has_frame = [](const CameraFrame* frame) {
            return frame && frame->width > 0 && frame->height > 0 && !frame->rgba.empty();
        };
        if (live && has_frame(live->rgb.get())) {
            const auto& color = *live->rgb;
            const auto previous_clip = scene_.clip;
            scene_.clip = previous_clip.intersect(preview);
            scene_.image(fitImage(preview, color.width, color.height, true), color.rgba.data(),
                color.width, color.height, false, color.x11_bgrx);
            if (has_frame(live->ir.get()) && preview.w >= 2 && preview.h >= 3) {
                const auto& infrared = *live->ir;
                const int ir_h = preview.h / 3;
                const int ir_w = std::clamp(ir_h * infrared.width / infrared.height, 1, preview.w / 2);
                const Rect ir{preview.x + preview.w - ir_w, preview.y + preview.h - ir_h, ir_w, ir_h};
                scene_.clip = scene_.clip.intersect(ir);
                scene_.image(fitImage(ir, infrared.width, infrared.height, true), infrared.rgba.data(),
                    infrared.width, infrared.height, false, infrared.x11_bgrx);
            }
            scene_.clip = previous_clip;
        } else {
            text(preview.x + 8, preview.y + preview.h / 2 + 5, "No preview", muted, preview.w - 16, Font::Small, true);
        }
    }

    const int nav_y = bounds.y + 12;
    button({bounds.x + 16, nav_y, 86, 36}, "< Back", "back", 4, state.ready && !state.busy);
    button({bounds.x + bounds.w - 112, nav_y, 96, 36}, "Settings", "uvc-settings", 4, content_enabled_);

    const bool scored = state.rgbir_available && running && live->scores.available() && state.rgbir_settings_error.empty();
    constexpr auto mode = "1:N | Liveness on";
    if (scored) {
        const auto& settings = state.rgbir_settings;
        drawSearchScores(panel, mode, live->scores, settings.similarity, settings.ir_threshold);
    } else {
        const bool failed = !state.rgbir_settings_error.empty() || (live && !running);
        const std::string summary = !state.rgbir_available ? "Dual-camera search unavailable"
            : !state.rgbir_settings_error.empty() ? state.rgbir_settings_error
            : live ? live->guidance : configured ? "Start search" : "Select both cameras in Settings";
        drawSearchResults(panel, mode, summary, failed);
    }

    constexpr int inset = 12, gap = 6;
    const int action_y = panel.y + panel.h + search_control_gap;
    const int action_w = (bounds.w - inset * 2 - gap) / 2;
    scene_.box({bounds.x, panel.y + panel.h, bounds.w,
        search_control_gap + search_button_height + search_bottom_padding}, panel_color);
    button({bounds.x + inset, action_y, action_w, search_button_height}, running ? "Stop search" : "Start search", "uvc-toggle", 1,
        content_enabled_ && state.rgbir_available && configured);
    button({bounds.x + inset + action_w + gap, action_y, bounds.w - inset * 2 - action_w - gap, search_button_height},
        "Face library", "page:gallery", 0, content_enabled_);
}
}
