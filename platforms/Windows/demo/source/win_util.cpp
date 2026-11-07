#include "win_util.h"
#include <wincodec.h>
#include <wrl/client.h>
#include <shlobj.h>
#include <iomanip>
#include <chrono>
#include <fstream>
#include <sstream>
#include <mutex>
#include <stdexcept>
#include <vector>

namespace hiface_demo {
using Microsoft::WRL::ComPtr;
namespace {
std::mutex log_mutex;
std::ofstream log_output;
size_t log_bytes = 0;
}
std::filesystem::path demoDataDirectory() {
    const auto length = GetEnvironmentVariableW(L"HIFACE_DATA_DIR", nullptr, 0);
    if (length) {
        std::wstring value(length, L'\0');
        const auto copied = GetEnvironmentVariableW(L"HIFACE_DATA_DIR", value.data(), length);
        if (!copied || copied >= length) throw std::runtime_error("Cannot read HIFACE_DATA_DIR");
        value.resize(copied); const std::filesystem::path directory(value);
        if (!directory.is_absolute()) throw std::runtime_error("HIFACE_DATA_DIR must be an absolute directory");
        return directory;
    }
    PWSTR raw = nullptr;
    checkHr(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr, &raw), "Find application data directory");
    const std::filesystem::path directory(raw); CoTaskMemFree(raw);
    return directory / L"HiFaceDemo";
}
std::filesystem::path logDirectory() { return demoDataDirectory() / L"logs"; }
void HIFACE_CALL sdkLog(HiFaceLogLevel, const char* tag, const char* message, void*) {
    try { writeLog(std::string("[") + (tag ? tag : "SDK") + "] " + (message ? message : "")); } catch (...) {}
}
void initializeLog(const char* application) {
    hiface::setLogCallback(sdkLog);
    const auto directory = logDirectory();
    std::filesystem::create_directories(directory);
    SYSTEMTIME time{}; GetLocalTime(&time);
    std::ostringstream name;
    name << application << '-' << time.wYear << std::setfill('0') << std::setw(2) << time.wMonth
         << std::setw(2) << time.wDay << '-' << std::setw(2) << time.wHour << std::setw(2) << time.wMinute
         << std::setw(2) << time.wSecond << '-' << GetCurrentProcessId() << ".log";
    {
        std::lock_guard<std::mutex> lock(log_mutex);
        log_output.open(directory / name.str(), std::ios::binary | std::ios::app);
        if (!log_output) throw std::runtime_error("Cannot create Demo diagnostic log");
    }
    SYSTEM_INFO system{}; GetNativeSystemInfo(&system);
    writeLog(std::string(application) + " | Windows x64 CPU | logical processors="
        + std::to_string(system.dwNumberOfProcessors) + " | exe=" + executableDirectory().u8string());
}
void writeLog(const std::string& message) noexcept {
    try {
        std::lock_guard<std::mutex> lock(log_mutex);
        OutputDebugStringW((widen(message) + L"\n").c_str());
        // Bound each run's diagnostic output; never log pixels or feature bytes.
        // 限制每次运行的诊断输出，绝不记录像素或特征字节。
        if (log_output && log_bytes < 4 * 1024 * 1024) {
            SYSTEMTIME time{}; GetLocalTime(&time);
            log_output << std::setfill('0') << std::setw(2) << time.wHour << ':' << std::setw(2) << time.wMinute
                << ':' << std::setw(2) << time.wSecond << '.' << std::setw(3) << time.wMilliseconds
                << " " << message << '\n';
            log_output.flush(); log_bytes += message.size() + 15;
        }
    } catch (...) { /* Logging must not interrupt capture or cross a C callback. / 日志不能中断采集，异常不能越过 C 回调边界。 */ }
}
std::string readFeatureFile(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input) throw std::runtime_error("Cannot read HF1 file");
    const auto size = input.tellg();
    if (size <= 0 || size > HIFACE_FEATURE_TEXT_LENGTH + 16) throw std::runtime_error("Invalid HF1 file size");
    input.seekg(0);
    // Read only the observed, bounded size even if the file grows concurrently.
    // 仅读取已检查的长度；读取期间文件增长也不会形成无界分配。
    std::string text(static_cast<size_t>(size), '\0');
    if (!input.read(text.data(), static_cast<std::streamsize>(text.size())))
        throw std::runtime_error("Cannot read complete HF1 file");
    if (input.peek() != std::char_traits<char>::eof()) throw std::runtime_error("HF1 file changed while reading");
    if (text.compare(0, 3, "\xef\xbb\xbf") == 0) text.erase(0, 3);
    while (!text.empty() && (text.back() == '\r' || text.back() == '\n' || text.back() == ' ')) text.pop_back();
    decodeFeature(text);
    return text;
}
void writeFeatureFile(const std::filesystem::path& path, const std::string& text) {
    decodeFeature(text);
    auto temporary = path;
    temporary += L".tmp-" + std::to_wstring(GetCurrentProcessId())
        + L"-" + std::to_wstring(std::chrono::steady_clock::now().time_since_epoch().count());
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() { std::error_code ignored; std::filesystem::remove(path, ignored); }
    } cleanup{temporary};
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    output << text << '\n'; output.close();
    if (!output || !MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        throw std::runtime_error("Cannot save HF1 file");
}
void checkHr(HRESULT status, const char* operation) {
    if (SUCCEEDED(status)) return;
    std::ostringstream message;
    message << operation << ": HRESULT 0x" << std::hex << static_cast<unsigned long>(status);
    wchar_t* detail = nullptr;
    if (FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr, static_cast<DWORD>(status), 0, reinterpret_cast<LPWSTR>(&detail), 0, nullptr) && detail) {
        std::wstring text(detail); LocalFree(detail);
        while (!text.empty() && (text.back() == L'\r' || text.back() == L'\n')) text.pop_back();
        message << " | " << utf8(text);
    }
    throw std::runtime_error(message.str());
}
std::wstring widen(const std::string& text) {
    if (text.empty()) return {};
    const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
    if (!size) throw std::runtime_error("Invalid UTF-8 text");
    std::wstring result(size, 0);
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), result.data(), size);
    return result;
}
std::string utf8(const std::wstring& text) {
    if (text.empty()) return {};
    const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    if (!size) throw std::runtime_error("Invalid Unicode text");
    std::string result(size, 0);
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), result.data(), size, nullptr, nullptr);
    return result;
}
ComApartment::ComApartment(bool sta) { checkHr(CoInitializeEx(nullptr, sta ? COINIT_APARTMENTTHREADED : COINIT_MULTITHREADED), "Initialize COM"); }
ComApartment::~ComApartment() { CoUninitialize(); }
std::filesystem::path executableDirectory() {
    std::vector<wchar_t> buffer(32768);
    const auto length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (!length || length >= buffer.size()) throw std::runtime_error("Cannot resolve executable path");
    return std::filesystem::path(std::wstring(buffer.data(), length)).parent_path();
}
Image readImage(const std::filesystem::path& path, bool fit_to_sdk_limit) {
    ComPtr<IWICImagingFactory> factory;
    checkHr(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory)), "Create Windows image decoder");
    ComPtr<IWICBitmapDecoder> decoder;
    checkHr(factory->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ,
        WICDecodeMetadataCacheOnLoad, &decoder), "Open image");
    ComPtr<IWICBitmapFrameDecode> frame;
    checkHr(decoder->GetFrame(0, &frame), "Read image frame");
    UINT width = 0, height = 0;
    checkHr(frame->GetSize(&width, &height), "Read image dimensions");
    if (width < 2 || height < 2 || (!fit_to_sdk_limit && (width > HIFACE_MAX_IMAGE_DIMENSION || height > HIFACE_MAX_IMAGE_DIMENSION)))
        throw std::runtime_error("Image dimensions must be between 2 and 4096");

    // Apply JPEG/TIFF EXIF orientation before producing the public RGBA input.
    // 生成公开 RGBA 输入前先应用 JPEG/TIFF EXIF 方向。
    ComPtr<IWICBitmapSource> source = frame;
    ComPtr<IWICMetadataQueryReader> metadata;
    if (SUCCEEDED(frame->GetMetadataQueryReader(&metadata))) {
        PROPVARIANT value; PropVariantInit(&value);
        HRESULT found = metadata->GetMetadataByName(L"/app1/ifd/{ushort=274}", &value);
        if (FAILED(found)) { PropVariantClear(&value); PropVariantInit(&value);
            found = metadata->GetMetadataByName(L"/ifd/{ushort=274}", &value); }
        const unsigned orientation = SUCCEEDED(found) && value.vt == VT_UI2 ? value.uiVal : 1;
        PropVariantClear(&value);
        WICBitmapTransformOptions transform = WICBitmapTransformRotate0;
        switch (orientation) {
            case 2: transform = WICBitmapTransformFlipHorizontal; break;
            case 3: transform = WICBitmapTransformRotate180; break;
            case 4: transform = WICBitmapTransformFlipVertical; break;
            case 5: transform = static_cast<WICBitmapTransformOptions>(WICBitmapTransformRotate90 | WICBitmapTransformFlipHorizontal); break;
            case 6: transform = WICBitmapTransformRotate90; break;
            case 7: transform = static_cast<WICBitmapTransformOptions>(WICBitmapTransformRotate270 | WICBitmapTransformFlipHorizontal); break;
            case 8: transform = WICBitmapTransformRotate270; break;
        }
        if (transform != WICBitmapTransformRotate0) {
            ComPtr<IWICBitmapFlipRotator> rotator;
            checkHr(factory->CreateBitmapFlipRotator(&rotator), "Create orientation transform");
            checkHr(rotator->Initialize(frame.Get(), transform), "Orient image");
            source = rotator;
        }
    }
    checkHr(source->GetSize(&width, &height), "Read oriented dimensions");
    if (width > HIFACE_MAX_IMAGE_DIMENSION || height > HIFACE_MAX_IMAGE_DIMENSION) {
        // Image search preserves original face scale within 4096px, matching Android.
        // WIC scales only oversized inputs, then even-size cropping removes at most 1px.
        // 与 Android 一致，图片搜索在 4096px 内保留原始人脸尺度；WIC 仅缩放超限输入，偶数裁剪最多去掉 1px。
        const auto longest = std::max(width, height);
        const UINT scaled_width = static_cast<UINT>(uint64_t{width} * HIFACE_MAX_IMAGE_DIMENSION / longest);
        const UINT scaled_height = static_cast<UINT>(uint64_t{height} * HIFACE_MAX_IMAGE_DIMENSION / longest);
        if (scaled_width < 2 || scaled_height < 2) throw std::runtime_error("Scaled image is too narrow for face search");
        ComPtr<IWICBitmapScaler> scaler;
        checkHr(factory->CreateBitmapScaler(&scaler), "Create image search scaler");
        checkHr(scaler->Initialize(source.Get(), scaled_width, scaled_height, WICBitmapInterpolationModeFant), "Scale oversized image");
        source = scaler; width = scaled_width; height = scaled_height;
    }
    // Preserve face scale: discard at most the final row/column to satisfy the
    // existing even-size RGBA detection contract, rather than stretching pixels.
    // 保留人脸尺度；为满足现有 RGBA 偶数尺寸契约，最多丢弃末行或末列，不拉伸像素。
    width &= ~1u; height &= ~1u;
    Image image{static_cast<int>(width), static_cast<int>(height), std::vector<uint8_t>(size_t(width) * height * 4)};
    ComPtr<IWICFormatConverter> converter;
    checkHr(factory->CreateFormatConverter(&converter), "Create RGBA converter");
    checkHr(converter->Initialize(source.Get(), GUID_WICPixelFormat32bppRGBA, WICBitmapDitherTypeNone,
        nullptr, 0, WICBitmapPaletteTypeCustom), "Convert image to RGBA");
    const WICRect rect{0, 0, static_cast<INT>(width), static_cast<INT>(height)};
    checkHr(converter->CopyPixels(&rect, width * 4, static_cast<UINT>(image.rgba.size()), image.rgba.data()), "Read RGBA pixels");
    return image;
}
void writeImage(const std::filesystem::path& path, const Image& image) {
    if (image.width <= 0 || image.height <= 0 || image.rgba.size() != size_t(image.width) * image.height * 4)
        throw std::runtime_error("Invalid RGBA export image");
    ComPtr<IWICImagingFactory> factory;
    checkHr(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)), "Create PNG encoder");
    ComPtr<IWICStream> stream; checkHr(factory->CreateStream(&stream), "Create PNG stream");
    checkHr(stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE), "Open PNG output");
    ComPtr<IWICBitmapEncoder> encoder;
    checkHr(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder), "Create PNG container");
    checkHr(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache), "Initialize PNG output");
    ComPtr<IWICBitmapFrameEncode> frame;
    checkHr(encoder->CreateNewFrame(&frame, nullptr), "Create PNG frame");
    checkHr(frame->Initialize(nullptr), "Initialize PNG frame");
    checkHr(frame->SetSize(image.width, image.height), "Set PNG dimensions");
    auto format = GUID_WICPixelFormat32bppBGRA;
    checkHr(frame->SetPixelFormat(&format), "Set PNG pixels");
    auto pixels = image.rgba;
    if (format == GUID_WICPixelFormat32bppBGRA) {
        for (size_t i = 0; i < pixels.size(); i += 4) std::swap(pixels[i], pixels[i + 2]);
    } else if (format != GUID_WICPixelFormat32bppRGBA) throw std::runtime_error("PNG encoder does not accept 32-bit pixels");
    checkHr(frame->WritePixels(image.height, image.width * 4, static_cast<UINT>(pixels.size()), pixels.data()), "Encode PNG pixels");
    checkHr(frame->Commit(), "Commit PNG frame"); checkHr(encoder->Commit(), "Commit PNG file");
}
void testWindowsImageDecoder() {
    const auto directory = std::filesystem::temp_directory_path() / (L"HiFace WIC 测试 "
        + std::to_wstring(std::chrono::steady_clock::now().time_since_epoch().count()));
    std::filesystem::create_directories(directory);
    struct Cleanup { std::filesystem::path path;
        ~Cleanup() { std::error_code ignored; std::filesystem::remove_all(path, ignored); }
    } cleanup{directory};
    // An independent 3x3, bottom-up BGR24 BMP with padded rows. The decoded
    // top-left must be red, second row green; odd final row/column are cropped.
    // 独立的 3x3 自底向上 BGR24 BMP，含行填充；解码后左上角应为红色、第二行为绿色，奇数末行或末列被裁掉。
    std::vector<uint8_t> bitmap(54 + 12 * 3, 0);
    auto u32 = [&](size_t offset, uint32_t value) {
        for (int i = 0; i < 4; ++i) bitmap[offset + i] = static_cast<uint8_t>(value >> (8 * i));
    };
    bitmap[0] = 'B'; bitmap[1] = 'M'; u32(2, static_cast<uint32_t>(bitmap.size())); u32(10, 54);
    u32(14, 40); u32(18, 3); u32(22, 3); bitmap[26] = 1; bitmap[28] = 24; u32(34, 36);
    for (int row = 0; row < 3; ++row)
        for (int x = 0; x < 3; ++x) bitmap[54 + row * 12 + x * 3 + row] = 255;
    const auto path = directory / L"奇数尺寸.bmp";
    {
        std::ofstream output(path, std::ios::binary);
        if (!output.write(reinterpret_cast<const char*>(bitmap.data()), bitmap.size()))
            throw std::runtime_error("Cannot create image decoder fixture");
    }
    const auto image = readImage(path);
    if (image.width != 2 || image.height != 2 || image.rgba.size() != 16
        || image.rgba[0] != 255 || image.rgba[1] != 0 || image.rgba[2] != 0 || image.rgba[3] != 255
        || image.rgba[8] != 0 || image.rgba[9] != 255 || image.rgba[10] != 0)
        throw std::runtime_error("WIC orientation, padding or channel conversion regression");
    const auto png = directory / L"对齐图.png"; writeImage(png, image);
    const auto roundtrip = readImage(png);
    if (roundtrip.rgba != image.rgba) throw std::runtime_error("PNG export/decode changed RGBA pixels");
    const Image large{4112, 12, std::vector<uint8_t>(4112 * 12 * 4, 128)};
    const auto large_path = directory / L"超限图片.png"; writeImage(large_path, large);
    bool rejected = false; try { readImage(large_path); } catch (const std::runtime_error&) { rejected = true; }
    if (!rejected) throw std::runtime_error("Ordinary image input must retain its existing size limit");
    const auto scaled = readImage(large_path, true);
    if (scaled.width != 4096 || scaled.height != 10) throw std::runtime_error("Image search scaling must preserve aspect ratio then crop odd edges");
    const auto preserved = readImage(png, true);
    if (preserved.rgba != image.rgba) throw std::runtime_error("Image search must preserve in-limit image resolution and pixels");
}
}
