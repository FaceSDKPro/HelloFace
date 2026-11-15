#pragma once
#include "hiface/hiface_c_api.h"
#include <cstdint>
#include <memory>
#include <vector>

namespace hiface_linux_demo {
// One owned terminal RGB scene; no camera buffer, disk cache or frame history.
// 独占一份结束采样的 RGB 场景；不持有相机缓冲，不落盘或缓存历史。
struct SearchFrameImage {
    uint64_t frame_id = 0;
    uint32_t width = 0, height = 0;
    std::vector<uint8_t> jpeg;
};
inline int32_t HIFACE_CALL receiveSearchFrameImage(const uint8_t* jpeg, size_t size,
        uint32_t width, uint32_t height, uint64_t frame_id, void* context) {
    auto& output = *static_cast<SearchFrameImage*>(context);
    if (frame_id != output.frame_id) return 0;
    try { output.jpeg.assign(jpeg, jpeg + size); output.width = width; output.height = height; return 1; }
    catch (...) { output.jpeg.clear(); output.width = output.height = 0; return 0; }
}
inline std::shared_ptr<const SearchFrameImage> copySearchFrameImage(HiFaceSessionHandle session,
        HiFaceSearchBatchHandle batch, uint64_t frame_id) noexcept {
    try {
        auto output = std::make_shared<SearchFrameImage>(); output->frame_id = frame_id;
        if (hiface_session_search_copy_jpeg_v1(session, batch, receiveSearchFrameImage, output.get())
                == HIFACE_STATUS_OK && !output->jpeg.empty()) return output;
    } catch (...) { }
    return {};
}
}
