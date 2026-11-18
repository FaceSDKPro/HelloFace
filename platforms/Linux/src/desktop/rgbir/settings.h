#pragma once
#include "form_field.h"
#include "sdk_helpers.h"

namespace hiface_linux_demo {
inline constexpr double rgbir_min_ir_threshold = 0.80, rgbir_max_ir_threshold = 0.99;
inline constexpr float rgbir_default_ir_threshold = 0.90f;
inline constexpr char rgbir_ir_threshold_error[] = "IR liveness threshold must be between 0.80 and 0.99.";

struct RgbIrSettings {
    std::string rgb_device, ir_device, group;
    int rgb_rotation = 0, ir_rotation = 0;
    float ir_threshold = rgbir_default_ir_threshold, similarity = .8f;
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
