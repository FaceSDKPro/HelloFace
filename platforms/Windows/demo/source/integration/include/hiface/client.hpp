#pragma once
#include "hiface/frame.hpp"
#include "hiface/error.hpp"
#include <array>
#include <filesystem>
#include <functional>
#include <optional>
#include <stdexcept>
#include <string>

namespace hiface {
struct SearchOptions {
    bool multi_face = false, liveness = true;
    uint32_t max_faces = 3, interval_ms = 0, timeout_ms = 3000;
    float threshold = HIFACE_DEFAULT_VERIFICATION_THRESHOLD;
    std::string group, tag;
};
enum class FlowKind { Capture, Liveness, Verification };
struct FlowOptions {
    FlowKind kind = FlowKind::Capture;
    std::vector<HiFaceFlowActionV1> actions;
    bool silent_liveness = true, allow_multiple = false;
    float threshold = HIFACE_DEFAULT_VERIFICATION_THRESHOLD;
    std::string reference;
};
struct DetailedFace {
    HiFaceFaceV1 face{}; // mesh pointer always null; owned points are below / mesh 指针始终为空，独占的关键点保存在下方。
    std::vector<HiFaceMeshPointV1> mesh;
};
struct CaptureResult { Feature feature{}; Image preview; std::string text; };
struct ImageFaceCapture {
    HiFaceFaceV1 face{};
    HiFaceStatus status = HIFACE_STATUS_INVALID_STATE;
    std::optional<CaptureResult> capture;
};
struct FlowResult {
    HiFaceFlowResultV1 metadata{};
    Image preview;
    std::string feature;
};
HiFaceFlowConfigV1 flowConfig(const FlowOptions& options, const Feature* reference = nullptr);
struct FrameUpdate {
    std::vector<HiFaceSearchCameraFaceV1> faces;
    std::vector<DetailedFace> details;
    std::optional<FlowResult> result;
    bool flow_active = false, cancelled = false, paused = false;
    bool searching = false;
    HiFaceFlowEventV1 event{};
    uint32_t search_progress = 0;
    bool matched = false;
    bool skipped = false;
    uint32_t end_reason = 0;
    bool has_liveness = false;
    float liveness_score = 0;
};

// Demo integration helper over the stable C ABI DLL. One serialized caller per owner.
// Results own their data; no camera, UI, file picker or application policy.
// 基于稳定 C ABI DLL 的 Demo 接入辅助层；每个持有者仅允许一个串行调用方。结果独占数据，不包含相机、UI、选图或应用策略。
class Client {
public:
    explicit Client(const std::filesystem::path& database);
    ~Client();
    Client(const Client&) = delete;
    Client& operator=(const Client&) = delete;
    void loadAllModels();
    void setLiveness(bool enabled);
    void configureSearch(const SearchOptions& options);
    void pauseSearch(bool paused);
    void configureDetection(uint32_t max_faces, bool detailed);
    void useSearch(bool enabled);
    // Starts one capture/action/verification flow; cancels search until completion.
    // 启动一次采集/动作/验证，期间停止搜索；参考特征在调用内复制。
    void beginFlow(const FlowOptions& options);
    void cancelFlow();
    bool flowActive() const { return flow_active_; }
    // Feed one frame on the owning worker. current() suppresses a stale flow result
    // after cancellation/navigation; returned images, meshes and features are owned copies.
    // 在持有者线程喂一帧；current() 拦截取消/离页后的旧结果，返回数据持有独立副本。
    FrameUpdate process(const CameraFrame& frame, const std::function<bool()>& is_current = {});
    std::vector<HiFaceFaceV1> detect(const Image& image);
    FrameUpdate detectDetailed(const Image& image, uint32_t max_faces, bool detailed);
    Feature capture(const Image& image);
    CaptureResult captureWithPreview(const Image& image);
    // Detect once, largest first, without liveness. Per-face errors do not
    // suppress other faces. No faces returns an empty vector successfully.
    // 单次检测，最大脸优先，不执行活体；单张脸失败不影响其他脸，无脸时成功返回空向量。
    std::vector<ImageFaceCapture> captureFaces(const Image& image,
        uint32_t maximum = HIFACE_MAX_FACES, bool previews = true);
    void insertFeature(const std::string& id, const Feature& feature);
    std::vector<std::pair<std::string, float>> query(const Feature& feature);
    // Borrowed handle; do not destroy it or use it concurrently with this Client.
    // 借用句柄，不得由调用方销毁或与 Client 并发访问。
    HiFaceSessionHandle nativeHandle() const { return session_; }
    uint64_t count() const;
private:
    void load(HiFaceModelIdV1 id);
    void startSearch();
    HiFaceSessionHandle session_ = nullptr;
    HiFaceSearchDatabaseHandle database_ = nullptr;
    SearchOptions search_;
    bool search_enabled_ = false, search_paused_ = false, flow_active_ = false;
    bool detailed_ = false;
    uint32_t detection_max_ = 1;
    HiFaceFlowModeV1 flow_mode_ = HIFACE_FLOW_GUIDED_CAPTURE;
    std::array<bool, 5> loaded_{};
    void stopFlow();
    void completeFlow(FrameUpdate& update, const std::function<bool()>& current);
};
}
