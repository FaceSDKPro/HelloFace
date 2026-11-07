#pragma once
#include "types.h"
#include "navigation.h"
#include <algorithm>
#include <atomic>
#include <deque>
#include <optional>

namespace hiface_demo {
struct Settings {
    Page page = Page::Home;
    SearchOptions search;
    FlowOptions flow;
    unsigned detection_max = 10, camera_index = 0, width = 640, height = 480;
    bool detailed = true, mirror = false;
    bool parameters_valid = true; // Invalid saved drafts may navigate, but must not start a fallback flow. / 无效草稿允许进页，但不自动启动回退参数的流程。
    int rotation = 0;
    std::wstring camera_link;
    std::string id = "person-001", group, tag, filter_group, filter_tag, query_id, reference_id;
};
enum class Action { Apply, EnterPage, OpenCamera, CloseCamera, StartFlow, Cancel, Pause,
    LoadA, LoadB, Compare, SetImageReference, ImportReference,
    ExportFeature, ExportPreview, ImageEnroll, RefreshGallery, NextPage,
    DeletePerson, UpdatePerson, ImportJson, ExportJson, ImportImages, SearchPhoto, SearchPhotoAgain, ReleaseMemory, SaveEnrollment, ReplaceEnrollment,
    SaveReference, SelectReference };
struct Command {
    Action action = Action::Apply;
    Settings settings;
    std::vector<std::filesystem::path> files;
    uint64_t generation = 0, sequence = 0, photo_request = 0;
};
// A new view/flow invalidates old work only after its command is admitted.
// SDK actions are validated before enqueueing; navigation may preserve a disabled draft.
// 命令入队后才使旧流程失效；动作先校验，导航可保留不启动的无效草稿。
inline bool replacesView(Action action) {
    switch (action) {
        case Action::EnterPage: case Action::Apply: case Action::OpenCamera:
        case Action::CloseCamera: case Action::StartFlow: case Action::Cancel: case Action::Pause:
        case Action::SelectReference: case Action::SearchPhoto:
        case Action::SearchPhotoAgain: case Action::RefreshGallery: return true;
        default: return false;
    }
}
// Queue mutation/take requires App's mutex. Photo request epochs are atomic
// because a running extraction checks them outside that mutex.
// 队列读写由 App 的互斥锁保护；图片请求代次供进行中的提取读取，因此使用原子量。
class WorkerCommands {
public:
    uint64_t push(Command command, std::atomic<uint64_t>& generation) {
        const auto view = generation.load();
        const int slot = photoSlot(command);
        const bool replace = replacesView(command.action);
        const auto obsolete = [&](const Command& old) {
            return replace || old.generation != view || (slot >= 0 && photoSlot(old) == slot);
        };
        if (std::count_if(pending_.begin(), pending_.end(), [&](const Command& old) { return !obsolete(old); }) >= 4)
            throw std::runtime_error("Task queue is full; wait for the current task");
        command.generation = view;
        command.sequence = next_sequence_ + 1;
        // Allocate before dropping old work, so allocation failure cannot cancel it.
        // 先取得新任务存储，再淘汰旧任务，分配失败不会丢失已入队工作。
        pending_.push_back(std::move(command));
        pending_.erase(std::remove_if(pending_.begin(), pending_.end(), [&](const Command& old) {
            return old.sequence != next_sequence_ + 1 && obsolete(old);
        }), pending_.end());
        auto& admitted = pending_.back();
        if (replace) admitted.generation = ++generation;
        if (slot >= 0) admitted.photo_request = ++photo_requests_[slot];
        return ++next_sequence_;
    }
    bool empty() const { return pending_.empty(); }
    size_t size() const { return pending_.size(); }
    std::optional<Command> take() {
        if (empty()) return std::nullopt;
        auto command = std::move(pending_.front()); pending_.pop_front(); return command;
    }
    bool current(const Command& command, uint64_t generation) const {
        const int slot = photoSlot(command);
        return command.generation == generation
            && (slot < 0 || command.photo_request == photo_requests_[slot]);
    }
private:
    static int photoSlot(const Command& command) {
        if (command.settings.page != Page::Comparison) return -1;
        return command.action == Action::LoadA ? 0 : command.action == Action::LoadB ? 1 : -1;
    }
    std::deque<Command> pending_;
    uint64_t next_sequence_ = 0;
    std::atomic<uint64_t> photo_requests_[2]{{0}, {0}};
};
}
