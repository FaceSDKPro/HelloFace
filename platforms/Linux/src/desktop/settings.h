#pragma once
#include "form_field.h"
#include "sdk_helpers.h"

namespace hiface_linux_demo {
// Desktop and board defaults are explicit; a small desktop monitor is still a desktop.
// 桌面与板端显式选择，不能仅凭屏幕分辨率推断运行环境。
bool embeddedDisplay();
int initialCameraRotation();
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
    int camera_width = 640, camera_height = embeddedDisplay() ? 360 : 480, camera_fps = 25;
    int ui_rotation = 0, camera_rotation = initialCameraRotation();
    bool camera_mjpeg = false, mirror = false;
};
int initialUiRotation();
bool useSoftwareMouseCursor(const std::string& mode, bool embedded_display);
std::vector<FormField> settingsFields(const DemoSettings& settings);
DemoSettings parseSettings(const std::vector<FormField>& fields);
DemoSettings loadSettings(const std::string& file);
void saveSettings(const std::string& file, const DemoSettings& settings);
const char* actionName(HiFaceFlowActionV1 action);
}
