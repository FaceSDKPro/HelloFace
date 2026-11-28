#include "camera_preferences.h"
#include <fstream>
#include <string>
#include <chrono>
#include <stdexcept>
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif
namespace hiface_demo {
int cameraPresetIndex(unsigned width, unsigned height) {
    for (std::size_t index = 0; index < camera_presets.size(); ++index) {
        const auto size = camera_presets[index];
        if (width == size.width && height == size.height) return static_cast<int>(index);
    }
    return -1;
}
namespace {
bool valid(const CameraPreferences& p) {
    return cameraPresetIndex(p.width, p.height) >= 0 && p.rotation >= 0 && p.rotation <= 270 && p.rotation % 90 == 0;
}
}
CameraPreferences loadCameraPreferences(const std::filesystem::path& file) {
    std::ifstream input(file, std::ios::binary | std::ios::ate);
    if (!input) return {};
    const auto size = input.tellg();
    if (size < 0 || size > 128) return {};
    input.seekg(0);
    std::string header;
    if (!std::getline(input, header)) return {};
    // Accept settings saved by editors that use Windows line endings.
    if (!header.empty() && header.back() == '\r') header.pop_back();
    CameraPreferences p;
    int mirror = 0, overridden = 0;
    if (!(input >> p.width >> p.height >> p.rotation >> mirror) || (mirror != 0 && mirror != 1)) return {};
    if (header == "HiFace-camera-v1") {
        // Old 16:9 sizes follow their corresponding 4:3 tiers. Legacy VGA uses the feature default.
        int preset = 0;
        if (p.width == 1280 && p.height == 720) preset = 1;
        else if (p.width == 1920 && p.height == 1080) preset = 2;
        else if (cameraPresetIndex(p.width, p.height) != 0) return {};
        const auto size = camera_presets[preset];
        p.width = size.width;
        p.height = size.height;
        overridden = preset != 0;
    } else if (header == "HiFace-camera-v2") {
        if (!(input >> overridden) || (overridden != 0 && overridden != 1)) return {};
    } else return {};
    if (!valid(p)) return {};
    input >> std::ws;
    if (!input.eof()) return {};
    p.mirror = mirror != 0;
    p.resolution_overridden = overridden != 0;
    return p;
}
void saveCameraPreferences(const std::filesystem::path& file, const CameraPreferences& p) {
    if (!valid(p)) throw std::runtime_error("Invalid camera preferences");
    auto temporary = file; temporary += ".tmp-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
    struct Cleanup { std::filesystem::path path; ~Cleanup() { std::error_code ignored; std::filesystem::remove(path, ignored); } } cleanup{temporary};
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    output << "HiFace-camera-v2\n" << p.width << ' ' << p.height << ' ' << p.rotation << ' ' << p.mirror
        << ' ' << p.resolution_overridden << '\n';
    output.close();
    if (!output) throw std::runtime_error("Cannot save camera preferences");
#ifdef _WIN32
    if (!MoveFileExW(temporary.c_str(), file.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        throw std::runtime_error("Cannot replace camera preferences");
#else
    std::filesystem::rename(temporary, file);
#endif
}
}
