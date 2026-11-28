#pragma once
#include "sdk_helpers.h"
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fcntl.h>
#include <string>
#include <system_error>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>
#if defined(__linux__)
#include <sys/syscall.h>
#endif
namespace hiface_linux_demo {
inline constexpr size_t maxInputFileBytes = 64u * 1024 * 1024;

// Open before inspecting the type so even a named pipe with no writer returns promptly.
inline std::string readInputFile(const char* path, const std::string& kind) {
    require(path && *path, "Missing " + kind + " path");
    struct File {
        int fd;
        ~File() { if (fd >= 0) ::close(fd); }
    } file{::open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)};
    require(file.fd >= 0, "Cannot open " + kind);
    struct stat info{};
    require(::fstat(file.fd, &info) == 0 && S_ISREG(info.st_mode), "Expected a regular file for " + kind);
    require(info.st_size > 0 && uint64_t(info.st_size) <= maxInputFileBytes,
            "Expected 1 byte to 64 MiB for " + kind);
    std::string bytes(static_cast<size_t>(info.st_size), '\0');
    size_t offset = 0;
    while (offset < bytes.size()) {
        const auto n = ::read(file.fd, bytes.data() + offset, bytes.size() - offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) throw DemoError{"Cannot read complete " + kind};
        offset += static_cast<size_t>(n);
    }
    char extra;
    ssize_t n;
    do { n = ::read(file.fd, &extra, 1); } while (n < 0 && errno == EINTR);
    require(n == 0, "File changed or could not be read: " + kind);
    return bytes;
}

inline void atomicWrite(const std::string& path, const std::string& contents, bool replace = true) {
    if (path.find('\0') != std::string::npos)
        throw std::filesystem::filesystem_error("Invalid file path", std::make_error_code(std::errc::invalid_argument));
    std::string pattern = path + ".tmp-XXXXXX";
    std::vector<char> name(pattern.begin(), pattern.end()); name.push_back('\0');
    int descriptor = ::mkstemp(name.data()); // Exclusive creation with mode 0600, independent of the launcher.
    auto fail = [&] {
        throw std::filesystem::filesystem_error("Cannot write file", path,
            std::error_code(errno ? errno : EIO, std::generic_category()));
    };
    if (descriptor < 0) fail();
    const std::string temporary(name.data());
    try {
        if (::fcntl(descriptor, F_SETFD, FD_CLOEXEC) < 0) fail();
        size_t offset = 0;
        while (offset < contents.size()) {
            const auto written = ::write(descriptor, contents.data() + offset, contents.size() - offset);
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) { if (!written) errno = EIO; fail(); }
            offset += static_cast<size_t>(written);
        }
        if (::fsync(descriptor) < 0) fail();
        const int closed = ::close(descriptor); descriptor = -1;
        if (closed < 0) fail();
        bool published = false;
#if defined(__linux__) && defined(SYS_renameat2)
        // Linux no-replace rename also supports removable filesystems without
        // hard links. Older kernels use the safe same-directory link fallback.
        if (!replace) {
            published = ::syscall(SYS_renameat2, AT_FDCWD, temporary.c_str(), AT_FDCWD, path.c_str(), 1 /* RENAME_NOREPLACE */) == 0;
            if (!published && errno != ENOSYS && errno != EINVAL) fail();
        }
#endif
        if (!published && (replace ? ::rename(temporary.c_str(), path.c_str()) < 0
                                   : ::link(temporary.c_str(), path.c_str()) < 0)) fail();
    } catch (...) {
        if (descriptor >= 0) ::close(descriptor);
        std::error_code ignored; std::filesystem::remove(temporary, ignored); throw;
    }
    std::error_code ignored; std::filesystem::remove(temporary, ignored);
}
}
