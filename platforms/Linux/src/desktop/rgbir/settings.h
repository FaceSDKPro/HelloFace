#pragma once
#include "form_field.h"
#include "sdk_helpers.h"

namespace hiface_linux_demo {
struct RgbIrSettings {
    std::string rgb_device, ir_device, group;
    int rgb_rotation = 0, ir_rotation = 0;
    float ir_threshold = .5f, similarity = .8f;
    uint32_t interval_ms = 0, timeout_ms = 3000;

    bool hasDevices() const { return !rgb_device.empty() && !ir_device.empty(); }
};
struct RgbIrSettingError : DemoError {
    std::string key;
    RgbIrSettingError(const std::string& field, const std::string& message) : DemoError(message), key(field) {}
};
std::vector<FormField> rgbIrSettingsFields(const RgbIrSettings& settings);
RgbIrSettings parseRgbIrSettings(const std::vector<FormField>& fields);
RgbIrSettings loadRgbIrSettings(const std::string& database);
void saveRgbIrSettings(const std::string& database, const RgbIrSettings& settings);
void verifyRgbIrDevices(const RgbIrSettings& settings);
}
