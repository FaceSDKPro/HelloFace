#include "app.h"
#include "win_util.h"
#include "enrollment_draft.h"
#include "search_power.h"
#include <algorithm>
#include <fstream>

namespace hiface_demo {
namespace {
std::string readReference(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (!input) return {};
    if (input.tellg() < 0 || input.tellg() > HIFACE_FEATURE_TEXT_LENGTH + 16) throw std::runtime_error("Invalid HF1 file size");
    input.seekg(0);
    std::string text((std::istreambuf_iterator<char>(input)), {});
    if (text.size() > HIFACE_FEATURE_TEXT_LENGTH + 16) throw std::runtime_error("Invalid HF1 file size");
    while (!text.empty() && (text.back() == '\r' || text.back() == '\n' || text.back() == ' ')) text.pop_back();
    if (text.compare(0, 3, "\xef\xbb\xbf") == 0) text.erase(0, 3);
    decodeFeature(text); return text;
}
void saveReference(const std::filesystem::path& path, const std::string& text) {
    decodeFeature(text);
    auto temporary = path; temporary += L".tmp-" + std::to_wstring(GetCurrentProcessId())
        + L"-" + std::to_wstring(std::chrono::steady_clock::now().time_since_epoch().count());
    struct Cleanup { std::filesystem::path path; ~Cleanup() { std::error_code ignored; std::filesystem::remove(path, ignored); } } cleanup{temporary};
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    output << text << '\n'; output.close();
    if (!output || !MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        throw std::runtime_error("Cannot save reference HF1");
}

}
std::shared_ptr<const Image> bgraImage(const Image& source) {
    auto image = std::make_shared<Image>(source);
    for (size_t i = 0; i + 3 < image->rgba.size(); i += 4) std::swap(image->rgba[i], image->rgba[i + 2]);
    return image;
}
App::~App() { stop(); }
void App::start() {
    active_ = true;
    try { worker_ = std::thread([this] { run(); }); } catch (...) { active_ = false; throw; }
}
void App::stop() {
    stopping_ = true; ++generation; changed_.notify_all();
    if (worker_.joinable()) worker_.join();
}
uint64_t App::enqueue(Command command) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!active_) throw std::runtime_error("Demo worker is unavailable; check the diagnostic log and restart");
    if (commands_.size() >= 4) throw std::runtime_error("Task queue is full; wait for the current task");
    command.generation = generation; command.sequence = ++next_command_;
    commands_.push_back(std::move(command)); changed_.notify_one(); return next_command_;
}
std::shared_ptr<const Snapshot> App::current() { std::lock_guard<std::mutex> lock(mutex_); return snapshot_; }
void App::publish(const Snapshot& state) {
    { std::lock_guard<std::mutex> lock(mutex_); snapshot_ = std::make_shared<Snapshot>(state); }
    if (!notification_pending.exchange(true)) PostMessageW(window, kFrameReady, 0, 0);
}
void App::run() {
    Snapshot state;
    try {
        ComApartment com;
        Gallery gallery(database);
        std::unique_ptr<DemoService> sdk;
        std::unique_ptr<Camera> camera;
        const auto reference_path = demoDataDirectory() / L"verification.hf1";
        std::string reference;
        EnrollmentDraft enrollment;
        std::string enrollment_notice;
        std::shared_ptr<const Image> search_source;
        struct SuspendedPhoto {
            std::shared_ptr<const Image> source, photo;
            std::shared_ptr<const ImageSearchResult> result;
            std::filesystem::path file;
            uint64_t generation = 0;
        };
        std::optional<SuspendedPhoto> suspended_photo;
        try { reference = readReference(reference_path); }
        catch (const std::exception& error) { writeLog(error.what()); state.error = true; state.update.message = error.what(); }
        state.has_reference = !reference.empty();
        auto refresh = [&] {
            state.total = gallery.count();
            state.filtered = gallery.count(state.settings.filter_group, state.settings.filter_tag);
            state.search_population = gallery.count(state.settings.search.group, state.settings.search.tag);
            if (state.offset >= state.filtered) state.offset = 0;
            state.people = gallery.list(state.offset, 100, state.settings.filter_group, state.settings.filter_tag);
        };
        // Create inference resources on demand; metadata-only operations use the gallery directly.
        // 按需创建推理资源；仅修改资料的操作直接使用人脸库。
        auto ensure = [&]() -> DemoService& {
            if (!sdk) sdk = std::make_unique<DemoService>(database);
            return *sdk;
        };
        auto apply = [&](const Settings& settings) {
            const bool keep_paused = state.settings.page == Page::Search && settings.page == Page::Search && state.paused;
            const bool returning_to_photo = state.settings.page == Page::Gallery && settings.page == Page::ImageSearch;
            if (state.settings.page == Page::ImageSearch && settings.page == Page::Gallery)
                suspended_photo = SuspendedPhoto{search_source, state.search_photo, state.image_search, state.search_file, state.search_generation};
            else if (state.settings.page != settings.page && !returning_to_photo) suspended_photo.reset();
            if (sdk) {
                sdk->cancelEnrollment();
                if (settings.page == Page::Search) sdk->configureSearch(settings.search);
                if (usesCamera(settings.page) && settings.page != Page::CameraSettings)
                    sdk->configureDetection(settings.detection_max, settings.detailed && settings.page == Page::Detection);
                sdk->useSearch(settings.page == Page::Search);
                sdk->pauseSearch(keep_paused);
            }
            if (!usesCamera(settings.page) || state.settings.page != settings.page) camera.reset();
            if (state.settings.page != settings.page) {
                enrollment.clear(); state.pending_enrollment = false;
                state.preview.reset(); state.image_a.reset(); state.image_b.reset();
                state.aligned_a.reset(); state.aligned_b.reset(); state.captured.reset(); state.update = {};
                state.image_search.reset(); state.search_photo.reset(); search_source.reset(); state.search_file.clear();
                state.capture_fps = state.analysis_fps = state.inference_ms = 0;
            }
            state.settings = settings; state.flow_active = false; state.paused = keep_paused;
            if (returning_to_photo && suspended_photo) {
                search_source = std::move(suspended_photo->source); state.search_photo = std::move(suspended_photo->photo);
                state.image_search = std::move(suspended_photo->result); state.search_file = std::move(suspended_photo->file);
                state.search_generation = suspended_photo->generation; suspended_photo.reset();
            }
            state.camera_open = bool(camera); state.offset = 0; refresh();
        };
        auto setReference = [&](const std::string& value, std::shared_ptr<const Image> preview = {}) {
            saveReference(reference_path, value); reference = value; state.has_reference = true;
            state.captured = std::move(preview);
            state.update.message = u8"1:1 基准已保存，重启后仍可使用";
        };
        refresh();
        if (state.update.message.empty()) state.update.message = u8"选择功能和摄像头后打开；图片和人脸库功能无需摄像头";
        publish(state);
        uint64_t flow_generation = 0;
        auto last_frame = std::chrono::steady_clock::now(), metric_time = last_frame;
        auto notice_until = last_frame;
        auto next_search_preview = last_frame, next_search_analysis = last_frame;
        SearchPreviewPower search_power;
        std::string notice;
        uint64_t analyzed = 0, previous_captured = 0;
        while (!stopping_) {
            std::optional<Command> command;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                if (!camera && commands_.empty()) changed_.wait(lock, [&] { return stopping_ || !commands_.empty(); });
                if (!commands_.empty()) { command = std::move(commands_.front()); commands_.pop_front(); }
            }
            if (sdk && sdk->enrolling() && flow_generation != generation) {
                sdk->cancelEnrollment(); state.flow_active = false; state.update.message = u8"已取消当前流程"; publish(state);
            }
            if (command && !stopping_) {
                search_power.reset();
                next_search_preview = next_search_analysis = std::chrono::steady_clock::now();
                state.busy = true; state.importing = command->action == Action::ImportJson || command->action == Action::ImportImages;
                state.error = false; publish(state);
                try {
                    const auto& task = *command;
                    auto current = [&] { return !stopping_ && task.generation == generation; };
                    // A cancelled queued command must not reopen a camera, stage a face or write data.
                    if (current()) switch (task.action) {
                        case Action::Apply:
                            apply(task.settings); state.update = {};
                            state.update.message = state.settings.page == Page::ImageSearch && state.image_search ? state.image_search->summary
                                : state.paused ? u8"参数已应用，搜索仍暂停；点击恢复搜索后生效" : u8"参数已应用";
                            if (state.settings.page == Page::Search && !enrollment_notice.empty()) {
                                state.update.message = std::move(enrollment_notice); enrollment_notice.clear();
                            }
                            break;
                        case Action::OpenCamera: {
                            if (task.settings.page != Page::CameraSettings) ensure();
                            apply(task.settings);
                            if (!current()) break;
                            if (task.settings.page == Page::Enrollment) {
                                enrollment.clear(); state.pending_enrollment = false; state.captured.reset();
                                state.image_a.reset(); state.preview.reset();
                            }
                            camera.reset(); state.camera_open = false;
                            camera = std::make_unique<Camera>(task.settings.camera_index, task.settings.camera_link, task.settings.width, task.settings.height);
                            state.camera_open = true; previous_captured = analyzed = 0;
                            metric_time = last_frame = std::chrono::steady_clock::now();
                            state.update = {}; state.update.message = u8"摄像头已打开"; break;
                        }
                        case Action::CloseCamera:
                            if (sdk) sdk->cancelEnrollment(); camera.reset(); state.camera_open = state.flow_active = false;
                            state.preview.reset(); state.capture_fps = state.analysis_fps = state.inference_ms = 0;
                            state.update = {}; state.update.message = u8"摄像头已关闭，数据已保留"; break;
                        case Action::StartFlow: {
                            if (!camera) throw std::runtime_error("Open the camera before starting a flow");
                            apply(task.settings); if (!current()) break;
                            enrollment.clear(); state.pending_enrollment = false;
                            flow_generation = task.generation;
                            auto options = task.settings.flow; options.reference = reference;
                            sdk->beginFlow(options);
                            state.flow_active = true; state.update = {}; state.captured.reset();
                            state.update.message = u8"流程已开始，请看向摄像头"; break;
                        }
                        case Action::Cancel:
                            if (sdk) sdk->cancelEnrollment(); state.flow_active = false;
                            if (state.settings.page == Page::Search && sdk) { sdk->pauseSearch(true); state.paused = true; }
                            enrollment.clear(); state.pending_enrollment = false;
                            if (state.settings.page == Page::Enrollment) state.captured.reset();
                            if (state.settings.page == Page::ImageSearch) state.image_search.reset();
                            state.update = {}; state.update.message = state.paused ? u8"搜索已停止，点击恢复搜索重新识别" : u8"已取消；未确认的人脸不会写入人脸库"; break;
                        case Action::Pause:
                            if (!sdk || !camera || state.settings.page != Page::Search) throw std::runtime_error(u8"请先在搜索页打开摄像头");
                            sdk->pauseSearch(!state.paused); state.paused = !state.paused;
                            state.update = {}; state.analysis_fps = state.inference_ms = 0;
                            state.update.message = state.paused ? u8"搜索已暂停，缓存已释放" : u8"搜索已恢复"; break;
                        case Action::LoadA:
                        case Action::LoadB: {
                            const auto image = std::make_shared<Image>(readImage(task.files.at(0)));
                            if (!current()) break;
                            state.update = {}; state.aligned_a.reset(); state.aligned_b.reset();
                            if (state.settings.page == Page::Enrollment) { enrollment.clear(); state.pending_enrollment = false; state.captured.reset(); }
                            if (task.action == Action::LoadA) { state.image_a = image; state.aligned_a.reset(); }
                            else { state.image_b = image; state.aligned_b.reset(); }
                            if (task.settings.page == Page::Detection) {
                                state.update = ensure().detectDetailed(*image, task.settings.detection_max, task.settings.detailed);
                                camera.reset(); state.camera_open = false; state.settings.mirror = false;
                                state.preview = bgraImage(*image);
                            } else if (task.settings.page == Page::Reference || task.settings.page == Page::Enrollment) {
                                if (sdk) sdk->cancelEnrollment(); camera.reset(); state.camera_open = false; state.settings.mirror = false;
                                state.preview = bgraImage(*image);
                                state.update.message = u8"已选择图片，请采集待确认人脸或设为 1:1 基准";
                            } else state.update.message = u8"图片已加载，可执行比对、设为基准或录入";
                            break;
                        }
                        case Action::SearchPhoto:
                        case Action::SearchPhotoAgain: {
                            if (!current()) break;
                            apply(task.settings);
                            state.image_search.reset(); state.search_generation = task.generation; state.update = {}; state.error = false;
                            if (task.action == Action::SearchPhoto) {
                                search_source.reset(); state.search_photo.reset(); state.search_file = task.files.at(0);
                            }
                            state.update.message = u8"正在检测、矫正并搜索…"; publish(state);
                            if (task.action == Action::SearchPhoto) search_source = std::make_shared<Image>(readImage(task.files.at(0), true));
                            if (!current()) break;
                            if (!search_source) throw std::runtime_error("Choose an image to search first");
                            state.search_photo = bgraImage(*search_source); publish(state);
                            auto found = ensure().searchImage(*search_source, current);
                            if (!found || !current()) break;
                            state.image_search = std::make_shared<ImageSearchResult>(std::move(*found));
                            state.update.message = state.image_search->summary; break;
                        }
                        case Action::Compare: {
                            if (!state.image_a || !state.image_b) throw std::runtime_error("Choose both image A and image B");
                            auto a = ensure().captureWithPreview(*state.image_a), b = sdk->captureWithPreview(*state.image_b);
                            const float score = compareFeatureText(a.text, b.text); // Android compareBlocking also compares the encoded HF1 features. / Android compareBlocking 同样比较编码后的 HF1 特征。
                            state.aligned_a = std::make_shared<Image>(std::move(a.preview)); state.aligned_b = std::make_shared<Image>(std::move(b.preview));
                            state.update = {}; state.update.matched = score >= task.settings.flow.threshold;
                            state.update.message = (state.update.matched ? u8"图片比对通过" : u8"图片不匹配") + std::string(u8" | 相似度=") + std::to_string(score);
                            break;
                        }
                        case Action::SetImageReference: {
                            if (!state.image_a) throw std::runtime_error("Choose a reference image first");
                            auto captured = ensure().captureWithPreview(*state.image_a);
                            setReference(captured.text, std::make_shared<Image>(std::move(captured.preview))); break;
                        }
                        case Action::SetGalleryReference: setReference(gallery.get(task.settings.id).feature); break;
                        case Action::ImportReference: {
                            const auto value = readReference(task.files.at(0)); if (value.empty()) throw std::runtime_error("Cannot read reference HF1 file");
                            setReference(value); break;
                        }
                        case Action::ExportFeature:
                            if (reference.empty()) throw std::runtime_error("No captured 1:1 reference to export");
                            saveReference(task.files.at(0), reference); state.update.message = u8"HF1 特征已导出"; break;
                        case Action::ExportPreview:
                            if (!state.captured) throw std::runtime_error("Capture an aligned face first");
                            writeImage(task.files.at(0), *state.captured); state.update.message = u8"333×333 对齐图已导出"; break;
                        case Action::ImageEnroll: {
                            if (state.settings.page != Page::Enrollment) throw std::runtime_error("Open the independent enrollment page first");
                            if (!state.image_a) throw std::runtime_error("Choose an image before enrollment");
                            enrollment.clear(); state.pending_enrollment = false; state.captured.reset();
                            const auto captured = ensure().captureEnrollmentImage(*state.image_a);
                            if (!current()) break;
                            enrollment.stage(captured); state.pending_enrollment = true;
                            state.captured = std::make_shared<Image>(captured.preview);
                            state.update = {}; state.update.message = u8"图片采集成功，尚未入库；核对预览和 ID 后确认保存"; break;
                        }
                        case Action::SaveEnrollment:
                            if (state.settings.page != Page::Enrollment || !current()) break;
                            enrollment.save(gallery, task.settings.id, task.settings.group, task.settings.tag);
                            state.pending_enrollment = false; refresh();
                            state.captured.reset();
                            enrollment_notice = u8"已录入人员 " + task.settings.id + u8"；请打开摄像头开始搜索";
                            enrollment_notice += u8"；搜索范围须包含该人员的分组和标签";
                            state.update = {}; state.update.message = enrollment_notice; break;
                        case Action::PreviousPage: if (state.offset >= 100) state.offset -= 100; refresh(); break;
                        case Action::NextPage: if (state.offset + 100 < state.filtered) state.offset += 100; refresh(); break;
                        case Action::RefreshGallery: state.settings = task.settings; state.offset = 0; refresh(); state.update.message = u8"人脸库已刷新，每页 100 条"; break;
                        case Action::DeletePerson: {
                            const auto removed = gallery.remove(task.settings.id); refresh();
                            state.update.message = removed ? u8"人员已删除" : u8"该 ID 不存在"; break;
                        }
                        case Action::UpdatePerson:
                            gallery.updateMetadata(task.settings.id, task.settings.group, task.settings.tag); refresh(); state.update.message = u8"分组和标签已更新"; break;
                        case Action::ImportJson: {
                            auto progress = importDataset(gallery, task.files.at(0), [&](const ImportProgress& value) {
                                if (value.processed % 100 == 0 || value.processed == value.total) {
                                    state.update.message = u8"导入 " + std::to_string(value.processed) + "/" + std::to_string(value.total) + u8" | 已保存=" + std::to_string(value.saved) + u8" | 失败=" + std::to_string(value.failed); publish(state);
                                }
                                return current();
                            });
                            refresh(); state.update.message = std::string(progress.stopped ? u8"已停止导入" : u8"导入完成") + u8" | 保存=" + std::to_string(progress.saved) + u8" | 失败=" + std::to_string(progress.failed); break;
                        }
                        case Action::ExportJson:
                            state.update.message = u8"已导出 " + std::to_string(exportDataset(gallery, task.files.at(0), task.settings.filter_group, task.settings.filter_tag)) + u8" 条原始 HF1"; break;
                        case Action::ImportImages: {
                            size_t saved = 0, failed = 0;
                            auto& engine = ensure();
                            for (size_t i = 0; i < task.files.size() && current(); ++i) {
                                try {
                                    const auto feature = engine.capture(readImage(task.files[i]));
                                    if (!current()) break;
                                    gallery.save({{task.files[i].stem().u8string(), task.settings.group, task.settings.tag, encodeFeature(feature), 0}}, true); ++saved;
                                } catch (const std::exception& error) { ++failed; writeLog(error.what()); }
                                state.update.message = u8"图片导入 " + std::to_string(i + 1) + "/" + std::to_string(task.files.size()) + u8" | 保存=" + std::to_string(saved) + u8" | 失败=" + std::to_string(failed); publish(state);
                            }
                            refresh(); state.update.message = std::string(current() ? u8"图片导入完成" : u8"已停止图片导入") + u8" | 保存=" + std::to_string(saved) + u8" | 失败=" + std::to_string(failed); break;
                        }
                        case Action::ReleaseMemory:
                            gallery.releaseMemory(); if (sdk) sdk->releaseMemory();
                            state.update.message = u8"数据库缓存已释放，磁盘记录保留"; break;
                    }
                    notice = state.update.message; notice_until = std::chrono::steady_clock::now() + std::chrono::seconds(4);
                } catch (const std::exception& error) {
                    writeLog(error.what()); state.error = true; state.update.message = error.what();
                    if (sdk) { try { sdk->cancelEnrollment(); } catch (...) {} }
                    state.flow_active = false; refresh();
                    notice = state.update.message; notice_until = std::chrono::steady_clock::now() + std::chrono::seconds(8);
                }
                state.busy = state.importing = false; state.completed_command = command->sequence; publish(state);
            }
            if (!camera || stopping_) { search_power.reset(); continue; }
            if (state.settings.page == Page::Search && search_power.idle()) {
                const auto deadline = std::min(next_search_preview, next_search_analysis);
                std::unique_lock<std::mutex> lock(mutex_);
                if (std::chrono::steady_clock::now() < deadline) {
                    changed_.wait_until(lock, deadline, [&] { return stopping_ || !commands_.empty(); });
                    if (stopping_ || !commands_.empty()) continue;
                }
            }
            try {
                CameraFrame frame;
                if (!camera->next(frame, std::chrono::milliseconds(100))) {
                    if (std::chrono::steady_clock::now() - last_frame > std::chrono::seconds(15)) throw std::runtime_error("Camera produced no frames for 15 seconds; check privacy settings and connection");
                    continue;
                }
                last_frame = std::chrono::steady_clock::now(); frame.rotation_degrees = state.settings.rotation;
                if (state.settings.page == Page::CameraSettings || state.pending_enrollment
                    || (state.settings.page == Page::Enrollment && !state.flow_active) || state.paused) {
                    search_power.reset();
                    state.preview = std::make_shared<Image>(frame.displayBgra(state.settings.mirror));
                    state.update.faces.clear(); state.update.details.clear();
                    state.analysis_fps = state.inference_ms = 0;
                    const auto seconds = std::chrono::duration<double>(last_frame - metric_time).count();
                    if (seconds >= 1) {
                        const auto captured = camera->capturedFrames(); state.capture_fps = (captured - previous_captured) / seconds;
                        previous_captured = captured; metric_time = last_frame;
                    }
                    publish(state); continue;
                }
                const auto begin = std::chrono::steady_clock::now();
                const bool idle_search = state.settings.page == Page::Search && search_power.idle();
                const bool preview_due = !idle_search || begin >= next_search_preview;
                const bool analysis_due = !idle_search || begin >= next_search_analysis;
                if (!preview_due && !analysis_due) continue;
                if (preview_due) {
                    state.preview = std::make_shared<Image>(frame.displayBgra(state.settings.mirror));
                    next_search_preview = begin + std::chrono::milliseconds(SearchPreviewPower::preview_interval_ms);
                }
                if (!analysis_due) { publish(state); continue; }
                next_search_analysis = begin + std::chrono::milliseconds(SearchPreviewPower::analysis_interval_ms);
                const auto frame_generation = generation.load();
                auto update = sdk->process(frame, [&] { return !stopping_ && flow_generation == generation; });
                if (stopping_ || frame_generation != generation) continue;
                if (update.skipped) { if (preview_due) publish(state); continue; }
                if (state.settings.page == Page::Search) {
                    const auto detected_at = std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::steady_clock::now().time_since_epoch()).count();
                    search_power.observe(detected_at, !update.faces.empty());
                } else search_power.reset();
                state.inference_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - begin).count();
                state.flow_active = sdk->enrolling(); ++analyzed;
                if (update.result) {
                    if (!update.result->preview.rgba.empty()) state.captured = std::make_shared<Image>(update.result->preview);
                    if (state.settings.page == Page::Reference && update.matched && !update.result->feature.empty()) {
                        setReference(update.result->feature, state.captured); update.message = state.update.message;
                    }
                    if (state.settings.page == Page::Enrollment && update.matched) {
                        enrollment.stage(*update.result); state.pending_enrollment = true;
                        update.message = u8"采集成功，尚未入库；请核对预览和 ID 后确认保存，或重新采集";
                    }
                    if (update.saved) refresh();
                    notice = update.message; notice_until = last_frame + std::chrono::seconds(6);
                    update.result.reset(); // UI needs the outcome message/preview, never the HF1 payload. / UI 只需要结果提示与预览，不需要 HF1 内容。
                }
                if (!state.flow_active && state.settings.page != Page::Search && last_frame < notice_until) update.message = notice;
                else state.error = false;
                state.update = std::move(update);
                const auto seconds = std::chrono::duration<double>(last_frame - metric_time).count();
                if (seconds >= 1) {
                    const auto captured = camera->capturedFrames();
                    state.capture_fps = (captured - previous_captured) / seconds; state.analysis_fps = analyzed / seconds;
                    previous_captured = captured; analyzed = 0; metric_time = last_frame;
                }
                publish(state);
            } catch (const std::exception& error) {
                search_power.reset();
                writeLog(error.what());
                if (sdk) { try { sdk->cancelEnrollment(); } catch (...) {} }
                camera.reset(); state.camera_open = state.flow_active = false;
                state.error = true; state.update.message = std::string(u8"摄像头已停止: ") + error.what(); publish(state);
            }
        }
        // All Native owners and pending samples die on this worker before COM.
        // 所有 Native 资源持有者和待处理样本先在此工作线程销毁，再清理 COM。
        camera.reset(); sdk.reset();
    } catch (const std::exception& error) {
        writeLog(error.what()); state.busy = state.camera_open = state.flow_active = false;
        state.fatal = true;
        state.update.message = std::string(u8"初始化失败: ") + error.what(); publish(state);
    }
    active_ = false;
}
}
