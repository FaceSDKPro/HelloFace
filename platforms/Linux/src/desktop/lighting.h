#pragma once
#include <memory>
#include <string>

namespace hiface_linux_demo {
// Reports the backend actually linked into this executable, without touching hardware.
const char* lightingBackend() noexcept;
const char* lightingCapabilities() noexcept;
// One controller per capture worker. The selected backend owns the hardware.
class CameraLighting {
public:
    CameraLighting();
    ~CameraLighting();
    void bindCamera(const std::string& camera);
    bool setActive(bool active) noexcept;
private:
    struct Board;
    std::unique_ptr<Board> board_;
};

class InfraredLighting {
public:
    explicit InfraredLighting(const std::string& camera);
    ~InfraredLighting();
    bool configured() const { return bool(board_); }
    bool setActive(bool active) noexcept;
private:
    struct Board;
    std::unique_ptr<Board> board_;
};

enum class SearchLightColor { off, red, green, blue };

class SearchStatusLighting {
public:
    SearchStatusLighting();
    ~SearchStatusLighting();
    void setColor(SearchLightColor color) noexcept;
private:
    struct Board;
    std::unique_ptr<Board> board_;
};
}
