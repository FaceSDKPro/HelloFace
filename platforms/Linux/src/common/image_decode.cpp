#include "image_decode.h"
#include "file_io.h"
#include <cstring>
#include <memory>
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <string_view>
#include <cmath>

namespace {
// Bound individual decoder allocations too, including inflated PNG data.
constexpr size_t kMaxDecoderAllocation = 320u * 1024 * 1024;
void* boundedImageRealloc(void* ptr, size_t size) {
    return size <= kMaxDecoderAllocation ? std::realloc(ptr, size) : nullptr;
}
}
#define STBI_MALLOC(size) boundedImageRealloc(nullptr, size)
#define STBI_REALLOC(ptr, size) boundedImageRealloc(ptr, size)
#define STBI_FREE(ptr) std::free(ptr)
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_ONLY_BMP
#define STBI_NO_STDIO
#define STBI_MAX_DIMENSIONS 16384
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

namespace hiface_linux_demo {
namespace {
constexpr uint64_t kMaxPhotoPixels = 64u * 1024 * 1024;
constexpr int kMaxCaptureSide = HIFACE_MAX_IMAGE_DIMENSION;

std::string_view ppmToken(std::string_view& input) {
    while (!input.empty()) {
        if (std::isspace(static_cast<unsigned char>(input.front()))) input.remove_prefix(1);
        else if (input.front() == '#') {
            const size_t newline = input.find('\n');
            input.remove_prefix(newline == input.npos ? input.size() : newline + 1);
        } else break;
    }
    size_t size = 0;
    while (size < input.size() && !std::isspace(static_cast<unsigned char>(input[size]))
            && input[size] != '#') {
        require(size < 32, "PPM header token too long");
        ++size;
    }
    require(size > 0, "Truncated PPM header");
    const auto token = input.substr(0, size);
    input.remove_prefix(size);
    return token;
}

Image decodePpm(std::string_view input) {
    require(ppmToken(input) == "P6", "Expected binary P6 PPM image");
    const auto dimension = [&] {
        int value = 0;
        for (char c : ppmToken(input)) {
            require(c >= '0' && c <= '9', "Invalid PPM dimension");
            value = value * 10 + c - '0';
            require(value <= kMaxCaptureSide, "PPM dimensions must be at most 4096 pixels");
        }
        require(value >= 2, "PPM dimensions must be at least 2 pixels");
        return value;
    };
    const int width = dimension(), height = dimension();
    require(ppmToken(input) == "255", "Expected 8-bit PPM channels (maxval 255)");
    require(!input.empty() && std::isspace(static_cast<unsigned char>(input.front())),
            "Missing PPM separator");
    input.remove_prefix(input.substr(0, 2) == "\r\n" ? 2 : 1);
    require(input.size() >= size_t(width) * height * 3, "Truncated PPM pixels");
    Image image{width & ~1, height & ~1, {}};
    image.rgba.resize(size_t(image.width) * image.height * 4);
    for (int y = 0; y < image.height; ++y) for (int x = 0; x < image.width; ++x) {
        const auto src = (size_t(y) * width + x) * 3;
        const auto dst = (size_t(y) * image.width + x) * 4;
        std::memcpy(image.rgba.data() + dst, input.data() + src, 3);
        image.rgba[dst + 3] = 255;
    }
    return image;
}

using Pixels = std::unique_ptr<stbi_uc, decltype(&stbi_image_free)>;

Pixels decodeRaster(const uint8_t* data, size_t size, int max_side, int& width, int& height) {
    int channels = 0;
    require(stbi_info_from_memory(data, static_cast<int>(size), &width, &height, &channels) &&
            width >= 2 && height >= 2 && width <= max_side && height <= max_side &&
            uint64_t(width) * height <= kMaxPhotoPixels, "Invalid photo header or dimensions");
    int decoded_width = 0, decoded_height = 0;
    Pixels pixels(stbi_load_from_memory(data, static_cast<int>(size), &decoded_width,
            &decoded_height, &channels, 4), stbi_image_free);
    require(pixels && decoded_width == width && decoded_height == height, "Cannot decode complete photo");
    return pixels;
}

Image cropEven(const uint8_t* pixels, int width, int height) {
    Image image{width & ~1, height & ~1, {}};
    const size_t row_bytes = size_t(image.width) * 4;
    image.rgba.resize(row_bytes * image.height);
    for (int y = 0; y < image.height; ++y) {
        std::memcpy(image.rgba.data() + size_t(y) * row_bytes, pixels + size_t(y) * width * 4, row_bytes);
    }
    return image;
}
}

void savePreview(const std::string& path, const std::vector<uint8_t>& rgba) {
    require(rgba.size() == HIFACE_ALIGNED_PREVIEW_RGBA_BYTES, "Invalid aligned preview");
    const auto side = std::to_string(HIFACE_ALIGNED_PREVIEW_SIDE);
    std::string ppm = "P6\n" + side + " " + side + "\n255\n";
    ppm.reserve(ppm.size() + rgba.size() / 4 * 3);
    for (size_t i = 0; i < rgba.size(); i += 4) {
        ppm.append(reinterpret_cast<const char*>(rgba.data() + i), 3);
    }
    try { atomicWrite(path, ppm); }
    catch (const std::filesystem::filesystem_error&) { require(false, "Cannot save captured preview"); }
}

Image decodeJpeg(const uint8_t* data, size_t size) {
    require(data && size > 0 && size <= 32u * 1024 * 1024, "Invalid camera JPEG size");
    int width = 0, height = 0;
    const auto pixels = decodeRaster(data, size, kMaxCaptureSide, width, height);
    return cropEven(pixels.get(), width, height);
}

namespace {
int jpegOrientation(std::string_view image) {
    if (image.size() < 2 || uint8_t(image[0]) != 0xff || uint8_t(image[1]) != 0xd8) return 1;
    size_t cursor = 2;
    for (int segment = 0; segment < 128 && cursor < image.size(); ++segment) {
        if (uint8_t(image[cursor++]) != 0xff) break;
        while (cursor < image.size() && uint8_t(image[cursor]) == 0xff) ++cursor;
        if (cursor == image.size()) break;
        const auto marker = uint8_t(image[cursor++]);
        if (marker == 0xda || marker == 0xd9 || marker == 0) break;
        if (marker == 1 || (marker >= 0xd0 && marker <= 0xd7)) continue;
        if (image.size() - cursor < 2) break;
        const size_t length = (size_t(uint8_t(image[cursor])) << 8) | uint8_t(image[cursor + 1]);
        if (length < 2 || length > image.size() - cursor) break;
        const auto data = image.substr(cursor + 2, length - 2);
        cursor += length;
        if (marker != 0xe1 || data.size() < 14 || data.substr(0, 6) != std::string_view("Exif\0\0", 6)) continue;
        const bool little = data[6] == 'I' && data[7] == 'I';
        const bool big = data[6] == 'M' && data[7] == 'M';
        if (!little && !big) continue;
        const auto u16 = [&](size_t at) -> uint32_t {
            const auto a = uint32_t(uint8_t(data[at])), b = uint32_t(uint8_t(data[at + 1]));
            return little ? a | (b << 8) : (a << 8) | b;
        };
        const auto u32 = [&](size_t at) -> uint32_t {
            return little ? u16(at) | (u16(at + 2) << 16) : (u16(at) << 16) | u16(at + 2);
        };
        if (u16(8) != 42) continue;
        const uint64_t start = uint64_t(u32(10)) + 6;
        if (start > data.size() - 2) continue;
        const size_t count = std::min<size_t>(u16(start), (data.size() - start - 2) / 12);
        for (size_t i = 0; i < count; ++i) {
            const size_t at = start + 2 + i * 12;
            if (u16(at) == 0x112 && u16(at + 2) == 3 && u32(at + 4) == 1) {
                const auto value = u16(at + 8);
                return value >= 1 && value <= 8 ? int(value) : 1;
            }
        }
    }
    return 1;
}
}

Image decodePhotoBytes(const uint8_t* data, size_t size, PhotoMode mode) {
    require(data && size >= 2 && size <= maxInputFileBytes, "Invalid photo byte count");
    const std::string_view bytes(reinterpret_cast<const char*>(data), size);
    if (bytes.substr(0, 2) == "P6") return decodePpm(bytes);
    if (data[0] == 0xff && data[1] == 0xd8) {
        // stb accepts some truncated JPEGs. Require the end marker for still photos.
        const auto last = bytes.find_last_not_of('\0');
        require(last >= 3 && uint8_t(bytes[last - 1]) == 0xff && uint8_t(bytes[last]) == 0xd9,
                "Incomplete JPEG photo");
    }
    int sw = 0, sh = 0;
    const bool search = mode == PhotoMode::Search;
    const auto pixels = decodeRaster(data, size, search ? STBI_MAX_DIMENSIONS : kMaxCaptureSide, sw, sh);
    const int orientation = jpegOrientation(bytes), ow = orientation >= 5 ? sh : sw, oh = orientation >= 5 ? sw : sh;
    if (orientation == 1 && std::max(sw, sh) <= kMaxCaptureSide) return cropEven(pixels.get(), sw, sh);
    const double scale = std::min(1.0, double(HIFACE_MAX_IMAGE_DIMENSION) / std::max(ow, oh));
    const int scaled_width = int(std::floor(ow * scale)), scaled_height = int(std::floor(oh * scale));
    const int width = scaled_width & ~1, height = scaled_height & ~1;
    require(width >= 2 && height >= 2, "Photo is too small after resizing");
    Image image{width, height, std::vector<uint8_t>(size_t(width) * height * 4)};
    auto orientedPixel = [&](int x, int y) {
        int sx = x, sy = y;
        switch (orientation) {
            case 2: sx = sw-1-x; break; case 3: sx = sw-1-x; sy = sh-1-y; break; case 4: sy = sh-1-y; break;
            case 5: sx = y; sy = x; break; case 6: sx = y; sy = sh-1-x; break;
            case 7: sx = sw-1-y; sy = sh-1-x; break; case 8: sx = sw-1-y; sy = x; break;
        }
        return pixels.get() + (size_t(sy) * sw + sx) * 4;
    };
    for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
        auto* dst = image.rgba.data() + (size_t(y) * width + x) * 4;
        if (scale == 1) { std::memcpy(dst, orientedPixel(x, y), 4); continue; }
        const double fx = std::clamp((x + .5) * ow / scaled_width - .5, 0.0, double(ow-1));
        const double fy = std::clamp((y + .5) * oh / scaled_height - .5, 0.0, double(oh-1));
        const int x0 = int(fx), y0 = int(fy), x1 = std::min(x0+1, ow-1), y1 = std::min(y0+1, oh-1);
        const double dx = fx-x0, dy = fy-y0;
        const auto* top_left = orientedPixel(x0, y0);
        const auto* top_right = orientedPixel(x1, y0);
        const auto* bottom_left = orientedPixel(x0, y1);
        const auto* bottom_right = orientedPixel(x1, y1);
        for (int c = 0; c < 4; ++c) {
            const double top = (1 - dx) * top_left[c] + dx * top_right[c];
            const double bottom = (1 - dx) * bottom_left[c] + dx * bottom_right[c];
            dst[c] = uint8_t(std::lround((1 - dy) * top + dy * bottom));
        }
    }
    return image;
}

Image readImage(const char* path) {
    const auto bytes = readInputFile(path, "photo");
    return decodePhotoBytes(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), PhotoMode::Capture);
}

Image readSearchImage(const char* path) {
    const auto bytes = readInputFile(path, "photo");
    return decodePhotoBytes(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), PhotoMode::Search);
}

}
