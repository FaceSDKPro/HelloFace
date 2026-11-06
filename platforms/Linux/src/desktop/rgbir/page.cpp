#include "page.h"
#include "ui.h"
#include <algorithm>

namespace hiface_linux_demo {
namespace {
constexpr uint32_t background = 0x0e1522, preview_color = 0x090f19, panel_color = 0x172233;
constexpr uint32_t border = 0x2c3b50, title_color = 0xecf3fc, muted = 0xaebfd3, mint = 0x7fe4c3, red = 0xff9b9b;
}

void DemoUi::uvcCameraFaceSearch(const ViewState& state, Rect bounds) {
    scene_.box(bounds, background);
    const int margin = bounds.w < 560 ? 16 : 24;
    const int title_x = margin + 84;
    button({margin, 16, 72, 38}, "< Back", "back", 0, state.ready && !state.busy);
    button({bounds.w - margin - 96, 16, 96, 38}, "Settings", "uvc-settings", 0, content_enabled_);
    text(title_x, 34, RgbIrSearchPage::title, title_color, bounds.w - title_x - margin - 108,
        bounds.w < 560 ? Font::Large : Font::Title);
    text(title_x, 57, RgbIrSearchPage::description, muted, bounds.w - title_x - margin, Font::Small);

    constexpr int gap = 12, panel_h = 166, button_h = 44;
    const Rect body{margin, 78, bounds.w - margin * 2, bounds.h - 78 - margin};
    const bool wide = body.w >= 740 && bounds.w >= bounds.h;
    const int panel_w = wide ? std::clamp(body.w / 3, 282, 358) : body.w;
    const Rect preview{body.x, body.y, wide ? body.w - panel_w - gap : body.w,
        wide ? body.h : std::max(0, body.h - panel_h - button_h - gap * 2)};
    const Rect panel{wide ? preview.x + preview.w + gap : body.x,
        wide ? body.y : preview.y + preview.h + gap, panel_w, panel_h};
    const auto* live = state.rgbir.get();
    const bool configured = state.rgbir_settings.hasDevices();
    const bool running = live && live->running;

    const bool stacked = wide && preview.h > preview.w;
    const int split = ((stacked ? preview.h : preview.w) - gap) / 2;
    const Rect rgb{preview.x, preview.y, stacked ? preview.w : split, stacked ? split : preview.h};
    const Rect ir{stacked ? preview.x : rgb.x + rgb.w + gap, stacked ? rgb.y + rgb.h + gap : preview.y,
        stacked ? preview.w : preview.w - rgb.w - gap, stacked ? preview.h - rgb.h - gap : preview.h};
    const auto stream = [&](Rect tile, const char* label, const CameraFrame* frame) {
        if (tile.h < 44 || tile.w < 60) return;
        scene_.box(tile, border, 12);
        scene_.box({tile.x + 1, tile.y + 1, tile.w - 2, tile.h - 2}, preview_color, 11);
        if (frame) picture({tile.x + 2, tile.y + 34, tile.w - 4, tile.h - 36}, nullptr, frame, false, {});
        else text(tile.x + 8, tile.y + tile.h / 2 + 12, "No preview", muted, tile.w - 16, Font::Small, true);
        text(tile.x + 12, tile.y + 23, label, muted, tile.w - 24, Font::Small);
    };
    stream(rgb, "RGB PREVIEW", live ? live->rgb.get() : nullptr);
    stream(ir, "IR PREVIEW", live ? live->ir.get() : nullptr);

    scene_.box(panel, border, 14);
    scene_.box({panel.x + 1, panel.y + 1, panel.w - 2, panel.h - 2}, panel_color, 13);
    const int x = panel.x + 16, width = panel.w - 32;
    const auto liveness = live ? live->liveness : LivenessState::pending;
    const bool passed = liveness == LivenessState::passed, rejected = liveness == LivenessState::rejected;
    const char* status = passed ? "IR LIVENESS: PASSED" : rejected ? "IR LIVENESS: FAILED"
        : running ? "IR LIVENESS: WAITING" : "IR LIVENESS: INACTIVE";
    text(x, panel.y + 27, status, passed ? mint : rejected ? red : muted, width, Font::Small);
    std::string guidance = !state.rgbir_available ? "Dual-camera search is unavailable in this build."
        : !state.rgbir_settings_error.empty() ? state.rgbir_settings_error
        : live ? live->guidance : configured ? "Start search when ready." : RgbIrSearchPage::status;
    wrap(x, panel.y + 52, guidance, title_color, width, 3);
    scene_.box({x, panel.y + 102, width, 1}, border);
    text(x, panel.y + 124, "Latest confirmed match", muted, width, Font::Small);
    const auto match = live ? live->latest_match : "";
    text(x, panel.y + 148, match.empty() ? "No match yet" : match, match.empty() ? title_color : mint, width, Font::Small);

    const int action_y = panel.y + panel.h + gap, action_w = (panel.w - gap) / 2;
    button({panel.x, action_y, action_w, button_h}, running ? "Stop search" : "Start search", "uvc-toggle", 1,
        content_enabled_ && state.rgbir_available && configured);
    button({panel.x + action_w + gap, action_y, panel.w - action_w - gap, button_h},
        "Face library", "page:gallery", 0, content_enabled_);
}
}
