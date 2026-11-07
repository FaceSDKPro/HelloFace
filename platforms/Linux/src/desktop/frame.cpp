#include "camera.h"
#include <algorithm>
#include <cmath>
#include <cstring>
namespace hiface_linux_demo {
namespace {
uint8_t clip(double value) { return static_cast<uint8_t>(std::clamp(std::lround(value), 0L, 255L)); }
void preview(CameraFrame& frame) {
    const size_t count = static_cast<size_t>(frame.width) * frame.height;
    frame.rgba.resize(count * 4);
    for (int y = 0; y < frame.height; ++y) for (int x = 0; x < frame.width; ++x) {
        const size_t offset = static_cast<size_t>(y) * frame.width + x;
        const size_t chroma = static_cast<size_t>(y / 2) * (frame.width / 2) + x / 2;
        const double luma = frame.range == HIFACE_YUV_RANGE_VIDEO
            ? (frame.i420[offset] - 16) * (255.0 / 219) : frame.i420[offset];
        const double u = (frame.i420[count + chroma] - 128) *
            (frame.range == HIFACE_YUV_RANGE_VIDEO ? 255.0 / 224 : 1);
        const double v = (frame.i420[count * 5 / 4 + chroma] - 128) *
            (frame.range == HIFACE_YUV_RANGE_VIDEO ? 255.0 / 224 : 1);
        const bool bt709 = frame.matrix == HIFACE_YUV_MATRIX_BT709;
        frame.rgba[offset * 4] = clip(luma + (bt709 ? 1.5748 : 1.402) * v);
        frame.rgba[offset * 4 + 1] = clip(luma - (bt709 ? .187324 : .344136) * u - (bt709 ? .468124 : .714136) * v);
        frame.rgba[offset * 4 + 2] = clip(luma + (bt709 ? 1.8556 : 1.772) * u);
        frame.rgba[offset * 4 + 3] = 255;
    }
}
void rotatePlane90(const uint8_t* source, int source_width, int source_height,
                   uint8_t* destination, bool clockwise) {
    for (int source_y = 0; source_y < source_height; ++source_y)
        for (int source_x = 0; source_x < source_width; ++source_x) {
            const int destination_x = clockwise ? source_height - 1 - source_y : source_y;
            const int destination_y = clockwise ? source_x : source_width - 1 - source_x;
            destination[static_cast<size_t>(destination_y) * source_height + destination_x] =
                source[static_cast<size_t>(source_y) * source_width + source_x];
        }
}
void rotateRgba90(const uint8_t* source, int source_width, int source_height,
                  uint8_t* destination, bool clockwise) {
    for (int source_y = 0; source_y < source_height; ++source_y)
        for (int source_x = 0; source_x < source_width; ++source_x) {
            const int destination_x = clockwise ? source_height - 1 - source_y : source_y;
            const int destination_y = clockwise ? source_x : source_width - 1 - source_x;
            std::memcpy(destination + (static_cast<size_t>(destination_y) * source_height + destination_x) * 4,
                source + (static_cast<size_t>(source_y) * source_width + source_x) * 4, 4);
        }
}
void rotateFrame90(CameraFrame& frame, bool clockwise) {
    require(frame.width >= 2 && frame.height >= 2 && !(frame.width & 1) && !(frame.height & 1),
        "Camera rotation requires even dimensions");
    const int source_width = frame.width, source_height = frame.height;
    const size_t count = static_cast<size_t>(source_width) * source_height;
    require(frame.i420.empty() || frame.i420.size() == count * 3 / 2, "Invalid I420 frame for camera rotation");
    require(frame.rgba.empty() || frame.rgba.size() == count * 4, "Invalid RGBA preview for camera rotation");
    require(!frame.i420.empty() || !frame.rgba.empty(), "Empty camera frame for rotation");
    const auto i420_source = std::move(frame.i420);
    const auto rgba_source = std::move(frame.rgba);
    frame.i420.resize(i420_source.size());
    if (!rgba_source.empty()) frame.rgba.resize(rgba_source.size());
    if(!i420_source.empty()) {
        rotatePlane90(i420_source.data(), source_width, source_height, frame.i420.data(), clockwise);
        rotatePlane90(i420_source.data() + count, source_width / 2, source_height / 2,
            frame.i420.data() + count, clockwise);
        rotatePlane90(i420_source.data() + count * 5 / 4, source_width / 2, source_height / 2,
            frame.i420.data() + count * 5 / 4, clockwise);
    }
    if (!rgba_source.empty())
        rotateRgba90(rgba_source.data(), source_width, source_height, frame.rgba.data(), clockwise);
    frame.width = source_height;
    frame.height = source_width;
}
}
HiFaceYuv420FrameV1 CameraFrame::view() const {
    const size_t count = static_cast<size_t>(width) * height;
    HiFaceYuv420FrameV1 frame{};
    frame.struct_size = sizeof(frame); frame.width = width; frame.height = height;
    frame.y = {i420.data(), count, width, 1};
    frame.u = {i420.data() + count, count / 4, width / 2, 1};
    frame.v = {i420.data() + count * 5 / 4, count / 4, width / 2, 1};
    frame.range = range; frame.matrix = matrix;
    return frame;
}
void infraredFrame(const uint8_t* bytes, size_t size, int width, int height, int stride,
                   bool yuyv, int rotation, CameraFrame& frame) {
    const int pixel_stride = yuyv ? 2 : 1;
    require(bytes && width >= 2 && height >= 2 && !(width & 1) && !(height & 1)
        && width <= 1920 && height <= 1080 && stride >= width * pixel_stride
        && size >= static_cast<size_t>(stride) * (height - 1) + width * pixel_stride,
        "Invalid infrared frame");
    require(rotation >= 0 && rotation <= 270 && rotation % 90 == 0, "Unsupported infrared rotation");
    const bool swap = rotation == 90 || rotation == 270;
    frame.width = swap ? height : width;
    frame.height = swap ? width : height;
    frame.i420.clear();
    frame.rgba.clear();
    frame.gray.resize(static_cast<size_t>(width) * height);
    for (int y = 0; y < height; ++y) {
        const auto* row = bytes + static_cast<size_t>(y) * stride;
        if (!rotation && !yuyv) {
            std::memcpy(frame.gray.data() + static_cast<size_t>(y) * width, row, width);
            continue;
        }
        for (int x = 0; x < width; ++x) {
            const int out_x = rotation == 90 ? height - 1 - y : rotation == 270 ? y : rotation == 180 ? width - 1 - x : x;
            const int out_y = rotation == 90 ? x : rotation == 270 ? width - 1 - x : rotation == 180 ? height - 1 - y : y;
            frame.gray[static_cast<size_t>(out_y) * frame.width + out_x] = row[x * pixel_stride];
        }
    }
}
void rotateFrame180(CameraFrame& frame) {
    const size_t count = static_cast<size_t>(frame.width) * frame.height;
    require(frame.width>=2 && frame.height>=2 && !(frame.width&1) && !(frame.height&1) &&
        (frame.i420.empty() || frame.i420.size() == count * 3 / 2) && (frame.rgba.empty() || frame.rgba.size() == count * 4) &&
        (!frame.i420.empty() || !frame.rgba.empty()),
        "Invalid camera frame for rotation");
    if(!frame.i420.empty()) {
        auto y = frame.i420.begin(), u = y + count, v = u + count / 4;
        std::reverse(y, u);std::reverse(u, v);std::reverse(v, frame.i420.end());
    }
    if (!frame.rgba.empty())
        for (size_t i = 0; i < count / 2; ++i)
            std::swap_ranges(frame.rgba.begin() + 4 * i, frame.rgba.begin() + 4 * (i + 1),
                frame.rgba.begin() + 4 * (count - 1 - i));
}
void yuyvFrame(const uint8_t* bytes, size_t size, int width, int height, int stride,
              HiFaceYuvRangeV1 range, HiFaceYuvMatrixV1 matrix, CameraFrame& frame, bool make_preview) {
    require(bytes && width >= 2 && height >= 2 && !(width & 1) && !(height & 1)
        && width <= 1920 && height <= 1080 && stride >= width * 2
        && size >= static_cast<size_t>(stride) * (height - 1) + width * 2, "Invalid YUYV frame");
    frame.width = width; frame.height = height; frame.range = range; frame.matrix = matrix;
    frame.x11_bgrx = false;
    const size_t count = static_cast<size_t>(width) * height;
    frame.i420.resize(count * 3 / 2);
    for (int y = 0; y < height; ++y) for (int x = 0; x < width; x += 2) {
        const auto* input = bytes + static_cast<size_t>(y) * stride + x * 2;
        frame.i420[static_cast<size_t>(y) * width + x] = input[0];
        frame.i420[static_cast<size_t>(y) * width + x + 1] = input[2];
        if (!(y & 1)) {
            const size_t uv = static_cast<size_t>(y / 2) * (width / 2) + x / 2;
            frame.i420[count + uv] = (unsigned(input[1]) + input[stride + 1] + 1) / 2;
            frame.i420[count * 5 / 4 + uv] = (unsigned(input[3]) + input[stride + 3] + 1) / 2;
        }
    }
    if (make_preview) preview(frame); else frame.rgba.clear();
}
void nv12Frame(const uint8_t* bytes, size_t size, int width, int height, int stride, bool nv21,
              HiFaceYuvRangeV1 range, HiFaceYuvMatrixV1 matrix, CameraFrame& frame, bool make_preview) {
    const size_t y_bytes = static_cast<size_t>(stride) * height;
    const size_t required = y_bytes + static_cast<size_t>(stride) * (height / 2 - 1) + width;
    require(bytes && width >= 2 && height >= 2 && !(width & 1) && !(height & 1)
        && width <= 1920 && height <= 1080 && stride >= width && size >= required, "Invalid NV12/NV21 frame");
    frame.width = width; frame.height = height; frame.range = range; frame.matrix = matrix;
    frame.x11_bgrx = false;
    const size_t count = static_cast<size_t>(width) * height;
    frame.i420.resize(count * 3 / 2);
    for (int y = 0; y < height; ++y)
        std::memcpy(frame.i420.data() + static_cast<size_t>(y) * width,
            bytes + static_cast<size_t>(y) * stride, width);
    const auto* chroma = bytes + y_bytes;
    for (int y = 0; y < height / 2; ++y) for (int x = 0; x < width; x += 2) {
        const auto* pair = chroma + static_cast<size_t>(y) * stride + x;
        const size_t index = static_cast<size_t>(y) * (width / 2) + x / 2;
        frame.i420[count + index] = pair[nv21 ? 1 : 0];
        frame.i420[count * 5 / 4 + index] = pair[nv21 ? 0 : 1];
    }
    if (make_preview) preview(frame); else frame.rgba.clear();
}
void rgbaFrame(const Image& image, CameraFrame& frame, bool make_preview) {
    const int width = image.width, height = image.height;
    require(width >= 2 && height >= 2 && width <= 1920 && height <= 1080 && !(width & 1) && !(height & 1)
        && image.rgba.size() == static_cast<size_t>(width) * height * 4, "Unsupported camera image size");
    frame.width = width; frame.height = height; frame.x11_bgrx = false;
    frame.range = HIFACE_YUV_RANGE_FULL; frame.matrix = HIFACE_YUV_MATRIX_BT601;
    if (make_preview) frame.rgba = image.rgba; else frame.rgba.clear();
    const size_t count = static_cast<size_t>(width) * height;
    frame.i420.resize(count * 3 / 2);
    for (int y = 0; y < height; y += 2) for (int x = 0; x < width; x += 2) {
        double us = 0, vs = 0;
        for (int dy = 0; dy < 2; ++dy) for (int dx = 0; dx < 2; ++dx) {
            const size_t index = static_cast<size_t>(y + dy) * width + x + dx;
            const auto* pixel = image.rgba.data() + index * 4;
            const double r = pixel[0], g = pixel[1], b = pixel[2];
            frame.i420[index] = clip(.299 * r + .587 * g + .114 * b);
            us += -.168736 * r - .331264 * g + .5 * b + 128;
            vs += .5 * r - .418688 * g - .081312 * b + 128;
        }
        const size_t index = static_cast<size_t>(y / 2) * (width / 2) + x / 2;
        frame.i420[count + index] = clip(us / 4);
        frame.i420[count * 5 / 4 + index] = clip(vs / 4);
    }
}
void rotateFrameCounterClockwise(CameraFrame& frame) {
    rotateFrame90(frame, false);
}
void rotateFrameClockwise(CameraFrame& frame) {
    rotateFrame90(frame, true);
}
}
