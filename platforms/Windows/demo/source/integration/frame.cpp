#include "hiface/frame.hpp"
#include <algorithm>
#include <stdexcept>
#include <utility>

namespace hiface {
Image CameraFrame::displayBgra(bool mirror) const {
    auto raw = previewBgra();
    // Default preview already has the required orientation: transfer its pixels.
    // 默认方向无需再分配、逐像素复制；旋转和镜像仅作用于展示。
    if (!rotation_degrees && !mirror) return {width, height, std::move(raw)};
    const bool quarter = rotation_degrees == 90 || rotation_degrees == 270;
    Image image{quarter ? height : width, quarter ? width : height, std::vector<uint8_t>(raw.size())};
    for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
        int out_x = x, out_y = y;
        if (rotation_degrees == 90) { out_x = height - y - 1; out_y = x; }
        else if (rotation_degrees == 180) { out_x = width - x - 1; out_y = height - y - 1; }
        else if (rotation_degrees == 270) { out_x = y; out_y = width - x - 1; }
        if (mirror) out_x = image.width - out_x - 1;
        std::copy_n(raw.data() + (static_cast<size_t>(y) * width + x) * 4, 4,
            image.rgba.data() + (static_cast<size_t>(out_y) * image.width + out_x) * 4);
    }
    return image;
}
HiFaceYuv420FrameV1 CameraFrame::view() const {
    if (width <= 0 || height <= 0 || (width & 1) || (height & 1)
        || std::max(width, height) > static_cast<int>(HIFACE_MAX_CAMERA_FRAME_LONG_SIDE)
        || std::min(width, height) > static_cast<int>(HIFACE_MAX_CAMERA_FRAME_SHORT_SIDE)
        || (range != HIFACE_YUV_RANGE_VIDEO && range != HIFACE_YUV_RANGE_FULL)
        || (matrix != HIFACE_YUV_MATRIX_BT601 && matrix != HIFACE_YUV_MATRIX_BT709)
        || (rotation_degrees != 0 && rotation_degrees != 90 && rotation_degrees != 180 && rotation_degrees != 270)
        || nv12.size() != static_cast<size_t>(width) * height * 3 / 2)
        throw std::runtime_error("Invalid NV12 frame geometry, size or color specification");
    // NV12 stores interleaved UV: both views use pixel stride 2; V starts one byte after U.
    // Views borrow nv12, which must stay alive for the entire SDK call.
    // NV12 的 UV 交错存储，像素步长均为 2；V 比 U 晚一字节，底层数据须存活至调用结束。
    const size_t y_bytes = static_cast<size_t>(width) * height;
    HiFaceYuv420FrameV1 result{};
    result.struct_size = sizeof(result);
    result.width = width; result.height = height;
    result.rotation_degrees = rotation_degrees;
    result.range = range; result.matrix = matrix;
    result.y = {nv12.data(), y_bytes, width, 1};
    result.u = {nv12.data() + y_bytes, y_bytes / 2, width, 2};
    result.v = {nv12.data() + y_bytes + 1, y_bytes / 2 - 1, width, 2};
    return result;
}

std::vector<uint8_t> CameraFrame::previewBgra() const {
    const auto frame = view();
    std::vector<uint8_t> pixels(static_cast<size_t>(width) * height * 4);
    const bool video = range == HIFACE_YUV_RANGE_VIDEO;
    const bool bt709 = matrix == HIFACE_YUV_MATRIX_BT709;
    const int y_scale = video ? 298 : 256;
    const int rv = video ? (bt709 ? 459 : 409) : (bt709 ? 403 : 359);
    const int gu = video ? (bt709 ? 55 : 100) : (bt709 ? 48 : 88);
    const int gv = video ? (bt709 ? 136 : 208) : (bt709 ? 120 : 183);
    const int bu = video ? (bt709 ? 541 : 516) : (bt709 ? 475 : 454);
    auto channel = [](int value) { return static_cast<uint8_t>(std::clamp((value + 128) >> 8, 0, 255)); };
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const int luma = y_scale * (int(frame.y.data[y * width + x]) - (video ? 16 : 0));
            const int uv = (y / 2) * width + (x & ~1);
            const int u = int(frame.u.data[uv]) - 128;
            const int v = int(frame.u.data[uv + 1]) - 128;
            auto* out = pixels.data() + (static_cast<size_t>(y) * width + x) * 4;
            out[0] = channel(luma + bu * u);
            out[1] = channel(luma - gu * u - gv * v);
            out[2] = channel(luma + rv * v);
            out[3] = 255;
        }
    }
    return pixels;
}
}
