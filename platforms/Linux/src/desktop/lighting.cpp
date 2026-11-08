#include "lighting.h"

namespace hiface_linux_demo {
const char* lightingBackend() noexcept { return "external"; }
const char* lightingCapabilities() noexcept { return R"({"lightingBackend":"external","lightingContract":"HIFACE-LIGHTING1:external"})"; }
// The desktop backend leaves camera illumination to the attached hardware.
struct CameraLighting::Board {};
CameraLighting::CameraLighting() = default;
CameraLighting::~CameraLighting() = default;
void CameraLighting::bindCamera(const std::string&) {}
bool CameraLighting::setActive(bool) noexcept { return true; }

struct InfraredLighting::Board {};
InfraredLighting::InfraredLighting(const std::string&) {}
InfraredLighting::~InfraredLighting() = default;
bool InfraredLighting::setActive(bool) noexcept { return false; }

struct SearchStatusLighting::Board {};
SearchStatusLighting::SearchStatusLighting() = default;
SearchStatusLighting::~SearchStatusLighting() = default;
void SearchStatusLighting::setColor(SearchLightColor) noexcept {}
}
