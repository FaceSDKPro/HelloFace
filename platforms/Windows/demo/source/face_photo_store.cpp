#include "face_photo_store.h"
#include "win_util.h"
#include <aclapi.h>
#include <sddl.h>
#include <algorithm>

namespace hiface_demo {
std::filesystem::path FacePhotoStore::databasePath(Library library) {
    return demoDataDirectory() / (library == Library::Search ? L"hiface-search.db" : L"captured-faces.db");
}
std::optional<FacePhotoStore::Library> FacePhotoStore::libraryForDatabase(const std::filesystem::path& database) {
    for (auto library : {Library::Search, Library::Reference}) {
        std::error_code error;
        if (std::filesystem::equivalent(database, databasePath(library), error)) return library;
    }
    return std::nullopt;
}
namespace {
void checkDirectory(const std::filesystem::path& path) {
    const auto flags = GetFileAttributesW(path.c_str());
    if (flags == INVALID_FILE_ATTRIBUTES || !(flags & FILE_ATTRIBUTE_DIRECTORY) || (flags & FILE_ATTRIBUTE_REPARSE_POINT))
        throw std::runtime_error("Unavailable or unsafe photo directory");
}
// Own the protected DACL granting crop-directory access to the current user and SYSTEM.
struct Security {
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    SECURITY_ATTRIBUTES attributes{sizeof(SECURITY_ATTRIBUTES), nullptr, FALSE};
    Security() {
        HANDLE token = nullptr;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) throw std::runtime_error("Cannot read photo owner");
        const std::unique_ptr<void, decltype(&CloseHandle)> token_owner(token, CloseHandle);
        DWORD size = 0; GetTokenInformation(token, TokenUser, nullptr, 0, &size);
        std::vector<uint8_t> bytes(size);
        const bool ok = GetTokenInformation(token, TokenUser, bytes.data(), size, &size) != 0;
        if (!ok) throw std::runtime_error("Cannot read photo owner");
        LPWSTR sid = nullptr;
        if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid, &sid)) throw std::runtime_error("Cannot read photo SID");
        const std::unique_ptr<wchar_t, decltype(&LocalFree)> sid_owner(sid, LocalFree);
        const auto dacl = std::wstring(L"D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;") + sid + L")";
        if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(dacl.c_str(), SDDL_REVISION_1, &descriptor, nullptr))
            throw std::runtime_error("Cannot protect face photos");
        attributes.lpSecurityDescriptor = descriptor;
    }
    ~Security() { if (descriptor) LocalFree(descriptor); }
    void directory(const std::filesystem::path& path) {
        if (!CreateDirectoryW(path.c_str(), &attributes) && GetLastError() != ERROR_ALREADY_EXISTS)
            throw std::runtime_error("Cannot create private photo directory");
        checkDirectory(path);
        BOOL present = FALSE, defaulted = FALSE; PACL dacl = nullptr;
        if (!GetSecurityDescriptorDacl(descriptor, &present, &dacl, &defaulted) || !present ||
            SetNamedSecurityInfoW(const_cast<wchar_t*>(path.c_str()), SE_FILE_OBJECT,
                DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, nullptr, nullptr, dacl, nullptr) != ERROR_SUCCESS)
            throw std::runtime_error("Cannot restrict photo directory");
    }
};
std::filesystem::path file(const std::string& id, FacePhotoStore::Library library, Security* security = nullptr) {
    if (id.empty() || id.find('\0') != std::string::npos) throw std::runtime_error("Invalid Face ID");
    // Extended paths support long SDK IDs; components stay below filesystem name limits.
    auto root = demoDataDirectory().lexically_normal();
    const auto name = root.make_preferred().wstring();
    if (name.compare(0, 4, L"\\\\?\\") != 0)
        root = name.compare(0, 2, L"\\\\") == 0 ? L"\\\\?\\UNC\\" + name.substr(2) : L"\\\\?\\" + name;
    if (security && !GetEnvironmentVariableW(L"HIFACE_DATA_DIR", nullptr, 0)) security->directory(root);
    else {
        if (security) std::filesystem::create_directories(root);
        checkDirectory(root);
    }
    auto descend = [&](const std::filesystem::path& component) {
        root /= component;
        if (security) security->directory(root);
        else checkDirectory(root);
    };
    descend(L"face-photos-v1");
    descend(library == FacePhotoStore::Library::Reference ? L"reference" : L"search");
    std::string key = id;
    if (!std::all_of(id.begin(), id.end(), [](unsigned char c) { return c >= '0' && c <= '9'; })) {
        const char* hex = "0123456789abcdef"; key = "~";
        for (unsigned char c : id) { key += hex[c >> 4]; key += hex[c & 15]; }
    }
    while (key.size() > 120) { descend(widen(key.substr(0, 120))); key.erase(0, 120); }
    return root / widen(key + ".png");
}
}
bool FacePhotoStore::save(const std::string& id, const Image* image, Library library) noexcept {
    std::filesystem::path temporary;
    try {
        Security security;
        const auto target = file(id, library, &security);
        if (!image || image->width < 1 || image->height < 1 || image->width > 720 || image->height > 720)
            throw std::runtime_error("No confirmed crop");
        GUID guid{}; checkHr(CoCreateGuid(&guid), "Create photo transaction");
        wchar_t unique[40]{}; StringFromGUID2(guid, unique, 40);
        temporary = target.parent_path() / (std::wstring(unique) + L".tmp");
        HANDLE handle = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, &security.attributes, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (handle == INVALID_HANDLE_VALUE) throw std::runtime_error("Cannot stage private photo");
        CloseHandle(handle);
        writeImage(temporary, *image);
        if (!MoveFileExW(temporary.c_str(), target.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
            throw std::runtime_error("Cannot replace private photo");
        return true;
    } catch (...) {
        if (!temporary.empty()) DeleteFileW(temporary.c_str());
        remove(id, library); return false;
    }
}
std::shared_ptr<const Image> FacePhotoStore::load(const std::string& id, Library library) noexcept {
    try {
        const auto path = file(id, library);
        const auto flags = GetFileAttributesW(path.c_str());
        if (flags == INVALID_FILE_ATTRIBUTES || flags & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)
                || std::filesystem::file_size(path) > 1024 * 1024) return {};
        const auto source = readImage(path);
        if (source.width > 720 || source.height > 720) return {};
        auto thumbnail = std::make_shared<Image>(); thumbnail->width = thumbnail->height = 48;
        thumbnail->rgba.resize(48 * 48 * 4);
        for (int y = 0; y < 48; ++y) for (int x = 0; x < 48; ++x) {
            const auto offset = (static_cast<size_t>(y * source.height / 48) * source.width + x * source.width / 48) * 4;
            std::copy_n(source.rgba.data() + offset, 4, thumbnail->rgba.data() + (y * 48 + x) * 4);
        }
        return thumbnail;
    } catch (...) { return {}; }
}
void FacePhotoStore::remove(const std::string& id, Library library) noexcept {
    try { DeleteFileW(file(id, library).c_str()); } catch (...) {}
}
}
