#include "camera.h"
#include "image_decode.h"
#include <array>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <dlfcn.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
namespace hiface_linux_demo {
namespace {
int request(int fd, unsigned long code, void* value) {
    int result;
    do { result = ioctl(fd, code, value); } while (result < 0 && errno == EINTR);
    return result;
}
void cameraCheck(bool okay, const std::string& operation) {
    require(okay, operation + ": " + std::strerror(errno));
}

// Minimal ABI copied from Rockchip's Apache-2.0 im2d headers. Keeping this
// private lets the Demo load the board-provided librga at runtime without
// adding a build-time dependency to the portable Linux SDK package.
// 从 Rockchip Apache-2.0 im2d 头文件保留的最小 ABI 声明；仅供 Demo 动态加载板载 librga，不给可移植 Linux SDK 增加构建依赖。
struct RgaColorKey { int max, min; };
struct RgaNn { int scale_r, scale_g, scale_b, offset_r, offset_g, offset_b; };
struct RgaBuffer {
    void* virtual_address;
    void* physical_address;
    int fd;
    int width, height, width_stride, height_stride, format;
    int color_space_mode;
    union { int global_alpha; struct { uint16_t alpha0, alpha1; } alpha_bit; };
    int read_mode;
    int color;
    RgaColorKey color_key;
    RgaNn nn;
    int rop_code;
    uint32_t handle;
};
struct RgaRect { int x, y, width, height; };
static_assert(sizeof(RgaBuffer) == 96, "Unexpected 64-bit Rockchip RGA buffer ABI");

constexpr int kRgaBgrx8888 = 0x16 << 8;
constexpr int kRgaNv12 = 0xa << 8;
constexpr int kRgaNv21 = 0xe << 8;
constexpr int kRgaRotate90 = 1 << 0;
constexpr int kRgaRotate270 = 1 << 2;
constexpr int kRgaSync = 1 << 19;
constexpr int kRgaBt601Limited = 1 << 0;
constexpr int kRgaBt601Full = 2 << 0;
constexpr int kRgaBt709Limited = 3 << 0;

class RgaPreview {
public:
    RgaPreview() {
        const char* dma = std::getenv("HIFACE_PREVIEW_DMA");
        dma_disabled_ = dma && !std::strcmp(dma, "0");
        library_ = dlopen("librga.so.2", RTLD_NOW | RTLD_LOCAL);
        if (!library_) library_ = dlopen("librga.so", RTLD_NOW | RTLD_LOCAL);
        if (!library_) return;
        wrap_ = reinterpret_cast<Wrap>(dlsym(library_, "wrapbuffer_virtualaddr_t"));
        wrap_fd_ = reinterpret_cast<WrapFd>(dlsym(library_, "wrapbuffer_fd_t"));
        process_ = reinterpret_cast<Process>(dlsym(library_, "improcess"));
        error_ = reinterpret_cast<Error>(dlsym(library_, "imStrError_t"));
        if (!wrap_ || !process_) { dlclose(library_); library_ = nullptr; }
    }
    ~RgaPreview() { if (library_) dlclose(library_); }
    RgaPreview(const RgaPreview&) = delete;
    RgaPreview& operator=(const RgaPreview&) = delete;

    void convert(const uint8_t* source, int dma_fd, int source_width, int source_height, int source_stride,
                 bool nv21, HiFaceYuvRangeV1 range, HiFaceYuvMatrixV1 matrix,
                 int output_width, int output_height, int rotation, CameraFrame& frame) {
        require(library_, "Rockchip RGA preview is unavailable");
        require(source && source_width >= 2 && source_height >= 2 && source_stride >= source_width,
            "Invalid RGA preview source");
        require(output_width >= 2 && output_height >= 2 && output_width <= 1920 && output_height <= 1920,
            "Invalid RGA preview size");
        frame.width = output_width;
        frame.height = output_height;
        frame.range = HIFACE_YUV_RANGE_FULL;
        frame.matrix = matrix;
        frame.x11_bgrx = true;
        frame.i420.clear();
        frame.rgba.resize(static_cast<size_t>(output_width) * output_height * 4);
        const bool dma = dma_fd >= 0 && wrap_fd_ && !dma_disabled_;
        auto input = dma ? wrap_fd_(dma_fd, source_width, source_height,
            source_stride, source_height, nv21 ? kRgaNv21 : kRgaNv12)
            : wrap_(const_cast<uint8_t*>(source), source_width, source_height,
                source_stride, source_height, nv21 ? kRgaNv21 : kRgaNv12);
        auto output = wrap_(frame.rgba.data(), output_width, output_height,
            output_width, output_height, kRgaBgrx8888);
        input.color_space_mode = matrix == HIFACE_YUV_MATRIX_BT709
            ? kRgaBt709Limited : range == HIFACE_YUV_RANGE_FULL ? kRgaBt601Full : kRgaBt601Limited;
        RgaBuffer empty{};
        RgaRect rect{};
        int status = process_(input, output, empty, rect, rect, rect, rotation | kRgaSync);
        if (status <= 0 && dma) {
            dma_disabled_ = true;
            const int color_space = input.color_space_mode;
            input = wrap_(const_cast<uint8_t*>(source), source_width, source_height,
                source_stride, source_height, nv21 ? kRgaNv21 : kRgaNv12);
            input.color_space_mode = color_space;
            status = process_(input, output, empty, rect, rect, rect, rotation | kRgaSync);
        }
        if (!source_logged_ && status > 0) {
            std::fprintf(stderr, "[RGA] preview source: %s\n", dma && !dma_disabled_ ? "V4L2 DMA-BUF" : "mapped CPU memory (fallback)");
            source_logged_ = true;
        }
        const char* detail = error_ ? error_(status) : nullptr;
        require(status > 0, std::string("Rockchip RGA preview conversion failed") +
            (detail && *detail ? ": " + std::string(detail) : " (" + std::to_string(status) + ")"));
    }
private:
    using Wrap = RgaBuffer (*)(void*, int, int, int, int, int);
    using WrapFd = RgaBuffer (*)(int, int, int, int, int, int);
    using Process = int (*)(RgaBuffer, RgaBuffer, RgaBuffer, RgaRect, RgaRect, RgaRect, int);
    using Error = const char* (*)(int);
    void* library_ = nullptr;
    Wrap wrap_ = nullptr;
    WrapFd wrap_fd_ = nullptr;
    bool dma_disabled_ = false, source_logged_ = false;
    Process process_ = nullptr;
    Error error_ = nullptr;
};

RgaPreview& rgaPreview() {
    static RgaPreview instance;
    return instance;
}
}
Camera::~Camera() { close(); }
void Camera::close() noexcept {
    if (streaming_) request(fd_, VIDIOC_STREAMOFF, &type_);
    streaming_ = false;
    for (auto& buffer : buffers_) {
        if (buffer.dma_fd >= 0) ::close(buffer.dma_fd);
        munmap(buffer.data, buffer.size);
    }
    buffers_.clear();
    if (fd_ >= 0) ::close(fd_);
    fd_ = -1; type_ = 0; plane_count_ = 0;
}
void Camera::open(const std::string& device, int width, int height, int fps, bool prefer_mjpeg) {
    close();
    try {
        const char* rotation = std::getenv("HIFACE_CAMERA_ROTATE");
        rotation_ = Rotation::none;
        if (rotation && (!std::strcmp(rotation, "left") || !std::strcmp(rotation, "ccw") || !std::strcmp(rotation, "90ccw")))
            rotation_ = Rotation::counter_clockwise;
        else if (rotation && (!std::strcmp(rotation, "right") || !std::strcmp(rotation, "cw") || !std::strcmp(rotation, "90cw")))
            rotation_ = Rotation::clockwise;
        require(!rotation || !*rotation || rotation_ != Rotation::none,
            "HIFACE_CAMERA_ROTATE must be left/ccw/90ccw or right/cw/90cw");
        fd_ = ::open(device.c_str(), O_RDWR | O_NONBLOCK | O_CLOEXEC);
        cameraCheck(fd_ >= 0, "Cannot open " + device + " (check video-device permission)");
        v4l2_capability capability{};
        cameraCheck(request(fd_, VIDIOC_QUERYCAP, &capability) == 0, "Query camera");
        const auto caps = capability.capabilities & V4L2_CAP_DEVICE_CAPS ? capability.device_caps : capability.capabilities;
        const bool multiplanar = caps & V4L2_CAP_VIDEO_CAPTURE_MPLANE;
        require((multiplanar || (caps & V4L2_CAP_VIDEO_CAPTURE)) && (caps & V4L2_CAP_STREAMING),
            "Device is not a streaming camera");
        type_ = multiplanar ? V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE : V4L2_BUF_TYPE_VIDEO_CAPTURE;
        bool supported = false;
        for (uint32_t wanted : prefer_mjpeg ? std::vector<uint32_t>{V4L2_PIX_FMT_MJPEG, V4L2_PIX_FMT_YUYV,
                                                 V4L2_PIX_FMT_NV12, V4L2_PIX_FMT_NV21}
                                           : std::vector<uint32_t>{V4L2_PIX_FMT_YUYV, V4L2_PIX_FMT_MJPEG,
                                                 V4L2_PIX_FMT_NV12, V4L2_PIX_FMT_NV21}) {
            v4l2_format format{};
            format.type = type_;
            if (multiplanar) {
                format.fmt.pix_mp.width = width; format.fmt.pix_mp.height = height;
                format.fmt.pix_mp.pixelformat = wanted; format.fmt.pix_mp.field = V4L2_FIELD_ANY;
            } else {
                format.fmt.pix.width = width; format.fmt.pix.height = height;
                format.fmt.pix.pixelformat = wanted; format.fmt.pix.field = V4L2_FIELD_ANY;
            }
            if (request(fd_, VIDIOC_S_FMT, &format) != 0) continue;
            const auto negotiated_format = multiplanar ? format.fmt.pix_mp.pixelformat : format.fmt.pix.pixelformat;
            if (negotiated_format != wanted) continue;
            width_ = multiplanar ? format.fmt.pix_mp.width : format.fmt.pix.width;
            height_ = multiplanar ? format.fmt.pix_mp.height : format.fmt.pix.height;
            format_ = wanted;
            plane_count_ = multiplanar ? format.fmt.pix_mp.num_planes : 1;
            require(plane_count_ == 1, "Camera format must use one packed buffer plane");
            const auto bytesperline = multiplanar ? format.fmt.pix_mp.plane_fmt[0].bytesperline : format.fmt.pix.bytesperline;
            stride_ = bytesperline ? bytesperline : width_ * (wanted == V4L2_PIX_FMT_YUYV ? 2 : 1);
            const auto colorspace = multiplanar ? format.fmt.pix_mp.colorspace : format.fmt.pix.colorspace;
            const auto raw_encoding = multiplanar ? format.fmt.pix_mp.ycbcr_enc : format.fmt.pix.ycbcr_enc;
            const auto raw_quantization = multiplanar ? format.fmt.pix_mp.quantization : format.fmt.pix.quantization;
            const auto encoding = raw_encoding == V4L2_YCBCR_ENC_DEFAULT
                ? V4L2_MAP_YCBCR_ENC_DEFAULT(colorspace) : raw_encoding;
            const auto quantization = raw_quantization == V4L2_QUANTIZATION_DEFAULT
                ? V4L2_MAP_QUANTIZATION_DEFAULT(false, colorspace, encoding) : raw_quantization;
            require(wanted == V4L2_PIX_FMT_MJPEG || encoding == V4L2_YCBCR_ENC_601 || encoding == V4L2_YCBCR_ENC_709,
                "Camera YUV matrix must be BT.601 or BT.709");
            range_ = quantization == V4L2_QUANTIZATION_FULL_RANGE ? HIFACE_YUV_RANGE_FULL : HIFACE_YUV_RANGE_VIDEO;
            matrix_ = encoding == V4L2_YCBCR_ENC_709 ? HIFACE_YUV_MATRIX_BT709 : HIFACE_YUV_MATRIX_BT601;
            supported = true; break;
        }
        require(supported, "Camera must support YUYV, MJPEG, NV12 or NV21 streaming");
        require(width_ >= 2 && height_ >= 2 && !(width_ & 1) && !(height_ & 1)
            && width_ <= 1920 && height_ <= 1080, "Camera resolution exceeds 1920x1080");
        v4l2_streamparm parameters{}; parameters.type = type_;
        parameters.parm.capture.timeperframe = {1, static_cast<uint32_t>(fps)};
        request(fd_, VIDIOC_S_PARM, &parameters); // Driver may select another rate. / 驱动可能选择其他帧率。
        v4l2_streamparm negotiated{}; negotiated.type = type_;
        const bool has_rate = request(fd_, VIDIOC_G_PARM, &negotiated) == 0
            && negotiated.parm.capture.timeperframe.numerator && negotiated.parm.capture.timeperframe.denominator;
        v4l2_requestbuffers allocation{};
        allocation.count = 4; allocation.type = type_; allocation.memory = V4L2_MEMORY_MMAP;
        cameraCheck(request(fd_, VIDIOC_REQBUFS, &allocation) == 0, "Allocate camera buffers");
        require(allocation.count >= 2 && allocation.count <= 32, "Invalid camera buffer count");
        buffers_.reserve(allocation.count);
        for (uint32_t i = 0; i < allocation.count; ++i) {
            v4l2_buffer buffer{}; buffer.type = allocation.type; buffer.memory = allocation.memory; buffer.index = i;
            std::array<v4l2_plane, VIDEO_MAX_PLANES> planes{};
            if (multiplanar) { buffer.m.planes = planes.data(); buffer.length = plane_count_; }
            cameraCheck(request(fd_, VIDIOC_QUERYBUF, &buffer) == 0, "Query camera buffer");
            const auto length = multiplanar ? planes[0].length : buffer.length;
            const auto offset = multiplanar ? planes[0].m.mem_offset : buffer.m.offset;
            require(length > 0 && length <= 32 * 1024 * 1024, "Invalid camera buffer length");
            auto* bytes = mmap(nullptr, length, PROT_READ | PROT_WRITE, MAP_SHARED, fd_, offset);
            cameraCheck(bytes != MAP_FAILED, "Map camera buffer");
            v4l2_exportbuffer exported{};
            exported.type = allocation.type; exported.index = i; exported.flags = O_CLOEXEC;
            // Optional: ISP buffers can feed RGA directly without pinning and
            // flushing the entire mapped NV12 input on every preview frame.
            // 可选地将 ISP 缓冲直接交给 RGA，避免每个预览帧都固定并刷新整份映射的 NV12 输入。
            const int dma_fd = request(fd_, VIDIOC_EXPBUF, &exported) == 0 ? exported.fd : -1;
            buffers_.push_back({bytes, length, dma_fd});
            cameraCheck(request(fd_, VIDIOC_QBUF, &buffer) == 0, "Queue camera buffer");
        }
        cameraCheck(request(fd_, VIDIOC_STREAMON, &type_) == 0, "Start camera");
        streaming_ = true;
        description_ = device + "  " + std::to_string(width_) + "x" + std::to_string(height_) +
            (format_ == V4L2_PIX_FMT_YUYV ? " YUYV" : format_ == V4L2_PIX_FMT_MJPEG ? " MJPEG" :
                format_ == V4L2_PIX_FMT_NV12 ? " NV12" : " NV21");
        if (has_rate) description_ += " " + std::to_string(double(negotiated.parm.capture.timeperframe.denominator)
            / negotiated.parm.capture.timeperframe.numerator) + " FPS";
        else description_ += " (requested " + std::to_string(fps) + " FPS)";
        if (rotation_ != Rotation::none)
            description_ += " -> " + std::to_string(height_) + "x" + std::to_string(width_) +
                (rotation_ == Rotation::counter_clockwise ? " CCW90" : " CW90");
    } catch (...) { close(); throw; }
}
bool Camera::read(CameraFrame& frame) { return readFrame(frame, 0, 0, false); }
bool Camera::readAnalysis(CameraFrame& frame) { return readFrame(frame, 0, 0, true); }
bool Camera::readPreview(CameraFrame& frame, int output_width, int output_height) {
    return readFrame(frame, output_width, output_height, false);
}
bool Camera::waitForFrame(int timeout_ms) {
    if (!streaming_) return false;
    pollfd descriptor{fd_, POLLIN, 0};
    const int polled = poll(&descriptor, 1, timeout_ms);
    if (polled < 0 && errno == EINTR) return false;
    cameraCheck(polled >= 0 && !(descriptor.revents & (POLLERR | POLLHUP | POLLNVAL)), "Camera disconnected");
    return polled > 0;
}
bool Camera::requestFrameRate(int fps) {
    if (!streaming_ || fps <= 0) return false;
    v4l2_streamparm parameters{}; parameters.type = type_;
    if (request(fd_, VIDIOC_G_PARM, &parameters) < 0 ||
        !(parameters.parm.capture.capability & V4L2_CAP_TIMEPERFRAME)) return false;
    parameters.parm.capture.timeperframe = {1, static_cast<uint32_t>(fps)};
    return request(fd_, VIDIOC_S_PARM, &parameters) == 0;
}
bool Camera::readFrame(CameraFrame& frame, int preview_width, int preview_height, bool analysis_only) {
    if (!waitForFrame(0)) return false;
    const bool multiplanar = type_ == V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
    v4l2_buffer buffer{}; buffer.type = type_; buffer.memory = V4L2_MEMORY_MMAP;
    std::array<v4l2_plane, VIDEO_MAX_PLANES> planes{};
    if (multiplanar) { buffer.m.planes = planes.data(); buffer.length = plane_count_; }
    if (request(fd_, VIDIOC_DQBUF, &buffer) < 0) {
        if (errno == EAGAIN) return false;
        cameraCheck(false, "Read camera buffer");
    }
    // Inference can take longer than one camera interval. Discard queued older
    // buffers and analyze the newest available frame instead of building lag.
    // 推理可能超过一个相机周期；丢弃排队旧缓冲，分析最新帧，避免累积延迟。
    for (size_t i = 1; i < buffers_.size(); ++i) {
        v4l2_buffer newer{}; newer.type = buffer.type; newer.memory = buffer.memory;
        std::array<v4l2_plane, VIDEO_MAX_PLANES> newer_planes{};
        if (multiplanar) { newer.m.planes = newer_planes.data(); newer.length = plane_count_; }
        if (request(fd_, VIDIOC_DQBUF, &newer) < 0) {
            if (errno == EAGAIN) break;
            request(fd_, VIDIOC_QBUF, &buffer);
            cameraCheck(false, "Drain camera queue");
        }
        cameraCheck(request(fd_, VIDIOC_QBUF, &buffer) == 0, "Return stale camera frame");
        buffer = newer;
        if (multiplanar) { planes = newer_planes; buffer.m.planes = planes.data(); }
    }
    require(buffer.index < buffers_.size(), "Camera returned invalid buffer index");
    if (buffer.flags & V4L2_BUF_FLAG_ERROR) {
        cameraCheck(request(fd_, VIDIOC_QBUF, &buffer) == 0, "Return damaged camera frame");
        return false;
    }
    try {
        const auto bytesused = multiplanar ? planes[0].bytesused : buffer.bytesused;
        require(bytesused > 0 && bytesused <= buffers_[buffer.index].size, "Truncated camera buffer");
        const auto* pixels = static_cast<const uint8_t*>(buffers_[buffer.index].data);
        if (preview_width > 0 && preview_height > 0) {
            require(format_ == V4L2_PIX_FMT_NV12 || format_ == V4L2_PIX_FMT_NV21,
                "RGA preview requires an NV12 or NV21 camera stream");
            const int rotation = rotation_ == Rotation::clockwise ? kRgaRotate90
                : rotation_ == Rotation::counter_clockwise ? kRgaRotate270 : 0;
            rgaPreview().convert(pixels, buffers_[buffer.index].dma_fd, width_, height_, stride_, format_ == V4L2_PIX_FMT_NV21,
                range_, matrix_, preview_width, preview_height, rotation, frame);
        } else if (format_ == V4L2_PIX_FMT_YUYV)
            yuyvFrame(pixels, bytesused, width_, height_, stride_, range_, matrix_, frame, !analysis_only);
        else if (format_ == V4L2_PIX_FMT_NV12 || format_ == V4L2_PIX_FMT_NV21)
            nv12Frame(pixels, bytesused, width_, height_, stride_, format_ == V4L2_PIX_FMT_NV21,
                range_, matrix_, frame, !analysis_only);
        else {
            const auto image = decodeJpeg(pixels, bytesused);
            require(image.width == width_ && image.height == height_, "Camera JPEG dimensions differ from negotiated video size");
            rgbaFrame(image, frame);
        }
        if (!preview_width && rotation_ == Rotation::counter_clockwise) rotateFrameCounterClockwise(frame);
        else if (!preview_width && rotation_ == Rotation::clockwise) rotateFrameClockwise(frame);
    } catch (...) { request(fd_, VIDIOC_QBUF, &buffer); throw; }
    cameraCheck(request(fd_, VIDIOC_QBUF, &buffer) == 0, "Return camera buffer");
    return true;
}
}
