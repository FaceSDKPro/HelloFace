#pragma once
#include <array>
#include <filesystem>
#include <string>
namespace hiface_demo {
struct CameraSize { unsigned width, height; };
inline constexpr std::array<CameraSize, 3> camera_presets{{{640, 480}, {1280, 960}, {1440, 1080}}};
int cameraPresetIndex(unsigned width, unsigned height);

// An empty selection uses High for live search and Low for other camera features.
inline CameraSize cameraSizeForSelection(int preset, bool searching) {
    if (preset >= 0 && preset < static_cast<int>(camera_presets.size())) return camera_presets[preset];
    return camera_presets[searching ? 2 : 0];
}

struct CameraPreferences {
    unsigned width = camera_presets.front().width, height = camera_presets.front().height;
    int rotation = 0;
    bool mirror = false;
    // Width and height can contain the last feature default. Only a user selection applies across pages.
    bool resolution_overridden = false;
    int zoom_percent = 100;
    std::string default_camera_link = {};
};
CameraPreferences loadCameraPreferences(const std::filesystem::path& file);
void saveCameraPreferences(const std::filesystem::path& file, const CameraPreferences& value);
}
