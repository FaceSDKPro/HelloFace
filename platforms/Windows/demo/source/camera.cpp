#include "camera.h"
#include "win_util.h"
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <wrl/client.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <condition_variable>
#include <cstring>
#include <memory>
#include <mutex>
#include <utility>


namespace hiface_demo {
using Microsoft::WRL::ComPtr;
namespace {
struct Foundation {
    Foundation() { checkHr(MFStartup(MF_VERSION), "Start Media Foundation"); }
    ~Foundation() { MFShutdown(); }
};
struct CaptureState {
    std::mutex mutex;
    std::condition_variable changed;
    bool running = false;
    HRESULT failure = S_OK;
    ComPtr<IMFMediaType> pending_format;
    ComPtr<IMFSample> latest;
    std::chrono::steady_clock::time_point captured_at;
    ComPtr<IMFSourceReader> reader;
    uint64_t captured = 0;
};
class ReaderCallback final : public IMFSourceReaderCallback {
public:
    explicit ReaderCallback(std::shared_ptr<CaptureState> state) : state_(std::move(state)) {}
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (iid != IID_IUnknown && iid != __uuidof(IMFSourceReaderCallback)) return E_NOINTERFACE;
        *object = static_cast<IMFSourceReaderCallback*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG count = --references_; if (!count) delete this; return count;
    }
    STDMETHODIMP OnReadSample(HRESULT status, DWORD, DWORD flags, LONGLONG, IMFSample* sample) override {
        ComPtr<IMFSourceReader> reader;
        {
            std::unique_lock<std::mutex> lock(state_->mutex);
            if (!state_->running) return S_OK;
            reader = state_->reader;
            if (SUCCEEDED(status) && (flags & (MF_SOURCE_READERF_ERROR | MF_SOURCE_READERF_ENDOFSTREAM)))
                status = MF_E_INVALIDMEDIATYPE;
            if (SUCCEEDED(status) && (flags & (MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED
                                              | MF_SOURCE_READERF_NATIVEMEDIATYPECHANGED))) {
                // Fetch this format before requesting another sample. A change can arrive without a sample.
                state_->latest.Reset();
                lock.unlock();
                ComPtr<IMFMediaType> format;
                status = reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &format);
                lock.lock();
                if (!state_->running) return S_OK;
                state_->pending_format = std::move(format);
            }
            if (FAILED(status)) {
                state_->failure = status;
                state_->running = false; state_->changed.notify_all(); return S_OK;
            }
            if (sample) {
                state_->latest = sample; state_->captured_at = std::chrono::steady_clock::now();
                ++state_->captured;
                state_->changed.notify_one();
            } // keep only latest / 仅保留最新帧。
        }
        const auto next = reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0,
            nullptr, nullptr, nullptr, nullptr);
        if (FAILED(next)) {
            std::lock_guard<std::mutex> lock(state_->mutex);
            if (state_->running) { state_->failure = next; state_->running = false; state_->changed.notify_all(); }
        }
        return S_OK;
    }
    STDMETHODIMP OnFlush(DWORD) override { return S_OK; }
    STDMETHODIMP OnEvent(DWORD, IMFMediaEvent*) override { return S_OK; }
private:
    std::atomic<ULONG> references_{1};
    std::shared_ptr<CaptureState> state_;
};
struct Devices {
    IMFActivate** values = nullptr;
    UINT32 count = 0;
    void enumerate() {
        ComPtr<IMFAttributes> attributes;
        checkHr(MFCreateAttributes(&attributes, 1), "Create camera attributes");
        checkHr(attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
            MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID), "Select video capture");
        checkHr(MFEnumDeviceSources(attributes.Get(), &values, &count), "Enumerate cameras");
    }
    ~Devices() {
        for (UINT32 i = 0; i < count; ++i) values[i]->Release();
        CoTaskMemFree(values);
    }
};
bool supportedDimensions(UINT32 width, UINT32 height) {
    return width && height && !(width & 1) && !(height & 1)
        && std::max(width, height) <= HIFACE_MAX_CAMERA_FRAME_LONG_SIDE
        && std::min(width, height) <= HIFACE_MAX_CAMERA_FRAME_SHORT_SIDE;
}
HRESULT readDeviceAttribute(IMFActivate* device, REFGUID key, std::wstring& text) {
    wchar_t* raw = nullptr;
    UINT32 length = 0;
    const auto result = device->GetAllocatedString(key, &raw, &length);
    const std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> owner(raw, CoTaskMemFree);
    if (SUCCEEDED(result)) text.assign(owner.get(), length);
    return result;
}
}
struct Camera::Impl {
    Foundation foundation;
    std::shared_ptr<CaptureState> state = std::make_shared<CaptureState>();
    ComPtr<IMFMediaSource> source;
    int width = 0, height = 0;
    LONG pitch = 0;
    HiFaceYuvRangeV1 range = HIFACE_YUV_RANGE_VIDEO;
    HiFaceYuvMatrixV1 matrix = HIFACE_YUV_MATRIX_BT601;
    void readFormat(IMFMediaType* output, IMFMediaType* fallback = nullptr) {
        UINT32 new_width = 0, new_height = 0; GUID subtype{};
        checkHr(output->GetGUID(MF_MT_SUBTYPE, &subtype), "Read negotiated pixel format");
        checkHr(MFGetAttributeSize(output, MF_MT_FRAME_SIZE, &new_width, &new_height), "Read negotiated dimensions");
        if (subtype != MFVideoFormat_NV12 || !supportedDimensions(new_width, new_height))
            throw std::runtime_error("Camera changed to an unsupported pixel format or size");
        width = static_cast<int>(new_width); height = static_cast<int>(new_height);
        UINT32 new_pitch = new_width;
        output->GetUINT32(MF_MT_DEFAULT_STRIDE, &new_pitch); pitch = static_cast<LONG>(new_pitch);
        auto colorAttribute = [&](REFGUID key) {
            UINT32 value = 0;
            if ((FAILED(output->GetUINT32(key, &value)) || !value) && fallback)
                fallback->GetUINT32(key, &value);
            return value;
        };
        matrix = HIFACE_YUV_MATRIX_BT601;
        const auto new_matrix = colorAttribute(MF_MT_YUV_MATRIX);
        if (new_matrix == MFVideoTransferMatrix_BT709) matrix = HIFACE_YUV_MATRIX_BT709;
        else if (new_matrix != MFVideoTransferMatrix_BT601 && new_matrix != MFVideoTransferMatrix_Unknown)
            throw std::runtime_error("Unsupported camera YUV matrix");
        range = HIFACE_YUV_RANGE_VIDEO;
        const auto new_range = colorAttribute(MF_MT_VIDEO_NOMINAL_RANGE);
        if (new_range == MFNominalRange_0_255) range = HIFACE_YUV_RANGE_FULL;
        else if (new_range != MFNominalRange_16_235 && new_range != MFNominalRange_Unknown)
            throw std::runtime_error("Unsupported camera YUV range");
    }
    ~Impl() {
        ComPtr<IMFSourceReader> reader;
        {
            std::lock_guard<std::mutex> lock(state->mutex);
            state->running = false; state->latest.Reset();
            reader = std::move(state->reader); // break callback/reader ownership cycle / 打破回调与读取器之间的循环持有。
            state->changed.notify_all();
        }
        if (reader) reader->Flush(MF_SOURCE_READER_ALL_STREAMS);
        if (source) source->Shutdown();
        reader.Reset(); source.Reset();
    }
};
std::vector<CameraDevice> Camera::devices() {
    Foundation foundation;
    Devices devices;
    devices.enumerate();
    std::vector<CameraDevice> result;
    result.reserve(devices.count);
    for (UINT32 i = 0; i < devices.count; ++i) {
        auto* activation = devices.values[i];
        CameraDevice device;
        checkHr(readDeviceAttribute(activation, MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, device.name), "Read camera name");
        checkHr(readDeviceAttribute(activation, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
            device.symbolic_link), "Read camera device ID");
        result.push_back(std::move(device));
    }
    return result;
}
Camera::Camera(unsigned device_index, const std::wstring& symbolic_link, unsigned preferred_width, unsigned preferred_height,
    unsigned preferred_fps) : impl_(std::make_unique<Impl>()) {
    Devices devices;
    devices.enumerate();
    if (!symbolic_link.empty()) {
        device_index = devices.count;
        std::wstring link;
        for (UINT32 i = 0; i < devices.count; ++i) {
            if (SUCCEEDED(readDeviceAttribute(devices.values[i], MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
                    link)) && link == symbolic_link) {
                device_index = i;
                break;
            }
        }
    }
    if (device_index >= devices.count) throw std::runtime_error("No available camera; check Windows camera privacy permission and device connection");
    checkHr(devices.values[device_index]->ActivateObject(IID_PPV_ARGS(&impl_->source)), "Open camera");
    ComPtr<ReaderCallback> callback;
    callback.Attach(new ReaderCallback(impl_->state));
    ComPtr<IMFAttributes> attributes;
    checkHr(MFCreateAttributes(&attributes, 3), "Create reader attributes");
    checkHr(attributes->SetUnknown(MF_SOURCE_READER_ASYNC_CALLBACK, callback.Get()), "Set camera callback");
    checkHr(attributes->SetUINT32(MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE), "Enable NV12 video conversion");
    checkHr(attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, FALSE), "Select CPU video conversion");
    ComPtr<IMFSourceReader> reader;
    checkHr(MFCreateSourceReaderFromMediaSource(impl_->source.Get(), attributes.Get(), &reader), "Create camera reader");
    checkHr(reader->SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS, FALSE), "Disable unused streams");
    checkHr(reader->SetStreamSelection(MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE), "Enable video stream");

    ComPtr<IMFMediaType> selected;
    std::pair<bool, uint64_t> best{};
    UINT32 selected_width = 0, selected_height = 0;
    GUID selected_subtype{};
    const uint64_t preferred_area = uint64_t(preferred_width) * preferred_height;
    for (DWORD i = 0;; ++i) {
        ComPtr<IMFMediaType> type;
        const auto status = reader->GetNativeMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, i, &type);
        if (status == MF_E_NO_MORE_TYPES) break;
        checkHr(status, "Enumerate camera formats");
        UINT32 width = 0, height = 0; GUID subtype{};
        if (FAILED(MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &width, &height))
            || FAILED(type->GetGUID(MF_MT_SUBTYPE, &subtype)) || !supportedDimensions(width, height)) continue;
        if (subtype != MFVideoFormat_NV12 && subtype != MFVideoFormat_YUY2 && subtype != MFVideoFormat_MJPG) continue;
        // An exact size wins. Otherwise the score weighs pixel-count distance, subtype, and distance from the requested frame rate.
        const uint64_t area = uint64_t(width) * height;
        uint64_t score = (area > preferred_area ? area - preferred_area : preferred_area - area) * 100;
        score += subtype == MFVideoFormat_NV12 ? 0 : (subtype == MFVideoFormat_YUY2 ? 10 : 20);
        UINT32 numerator = 0, denominator = 0;
        if (SUCCEEDED(MFGetAttributeRatio(type.Get(), MF_MT_FRAME_RATE, &numerator, &denominator)) && denominator)
            score += static_cast<uint64_t>(std::abs(double(numerator) / denominator - preferred_fps));
        const auto rank = std::make_pair(width != preferred_width || height != preferred_height, score);
        if (!selected || rank < best) {
            best = rank;
            selected = std::move(type);
            selected_width = width;
            selected_height = height;
            selected_subtype = subtype;
        }
    }
    if (!selected) throw std::runtime_error("Camera has no supported NV12/YUY2/MJPEG mode within 1080p");
    checkHr(reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, selected.Get()), "Select capture mode");
    ComPtr<IMFMediaType> output;
    if (selected_subtype != MFVideoFormat_NV12) {
        checkHr(MFCreateMediaType(&output), "Create NV12 output type");
        checkHr(output->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video), "Set video type");
        checkHr(output->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12), "Set NV12 format");
        checkHr(MFSetAttributeSize(output.Get(), MF_MT_FRAME_SIZE, selected_width, selected_height), "Set NV12 dimensions");
        checkHr(reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, output.Get()), "Negotiate NV12 camera output");
    }
    checkHr(reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &output), "Read negotiated camera format");
    impl_->readFormat(output.Get(), selected.Get());
    writeLog("Camera NV12 " + std::to_string(impl_->width) + "x" + std::to_string(impl_->height)
        + " stride=" + std::to_string(impl_->pitch) + " matrix=" + std::to_string(impl_->matrix)
        + " range=" + std::to_string(impl_->range));
    // Missing camera color metadata has a documented Demo fallback: VIDEO/601.
    // This is explicit adapter policy, never a width-based guess inside Core.
    // 缺少相机颜色元数据时，Demo 明确回退到 VIDEO/601；这是适配层策略，Core 不按宽度猜测。
    {
        std::lock_guard<std::mutex> lock(impl_->state->mutex);
        impl_->state->reader = reader; impl_->state->running = true;
    }
    checkHr(reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, nullptr, nullptr, nullptr, nullptr), "Start camera samples");
}
Camera::~Camera() = default;
uint64_t Camera::capturedFrames() const {
    std::lock_guard<std::mutex> lock(impl_->state->mutex); return impl_->state->captured;
}
bool Camera::next(CameraFrame& frame, std::chrono::milliseconds timeout,
    std::chrono::steady_clock::time_point* captured_at, [[maybe_unused]] int zoom_percent) {
    ComPtr<IMFSample> sample;
    ComPtr<IMFMediaType> format;
    {
        std::unique_lock<std::mutex> lock(impl_->state->mutex);
        impl_->state->changed.wait_for(lock, timeout, [&] {
            return impl_->state->latest || !impl_->state->running;
        });
        checkHr(impl_->state->failure, "Camera disconnected or capture failed");
        if (!impl_->state->latest) return false;
        sample = std::move(impl_->state->latest);
        if (captured_at) *captured_at = impl_->state->captured_at;
        format = std::move(impl_->state->pending_format);
    }
    if (format) impl_->readFormat(format.Get());
    frame.width = impl_->width; frame.height = impl_->height;
    frame.matrix = impl_->matrix; frame.range = impl_->range;
    frame.nv12.resize(static_cast<size_t>(frame.width) * frame.height * 3 / 2);
    ComPtr<IMFMediaBuffer> buffer;
    checkHr(sample->ConvertToContiguousBuffer(&buffer), "Read camera buffer");
    ComPtr<IMF2DBuffer> buffer2d;
    if (SUCCEEDED(buffer.As(&buffer2d))) {
        DWORD size = 0;
        checkHr(buffer2d->GetContiguousLength(&size), "Read packed NV12 length");
        if (size != frame.nv12.size()) throw std::runtime_error("Unexpected packed NV12 size");
        checkHr(buffer2d->ContiguousCopyTo(frame.nv12.data(), size), "Copy packed NV12");
    } else {
        BYTE* bytes = nullptr; DWORD length = 0;
        checkHr(buffer->Lock(&bytes, nullptr, &length), "Lock NV12 buffer");
        struct Unlock { IMFMediaBuffer* buffer; ~Unlock() { buffer->Unlock(); } } unlock{buffer.Get()};
        const auto pitch = impl_->pitch;
        const auto rows = frame.height + frame.height / 2;
        if (pitch < frame.width || uint64_t(pitch) * (rows - 1) + frame.width > length)
            throw std::runtime_error("Invalid NV12 stride or buffer length");
        for (int y = 0; y < rows; ++y)
            std::memcpy(frame.nv12.data() + static_cast<size_t>(y) * frame.width,
                bytes + static_cast<size_t>(y) * pitch, frame.width);
    }
    frame.view(); // validate negotiated geometry before accessing preview pixels / 访问预览像素前先校验协商后的尺寸布局。
    return true;
}
}
