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
namespace {
bool valid(const CameraPreferences& p) {
    return ((p.width == 640 && p.height == 480) || (p.width == 1280 && p.height == 720)
        || (p.width == 1920 && p.height == 1080)) && p.rotation >= 0 && p.rotation <= 270 && p.rotation % 90 == 0;
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
    int mirror = 0;
    if (header != "HiFace-camera-v1" || !(input >> p.width >> p.height >> p.rotation >> mirror)
        || (mirror != 0 && mirror != 1) || !valid(p)) return {};
    input >> std::ws;
    if (!input.eof()) return {};
    p.mirror = mirror != 0; return p;
}
void saveCameraPreferences(const std::filesystem::path& file, const CameraPreferences& p) {
    if (!valid(p)) throw std::runtime_error("Invalid camera preferences");
    auto temporary = file; temporary += ".tmp-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
    struct Cleanup { std::filesystem::path path; ~Cleanup() { std::error_code ignored; std::filesystem::remove(path, ignored); } } cleanup{temporary};
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    output << "HiFace-camera-v1\n" << p.width << ' ' << p.height << ' ' << p.rotation << ' ' << p.mirror << '\n';
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
