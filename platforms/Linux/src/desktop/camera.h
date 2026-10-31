#pragma once
#include "sdk_helpers.h"
#include <string>
#include <vector>
namespace hiface_linux_demo {
struct CameraFrame {
    int width = 0, height = 0;
    std::vector<uint8_t> rgba, i420;
    HiFaceYuvRangeV1 range = HIFACE_YUV_RANGE_VIDEO;
    HiFaceYuvMatrixV1 matrix = HIFACE_YUV_MATRIX_BT601;
    // Rockchip's BGRX byte order matches the little-endian X11 0x00RRGGBB
    // visual and can be uploaded without a per-pixel CPU channel swap.
    // Rockchip BGRX 字节序与小端 X11 的 0x00RRGGBB 视觉格式一致，可直接上传而无需 CPU 逐像素交换通道。
    bool x11_bgrx = false;
    HiFaceYuv420FrameV1 view() const;
};
// Pixel adapters only; all face analysis and flow decisions remain in Core.
// 仅适配像素；所有人脸分析和流程判定仍由 Core 完成。
void yuyvFrame(const uint8_t* bytes, size_t size, int width, int height, int stride,
              HiFaceYuvRangeV1 range, HiFaceYuvMatrixV1 matrix, CameraFrame& output,
              bool make_preview = true);
void nv12Frame(const uint8_t* bytes, size_t size, int width, int height, int stride, bool nv21,
              HiFaceYuvRangeV1 range, HiFaceYuvMatrixV1 matrix, CameraFrame& output,
              bool make_preview = true);
void rgbaFrame(const Image& image, CameraFrame& output);
void rotateFrameCounterClockwise(CameraFrame& frame);
void rotateFrameClockwise(CameraFrame& frame);
class Camera {
public:
    Camera() = default;
    ~Camera();
    Camera(const Camera&) = delete;
    Camera& operator=(const Camera&) = delete;
    void open(const std::string& device, int width = 640, int height = 360, int fps = 30, bool prefer_mjpeg = false);
    void close() noexcept;
    bool read(CameraFrame& frame);
    bool readAnalysis(CameraFrame& frame);
    // Convert a native NV12/NV21 frame directly into the final X11 BGRX
    // preview size with Rockchip RGA. Recognition uses readAnalysis().
    // 使用 Rockchip RGA 将原生 NV12/NV21 帧直接转换成最终 X11 BGRX 预览尺寸；识别仍使用 readAnalysis()。
    bool readPreview(CameraFrame& frame, int output_width, int output_height);
    const std::string& description() const { return description_; }
    bool ready() const { return streaming_; }
    bool waitForFrame(int timeout_ms);
    bool requestFrameRate(int fps); // Best effort, without restarting the stream.
private:
    enum class Rotation { none, counter_clockwise, clockwise };
    struct Buffer { void* data; size_t size; int dma_fd = -1; };
    int fd_ = -1, width_ = 0, height_ = 0, stride_ = 0, type_ = 0, plane_count_ = 0;
    uint32_t format_ = 0;
    bool streaming_ = false;
    Rotation rotation_ = Rotation::none;
    HiFaceYuvRangeV1 range_ = HIFACE_YUV_RANGE_VIDEO;
    HiFaceYuvMatrixV1 matrix_ = HIFACE_YUV_MATRIX_BT601;
    std::vector<Buffer> buffers_;
    std::string description_;
    bool readFrame(CameraFrame& frame, int preview_width, int preview_height, bool analysis_only);
};
}
