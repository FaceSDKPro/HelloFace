#pragma once
#include <array>
#include "form_field.h"
#include "sdk_helpers.h"

namespace hiface_linux_demo {
// Desktop and board defaults are explicit; a small desktop monitor is still a desktop.
// 桌面与板端显式选择，不能仅凭屏幕分辨率推断运行环境。
bool embeddedDisplay();
int initialCameraRotation();
struct CameraSize {
    int width, height;
    constexpr bool operator==(CameraSize other) const { return width == other.width && height == other.height; }
};
// Desktop uses 4:3 tiers. The embedded UI uses the board's 16:9 presets.
inline constexpr std::array<CameraSize, 3> desktop_camera_presets{{{640, 480}, {1280, 960}, {1440, 1080}}};
inline constexpr std::array<CameraSize, 3> embedded_camera_presets{{{640, 360}, {1280, 720}, {1920, 1080}}};
inline constexpr const auto& cameraPresets(bool embedded) {
    return embedded ? embedded_camera_presets : desktop_camera_presets;
}
struct DemoSettings {
    uint32_t detection_faces = 10;
    bool detailed = true, allow_multiple = true, verification_liveness = true;
    bool random_actions = true, verification_random_actions = true, verification_allow_multiple = true;
    float verification_threshold = HIFACE_DEFAULT_VERIFICATION_THRESHOLD;
    std::vector<HiFaceFlowActionV1> actions;
    std::vector<HiFaceFlowActionV1> verification_actions;
    bool search_multi = false, search_liveness = true;
    uint32_t search_faces = 3, search_interval = 0, search_timeout = 3000;
    float search_threshold = .8f;
    std::string group, tag;
    int camera_width = desktop_camera_presets.front().width;
    int camera_height = cameraPresets(embeddedDisplay()).front().height, camera_fps = 25;
    int ui_rotation = 0, camera_rotation = initialCameraRotation();
    bool camera_mjpeg = false, mirror = false;
    bool camera_resolution_overridden = false;
    int camera_zoom_percent = 100;
    std::string camera_default_device;
    CameraSize cameraSize() const { return {camera_width, camera_height}; }
    bool hasCameraResolutionOverride() const {
        // Keep custom dimensions and distinguish selected Low from an unset desktop preference.
        return camera_resolution_overridden || !(cameraSize() == desktop_camera_presets.front());
    }
    CameraSize cameraSizeForCapture(bool desktop_search) const {
        // Apply the search default only to the capture request, leaving the stored settings intact.
        if (desktop_search && !hasCameraResolutionOverride()) return desktop_camera_presets[2];
        return cameraSize();
    }
};
int initialUiRotation();
bool useSoftwareMouseCursor(const std::string& mode, bool embedded_display);
std::vector<FormField> settingsFields(const DemoSettings& settings);
DemoSettings parseSettings(const std::vector<FormField>& fields);
DemoSettings loadSettings(const std::string& file);
void saveSettings(const std::string& file, const DemoSettings& settings);
const char* actionName(HiFaceFlowActionV1 action);
}
