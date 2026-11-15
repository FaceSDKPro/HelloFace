#pragma once
#include "image_decode.h"
#include "file_io.h"
#include <algorithm>
#include <memory>
#include <sys/stat.h>

namespace hiface_linux_demo {
// Demo-only owner-private crop store. PPM reuses the existing image format without another codec.
// Mode 0700/0600 isolates users; ordinary processes running under the same UID remain able to read.
class FacePhotoStore {
public:
    explicit FacePhotoStore(std::filesystem::path directory) : root_(std::move(directory) / "face-photos-v1") {}
    bool save(const std::string& id, const Image* image) const noexcept {
        try {
            const auto target = file(id, true);
            if (!image || image->width != 333 || image->height != 333 || image->rgba.size() != 333 * 333 * 4)
                throw std::runtime_error("No aligned crop");
            std::string bytes = "P6\n333 333\n255\n";
            bytes.reserve(bytes.size() + 333 * 333 * 3);
            for (size_t i = 0; i < image->rgba.size(); i += 4)
                bytes.append(reinterpret_cast<const char*>(image->rgba.data() + i), 3);
            atomicWrite(target.string(), bytes);
            return true;
        } catch (...) { remove(id); return false; }
    }
    std::shared_ptr<const Image> load(const std::string& id) const noexcept {
        try {
            const auto target = file(id, false);
            struct Descriptor {
                int value;
                ~Descriptor() { if (value >= 0) ::close(value); }
            } descriptor{::open(target.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC)};
            if (descriptor.value < 0) return {};
            struct stat info{};
            const std::string header = "P6\n333 333\n255\n";
            const size_t length = header.size() + 333 * 333 * 3;
            if (::fstat(descriptor.value, &info) || !S_ISREG(info.st_mode) || info.st_uid != ::geteuid()
                    || (info.st_mode & 077) || info.st_size != static_cast<off_t>(length)) return {};
            std::string bytes(length, '\0'); size_t offset = 0;
            while (offset < length) {
                const auto count = ::read(descriptor.value, bytes.data() + offset, length - offset);
                if (count < 0 && errno == EINTR) continue;
                if (count <= 0) throw std::runtime_error("Cannot read photo");
                offset += static_cast<size_t>(count);
            }
            if (bytes.compare(0, header.size(), header)) return {};
            auto image = std::make_shared<Image>(); image->width = image->height = 48;
            image->rgba.resize(48 * 48 * 4);
            for (int y = 0; y < 48; ++y) for (int x = 0; x < 48; ++x) {
                const size_t source = header.size() + (y * 333 / 48 * 333 + x * 333 / 48) * 3;
                const size_t output = (y * 48 + x) * 4;
                std::copy_n(reinterpret_cast<const uint8_t*>(bytes.data()) + source, 3, image->rgba.data() + output);
                image->rgba[output + 3] = 255;
            }
            return image;
        } catch (...) { return {}; }
    }
    void remove(const std::string& id) const noexcept {
        try { ::unlink(file(id, false).c_str()); } catch (...) {}
    }
private:
    std::filesystem::path root_;
    static void directory(const std::filesystem::path& path, bool create) {
        if (create && ::mkdir(path.c_str(), 0700) < 0 && errno != EEXIST)
            throw std::runtime_error("Cannot create private photo directory");
        struct stat info{};
        if (::lstat(path.c_str(), &info) || !S_ISDIR(info.st_mode) || info.st_uid != ::geteuid())
            throw std::runtime_error("Unsafe photo directory");
        if (create && ::chmod(path.c_str(), 0700)) throw std::runtime_error("Cannot restrict photo directory");
        if (!create && (info.st_mode & 077)) throw std::runtime_error("Photo directory is not private");
    }
    std::filesystem::path file(const std::string& id, bool create) const {
        if (id.empty() || id.find('\0') != std::string::npos) throw std::runtime_error("Invalid Face ID");
        std::string key = id;
        if (!std::all_of(id.begin(), id.end(), [](unsigned char c) { return c >= '0' && c <= '9'; })) {
            const char* hex = "0123456789abcdef"; key = "~";
            for (unsigned char c : id) { key += hex[c >> 4]; key += hex[c & 15]; }
        }
        auto path = root_; directory(path, create);
        while (key.size() > 120) { path /= key.substr(0, 120); key.erase(0, 120); directory(path, create); }
        return path / (key + ".ppm");
    }
};
}
