#include "lighting.h"

namespace hiface_linux_demo {
// The desktop backend leaves camera illumination to the attached hardware.
struct CameraLighting::Board {};
CameraLighting::CameraLighting() = default;
CameraLighting::~CameraLighting() = default;
void CameraLighting::bindCamera(const std::string&) {}
bool CameraLighting::setActive(bool) noexcept { return true; }

struct InfraredLighting::Board {};
InfraredLighting::InfraredLighting(const std::string&) {}
InfraredLighting::~InfraredLighting() = default;
void InfraredLighting::setActive(bool) noexcept {}

struct SearchStatusLighting::Board {};
SearchStatusLighting::SearchStatusLighting() = default;
SearchStatusLighting::~SearchStatusLighting() = default;
void SearchStatusLighting::setColor(SearchLightColor) noexcept {}
}
