#include "page.h"
#include "ui.h"
#include <algorithm>

namespace hiface_linux_demo {
namespace {
constexpr uint32_t background = 0x0e1522, panel_color = 0x172233;
constexpr uint32_t border = 0x2c3b50, title_color = 0xecf3fc, muted = 0xaebfd3;
bool cameraSetting(const std::string& key) { return key.rfind("rgb_", 0) == 0 || key.rfind("ir_", 0) == 0; }
}

void DemoUi::uvcSettingsDialog(const ViewState& state) {
    controls_.clear();
    scene_.box({0, 0, scene_.width, scene_.height}, background);
    const int w = std::min(600, scene_.width - 32), h = std::min(504, scene_.height - 24);
    const int x = (scene_.width - w) / 2, y = (scene_.height - h) / 2;
    const int left = x + 18, content = w - 36, half = (content - 12) / 2;
    const bool editable = !state.busy && !uvc_settings_pending_ && !settings_pending_;
    scene_.box({x, y, w, h}, border, 14);
    scene_.box({x + 1, y + 1, w - 2, h - 2}, panel_color, 13);
    text(left, y + 33, "Dual-camera search settings", title_color, content, Font::Large);
    const int tab_width = (content - 16) / 3;
    button({left, y + 48, tab_width, 36}, "Cameras", "uvc-tab-camera",
           uvc_settings_tab_ == UvcSettingsTab::camera ? 2 : 0, editable);
    button({left + tab_width + 8, y + 48, tab_width, 36}, "Search", "uvc-tab-search",
           uvc_settings_tab_ == UvcSettingsTab::search ? 2 : 0, editable);
    button({left + 2 * (tab_width + 8), y + 48, content - 2 * (tab_width + 8), 36}, "Display", "uvc-tab-display",
           uvc_settings_tab_ == UvcSettingsTab::display ? 2 : 0, editable);
    const int bottom = y + h - 49;
    if (uvc_settings_tab_ == UvcSettingsTab::display) {
        text(left, y + 120, "UI rotation", title_color, content, Font::Large);
        wrap(left, y + 147, "Changes apply immediately to all Demo pages, including both previews.", muted, content, 2, Font::Small);
        rotationButtons({left, y + 181, content, 36}, std::to_string(state.settings.ui_rotation), editable);
        wrap(left, y + 247, "To rotate one camera image, use its rotation control in Cameras.", muted, content, 2, Font::Small);
        if (!notice_.empty()) wrap(left, y + h - 89, notice_, 0xffb7ae, content, 2, Font::Small);
        button({x + w - 128, bottom, 110, 35}, settings_pending_ ? "Saving..." : "Close", "uvc-settings-cancel", 0, editable);
        return;
    }

    static const auto labels = [] {
        std::map<std::string, std::string> result;
        for (const auto& f : rgbIrSettingsFields({})) result.emplace(f.key, f.label);
        return result;
    }();
    const auto drawField = [&](const std::string& key, int field_x, int field_y, int width) {
        field({field_x, field_y, width, 58}, "uvc:" + key, labels.at(key), "", editable);
    };
    if (uvc_settings_tab_ == UvcSettingsTab::camera) {
        wrap(left, y + 111, "Choose separate RGB and IR devices. Use v4l2-ctl --list-devices to find capture paths.",
             muted, content, 2, Font::Small);
        drawField("rgb_device", left, y + 143, content);
        drawField("ir_device", left, y + 201, content);
        const auto rotations = [&](int field_x, const std::string& key) {
            text(field_x, y + 274, labels.at(key), muted, half, Font::Small);
            const int step = half / 4;
            for (int angle : {0, 90, 180, 270}) {
                const auto value = std::to_string(angle);
                button({field_x + angle / 90 * step, y + 284, step - 5, 33}, value + "°",
                    "uvc-rotation:" + key + ":" + value, values_["uvc:" + key] == value ? 2 : 0, editable, Font::Small);
            }
        };
        rotations(left, "rgb_rotation");
        rotations(left + half + 12, "ir_rotation");
        drawField("ir_threshold", left, y + 331, half);
        wrap(left + half + 12, y + 358, "Development value. Calibrate on the target module.",
             muted, content - half - 12, 2, Font::Small);
    } else {
        wrap(left, y + 111, "Single-person 1:N. Identity and IR liveness must pass in the same sample.",
             muted, content, 2, Font::Small);
        drawField("group", left, y + 143, content);
        drawField("similarity", left, y + 210, half);
        drawField("interval_ms", left + half + 12, y + 210, content - half - 12);
        drawField("timeout_ms", left, y + 277, half);
    }
    if (!notice_.empty()) wrap(left, y + h - 89, notice_, 0xffb7ae, content, 2, Font::Small);
    button({left, bottom, 90, 35}, "Cancel", "uvc-settings-cancel", 0, editable);
    button({left + 101, bottom, 90, 35}, "Reset", "uvc-settings-reset", 0, editable);
    button({x + w - 128, bottom, 110, 35}, editable ? "Apply" : "Saving...", "uvc-settings-apply", 1, editable);
}

void DemoUi::handleUvcSettings(const std::string& action, const ViewState& state) {
    if (uvc_settings_pending_ || settings_pending_) return;
    if (action == "uvc-settings" && page_ == RgbIrSearchPage::route && !state.busy) {
        beginOverlay();
        uvc_settings_open_ = true;
        uvc_settings_tab_ = UvcSettingsTab::camera;
        for (const auto& f : rgbIrSettingsFields(state.rgbir_settings)) values_["uvc:" + f.key] = f.value;
        notice_ = state.rgbir_settings_error;
        keyboard_focus_ = "uvc-tab-camera";
        return;
    }
    if (!uvc_settings_open_) return;
    if (action == "uvc-settings-cancel") { dismissOverlay(); return; }
    if (action == "uvc-tab-camera" || action == "uvc-tab-search" || action == "uvc-tab-display") {
        uvc_settings_tab_ = action == "uvc-tab-camera" ? UvcSettingsTab::camera
            : action == "uvc-tab-search" ? UvcSettingsTab::search : UvcSettingsTab::display;
        focused_.clear(); invalid_field_.clear(); notice_.clear();
        return;
    }
    if (uvc_settings_tab_ == UvcSettingsTab::display) return;
    if (action == "uvc-settings-reset") {
        RgbIrSettings defaults;
        // Reset tuning values without losing the saved roles of the two cameras.
        defaults.rgb_device = state.rgbir_settings.rgb_device;
        defaults.ir_device = state.rgbir_settings.ir_device;
        for (const auto& f : rgbIrSettingsFields(defaults))
            if (cameraSetting(f.key) == (uvc_settings_tab_ == UvcSettingsTab::camera)) values_["uvc:" + f.key] = f.value;
        focused_.clear(); invalid_field_.clear(); notice_.clear();
        return;
    }
    if (action.rfind("uvc-rotation:", 0) == 0) {
        const auto key_value = action.substr(13);
        const auto separator = key_value.find(':');
        if (separator != std::string::npos)
            values_["uvc:" + key_value.substr(0, separator)] = key_value.substr(separator + 1);
        return;
    }
    if (action != "uvc-settings-apply" || state.busy) return;
    auto fields = rgbIrSettingsFields(state.rgbir_settings);
    for (auto& f : fields) f.value = values_["uvc:" + f.key];
    try { parseRgbIrSettings(fields); }
    catch (const RgbIrSettingError& error) {
        uvc_settings_tab_ = cameraSetting(error.key) ? UvcSettingsTab::camera : UvcSettingsTab::search;
        notice_ = error.message;
        invalid_field_ = focused_ = "uvc:" + error.key;
        keyboard_focus_ = "field:" + focused_;
        cursor_ = values_[focused_].size();
        return;
    } catch (const DemoError& error) { notice_ = error.message; return; }
    commands_.push_back({"uvc-save-settings", {}, std::move(fields)});
    uvc_settings_pending_ = true;
    uvc_settings_attempt_ = state.rgbir_settings_attempt;
    focused_.clear(); invalid_field_.clear(); notice_.clear();
}
}
