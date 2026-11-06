#include "settings.h"
#include "file_io.h"
#include <algorithm>
#include <cerrno>
#include <charconv>
#include <cmath>
#include <filesystem>
#include <iomanip>
#include <map>
#include <optional>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>

namespace hiface_linux_demo {
namespace {
std::optional<dev_t> deviceNumber(const std::string& path) {
    struct stat device{};
    if (stat(path.c_str(), &device) == 0 && S_ISCHR(device.st_mode)) return device.st_rdev;
    return std::nullopt;
}
}

std::vector<FormField> rgbIrSettingsFields(const RgbIrSettings& s) {
    const auto decimal = [](float value) {
        char text[48];
        const auto result = std::to_chars(text, text + sizeof(text), value);
        require(result.ec == std::errc{}, "Cannot format dual-camera threshold.");
        return std::string(text, result.ptr);
    };
    return {
        {"rgb_device", "RGB camera device", s.rgb_device},
        {"ir_device", "IR camera device", s.ir_device},
        {"rgb_rotation", "RGB rotation (clockwise)", std::to_string(s.rgb_rotation)},
        {"ir_rotation", "IR rotation (clockwise)", std::to_string(s.ir_rotation)},
        {"ir_threshold", "IR liveness threshold (0, 1]", decimal(s.ir_threshold)},
        {"group", "Search group (empty = all)", s.group},
        {"similarity", "Identity similarity (0.75–0.85)", decimal(s.similarity)},
        {"interval_ms", "Success interval (0–3000 ms)", std::to_string(s.interval_ms)},
        {"timeout_ms", "Round timeout (1000–3000 ms)", std::to_string(s.timeout_ms)}
    };
}

RgbIrSettings parseRgbIrSettings(const std::vector<FormField>& fields) {
    std::map<std::string, std::string> values;
    for (const auto& field : fields) {
        if (field.value.find_first_of("\r\n") != std::string::npos || field.value.find('\0') != std::string::npos ||
            field.value.size() > HIFACE_SEARCH_MAX_TEXT_BYTES)
            throw RgbIrSettingError{field.key, field.label + " contains invalid or oversized text."};
        const auto begin = field.value.find_first_not_of(" \t"), end = field.value.find_last_not_of(" \t");
        require(values.emplace(field.key, begin == std::string::npos ? "" : field.value.substr(begin, end - begin + 1)).second,
            "Duplicate RGB/IR setting: " + field.key);
    }
    const auto schema = rgbIrSettingsFields({});
    require(values.size() == schema.size(), "Missing or unknown RGB/IR settings");
    for (const auto& field : schema) require(values.count(field.key), "Missing RGB/IR setting: " + field.key);
    const auto number = [&](const char* key, double minimum, double maximum, bool integer, const char* message) {
        std::istringstream input(values.at(key));
        input.imbue(std::locale::classic());
        double result = 0;
        if (!(input >> result) || !input.eof() || !std::isfinite(result) || result < minimum || result > maximum ||
            (integer && std::floor(result) != result)) throw RgbIrSettingError{key, message};
        return result;
    };
    const auto rotation = [&](const char* key) {
        constexpr auto message = "Select a rotation of 0, 90, 180 or 270 degrees.";
        const int degrees = static_cast<int>(number(key, 0, 270, true, message));
        if (degrees % 90 != 0) throw RgbIrSettingError{key, message};
        return degrees;
    };
    const auto device = [&](const char* key) {
        const auto& value = values.at(key);
        if (value.empty()) return value;
        auto path = std::filesystem::path(value).lexically_normal().string();
        if (path.rfind("/dev/", 0) != 0 || path.size() <= 5 || path.back() == '/')
            throw RgbIrSettingError{key, "Enter an absolute video device path under /dev."};
        return path;
    };
    RgbIrSettings s;
    s.rgb_device = device("rgb_device");
    s.ir_device = device("ir_device");
    if (s.hasDevices()) {
        const auto rgb = deviceNumber(s.rgb_device), ir = deviceNumber(s.ir_device);
        if (s.rgb_device == s.ir_device || (rgb && rgb == ir))
            throw RgbIrSettingError{"ir_device", "Choose a different capture device for each role."};
    }
    s.rgb_rotation = rotation("rgb_rotation");
    s.ir_rotation = rotation("ir_rotation");
    constexpr auto ir_threshold_error = "IR liveness threshold must be greater than 0 and at most 1.";
    s.ir_threshold = static_cast<float>(number("ir_threshold", 0, 1, false, ir_threshold_error));
    if (s.ir_threshold <= 0) throw RgbIrSettingError{"ir_threshold", ir_threshold_error};
    s.group = values.at("group");
    s.similarity = number("similarity", .75, .85, false, "Identity similarity must be between 0.75 and 0.85.");
    s.interval_ms = number("interval_ms", 0, 3000, true, "Success interval must be a whole number from 0 to 3000 ms.");
    s.timeout_ms = number("timeout_ms", 1000, 3000, true, "Round timeout must be a whole number from 1000 to 3000 ms.");
    return s;
}

void verifyRgbIrDevices(const RgbIrSettings& settings) {
    require(settings.hasDevices(), "Select both camera devices in Settings.");
    const auto rgb = deviceNumber(settings.rgb_device), ir = deviceNumber(settings.ir_device);
    if (!rgb) throw DemoError{"RGB camera: expected a video device at " + settings.rgb_device};
    if (!ir) throw DemoError{"IR camera: expected a video device at " + settings.ir_device};
    require(rgb != ir, "RGB and IR must use different video devices");
    const auto verifyAccess = [](const char* role, const std::string& path) {
        if (access(path.c_str(), R_OK | W_OK) == 0) return;
        const std::error_code error(errno, std::generic_category());
        throw DemoError{std::string(role) + " camera: " + error.message() + " for " + path};
    };
    verifyAccess("RGB", settings.rgb_device);
    verifyAccess("IR", settings.ir_device);
}

namespace {
std::filesystem::path rgbIrSettingsPath(const std::string& database) {
    // Both entry points share this file beside the gallery, separate from RGB-only settings.
    return std::filesystem::path(database).parent_path() / "rgbir.conf";
}
}

RgbIrSettings loadRgbIrSettings(const std::string& database) {
    const auto path = rgbIrSettingsPath(database);
    if (!std::filesystem::exists(path)) return {};
    std::ifstream input(path);
    require(bool(input), "Cannot read dual-camera settings.");
    auto fields = rgbIrSettingsFields({});
    std::map<std::string, bool> seen;
    for (std::string line; std::getline(input, line);) {
        if (line.empty()) continue;
        std::istringstream row(line);
        std::string key, value;
        require(bool(row >> key >> std::quoted(value)), "Invalid dual-camera settings file.");
        row >> std::ws;
        require(row.eof() && seen.emplace(key, true).second, "Invalid or duplicate dual-camera setting.");
        auto field = std::find_if(fields.begin(), fields.end(), [&](const FormField& f) { return f.key == key; });
        require(field != fields.end(), "Unknown dual-camera setting: " + key);
        field->value = value;
    }
    require(input.eof(), "Cannot read dual-camera settings.");
    return parseRgbIrSettings(fields);
}

void saveRgbIrSettings(const std::string& database, const RgbIrSettings& settings) {
    std::ostringstream output;
    const auto valid = parseRgbIrSettings(rgbIrSettingsFields(settings));
    for (const auto& field : rgbIrSettingsFields(valid)) output << field.key << ' ' << std::quoted(field.value) << '\n';
    atomicWrite(rgbIrSettingsPath(database).string(), output.str());
}
}
