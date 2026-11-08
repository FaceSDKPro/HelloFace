#include "lighting.h"
#include <array>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <stdexcept>
#include <unistd.h>

namespace hiface_linux_demo {
const char* lightingBackend() noexcept { return "t92p"; }
const char* lightingCapabilities() noexcept { return R"({"lightingBackend":"t92p","lightingContract":"HIFACE-LIGHTING1:t92p"})"; }
namespace {
bool writeValue(const std::string& file, int value) noexcept {
    int fd;
    do { fd = open(file.c_str(), O_WRONLY | O_CLOEXEC); } while (fd < 0 && errno == EINTR);
    if (fd < 0) return false;
    char text[16];
    const auto length = std::snprintf(text, sizeof(text), "%d", value);
    ssize_t written;
    do { written = write(fd, text, length); } while (written < 0 && errno == EINTR);
    const int saved = written < 0 ? errno : EIO;
    close(fd); errno = saved;
    return written == length;
}

// Successful transitions are cached. Failed writes retry at a bounded rate,
// and an off request can interrupt a failed attempt to turn on.
class LampState {
public:
    bool isApplied(int value) const { return applied_ == value; }
    bool shouldWrite(int value, bool shutdown) const {
        return !isApplied(value) &&
            (shutdown || failed_ != value || Clock::now() >= retry_after_);
    }
    void applied(int value) {
        applied_ = value;
        failed_ = -1;
    }
    bool failed(int value, bool confirmed_off) {
        const bool first = failed_ != value;
        applied_ = confirmed_off ? 0 : -1;
        failed_ = value;
        retry_after_ = Clock::now() + std::chrono::milliseconds(250);
        return first;
    }
private:
    using Clock = std::chrono::steady_clock;
    Clock::time_point retry_after_{};
    int applied_ = -1, failed_ = -1;
};
}

struct CameraLighting::Board {
    Board(const std::string& pwm, const char* camera)
        : duty(pwm + "/duty_cycle"), enable(pwm + "/enable"), camera_path(camera) {
        setActive(false);
    }
    ~Board() { setActive(false, true); }

    bool setActive(bool active, bool shutdown = false) noexcept {
        if (!state.shouldWrite(active, shutdown)) return state.isApplied(active);
        // A 250 us pulse on the board's 1 ms PWM period preserves the 25% cap.
        if (active && writeValue(duty, 250000) && writeValue(enable, 1)) {
            state.applied(true);
            std::fprintf(stderr, "[Lighting] white=25%%\n");
            return true;
        }
        const bool disabled = writeValue(enable, 0);
        const bool cleared = writeValue(duty, 0);
        if (active || !disabled || !cleared) {
            if (state.failed(active, disabled && cleared))
                std::fprintf(stderr, "[Lighting] white PWM write failed\n");
        } else {
            state.applied(false);
            std::fprintf(stderr, "[Lighting] white=0%%\n");
        }
        return state.isApplied(active);
    }

    std::string duty, enable, camera_path;
    bool camera_selected = false;
    LampState state;
};

CameraLighting::CameraLighting() {
    const char* pwm = std::getenv("HIFACE_LIGHT_PWM_PATH");
    const char* camera = std::getenv("HIFACE_LIGHT_CAMERA_DEVICE");
    if (pwm && *pwm)
        board_ = std::make_unique<Board>(pwm, camera && *camera ? camera : "/dev/video31");
}
CameraLighting::~CameraLighting() = default;

void CameraLighting::bindCamera(const std::string& camera) {
    if (!board_) return;
    std::error_code error;
    board_->camera_selected = !camera.empty() && (camera == board_->camera_path ||
        std::filesystem::equivalent(camera, board_->camera_path, error));
}
bool CameraLighting::setActive(bool active) noexcept {
    return !board_ || board_->setActive(active && board_->camera_selected);
}

struct InfraredLighting::Board {
    explicit Board(const char* path) : value_path(path) {
        if (!setActive(false)) throw std::runtime_error("Cannot initialize the infrared light GPIO");
    }
    ~Board() { setActive(false, true); }
    bool setActive(bool active, bool shutdown = false) noexcept;

    std::string value_path;
    LampState state;
};

bool InfraredLighting::Board::setActive(bool active, bool shutdown) noexcept {
    if (!state.shouldWrite(active, shutdown)) return state.isApplied(active);
    if (writeValue(value_path, active ? 1 : 0)) {
        state.applied(active);
        std::fprintf(stderr, "[Lighting] infrared=%s\n", active ? "on" : "off");
        return true;
    }
    const int error = errno;
    const bool confirmed_off = active && writeValue(value_path, 0);
    if (state.failed(active, confirmed_off))
        std::fprintf(stderr, "[Lighting] infrared %s failed: %s\n", active ? "on" : "off", std::strerror(error));
    return false;
}

InfraredLighting::InfraredLighting(const std::string& camera) {
    const char* value_path = std::getenv("HIFACE_IR_LIGHT_GPIO_VALUE");
    const char* board_camera = std::getenv("HIFACE_IR_LIGHT_CAMERA_DEVICE");
    const bool has_path = value_path && *value_path, has_camera = board_camera && *board_camera;
    if (!has_path && !has_camera) return; // External/USB illumination needs no GPIO configuration.
    if (!has_path || !has_camera)
        throw std::runtime_error("Infrared lighting requires both GPIO value and camera configuration");
    std::error_code error;
    if (!std::filesystem::equivalent(camera, board_camera, error))
        throw std::runtime_error("The infrared light is bound to a different or unavailable camera");
    board_ = std::make_unique<Board>(value_path);
}
InfraredLighting::~InfraredLighting() = default;

bool InfraredLighting::setActive(bool active) noexcept {
    return board_ && board_->setActive(active);
}

struct SearchStatusLighting::Board {
    Board(const char* red, const char* green, const char* blue) : paths{red, green, blue} {}
    ~Board() { setColor(SearchLightColor::off, true); }

    bool clear() noexcept {
        bool off = true;
        for (const auto& path : paths) off = writeValue(path, 0) && off;
        return off;
    }

    void setColor(SearchLightColor color, bool shutdown = false) noexcept {
        const int value = static_cast<int>(color);
        if (!state.shouldWrite(value, shutdown)) return;
        // Turn the previous color off before enabling another channel.
        const bool cleared = clear();
        if (cleared && (color == SearchLightColor::off || writeValue(paths[value - 1], 1))) {
            state.applied(value);
            constexpr const char* names[] = {"off", "red", "green", "blue"};
            std::fprintf(stderr, "[Lighting] search_status=%s\n", names[value]);
        } else if (state.failed(value, cleared && clear())) {
            std::fprintf(stderr, "[Lighting] search status GPIO write failed\n");
        }
    }

    std::array<std::string, 3> paths;
    LampState state;
};

SearchStatusLighting::SearchStatusLighting() {
    const char* red = std::getenv("HIFACE_RGBIR_LED_RED");
    const char* green = std::getenv("HIFACE_RGBIR_LED_GREEN");
    const char* blue = std::getenv("HIFACE_RGBIR_LED_BLUE");
    if (red && *red && green && *green && blue && *blue)
        board_ = std::make_unique<Board>(red, green, blue);
}
SearchStatusLighting::~SearchStatusLighting() = default;

void SearchStatusLighting::setColor(SearchLightColor color) noexcept {
    if (board_) board_->setColor(color);
}
}
