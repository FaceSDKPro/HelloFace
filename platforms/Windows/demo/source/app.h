#pragma once
#include "camera.h"
#include "worker_commands.h"
#include "data_exchange.h"
#include "demo_service.h"
#include <windows.h>
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>

namespace hiface_demo {
constexpr UINT kFrameReady = WM_APP + 1;
// Read-only UI snapshot; SDK handles and camera objects remain on the worker thread.
// UI 只读取状态快照；SDK 句柄和相机对象保留在工作线程。
struct Snapshot {
    Settings settings;
    std::shared_ptr<const Image> preview, image_a, image_b, aligned_a, aligned_b, captured;
    Update update;
    std::shared_ptr<const Image> search_photo; // BGRA for the native view / 供原生视图显示的 BGRA。
    std::filesystem::path search_file;
    std::shared_ptr<const ImageSearchResult> image_search;
    std::vector<Person> people;
    std::vector<std::string> reference_ids;
    std::string reference_id, comparison_error_a, comparison_error_b, flow_summary;
    std::optional<float> comparison_similarity;
    uint64_t flow_completion = 0;
    bool pending_reference = false, comparison_ready = false;
    uint64_t total = 0, filtered = 0, search_population = 0;
    uint32_t offset = 0;
    uint64_t completed_command = 0, search_generation = 0, view_generation = 0;
    int64_t preview_at_ms = -1, analysis_at_ms = -1;
    bool gallery_more = false, enrollment_conflict = false;
    std::string conflict_id;
    bool error = false, pending_enrollment = false;
    bool camera_open = false, busy = false, importing = false, flow_active = false, paused = false, has_reference = false, fatal = false;
    double capture_fps = 0, analysis_fps = 0, inference_ms = 0;
};
// One worker owns SDK, database, and camera resources; the UI submits bounded commands.
// 工作线程统一管理 SDK、数据库和相机资源；UI 通过有界队列提交命令。
class App {
public:
    HWND window = nullptr;
    std::filesystem::path database;
    std::vector<CameraDevice> cameras; // UI thread only / 仅限 UI 线程。
    // Admitted commands advance the epoch; typing an ID query invalidates immediately.
    // The worker checks this before publishing or writing.
    // 命令入队后推进代次；ID 输入立即失效旧查询。工作线程在发布/写库前检查。
    std::atomic<uint64_t> generation{0};
    std::atomic<bool> notification_pending{false};
    ~App();
    void start();
    void stop();
    uint64_t enqueue(Command command);
    std::shared_ptr<const Snapshot> current();
private:
    std::atomic<bool> stopping_{false};
    std::atomic<bool> active_{false};
    std::thread worker_;
    std::mutex mutex_;
    std::condition_variable changed_;
    WorkerCommands commands_;
    std::shared_ptr<const Snapshot> snapshot_ = std::make_shared<Snapshot>();
    void publish(const Snapshot& state);
    void run();
};
std::shared_ptr<const Image> bgraImage(const Image& image);
}
