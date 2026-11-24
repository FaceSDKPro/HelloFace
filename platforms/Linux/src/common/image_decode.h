#pragma once
#include "sdk_helpers.h"
namespace hiface_linux_demo {
enum class PhotoMode { Capture, Search };
Image decodePhotoBytes(const uint8_t* data, size_t size, PhotoMode mode);
Image readImage(const char* path);
// Image-search picker: apply JPEG EXIF orientation, shrink to 4096, then crop odd edges.
// 图片搜索选择器：应用 JPEG EXIF 方向，超限时缩至 4096，再裁掉奇数末边。
Image readSearchImage(const char* path);
void savePreview(const std::string& path, const std::vector<uint8_t>& rgba);
Image decodeJpeg(const uint8_t* data, size_t size);
}
