#include "app.h"
#include "win_util.h"
#include "enrollment_draft.h"
#include "search_power.h"
#include "workflow_state.h"
#include <algorithm>
#include <iomanip>
#include <sstream>

namespace hiface_demo {
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
    if (stopping_ || !active_) throw std::runtime_error("Demo worker is unavailable; check the diagnostic log and restart");
    const auto sequence = commands_.push(std::move(command), generation);
    changed_.notify_one(); return sequence;
}
std::shared_ptr<const Snapshot> App::current() { std::lock_guard<std::mutex> lock(mutex_); return snapshot_; }
void App::publish(const Snapshot& state) {
    { std::lock_guard<std::mutex> lock(mutex_); snapshot_ = std::make_shared<Snapshot>(state); }
    if (!notification_pending.exchange(true) && !PostMessageW(window, kFrameReady, 0, 0))
        notification_pending = false; // Retry on the next snapshot if the message queue was full. / 投递失败时允许下次快照重试。
}
// Worker main loop: serial commands first, then preview/inference. SDK handles,
// drafts and database writes never cross to the UI thread.
// 工作线程先处理命令，再预览/分析；SDK 句柄、采集草稿及数据库写入均留在此线程。
void App::run() {
    Snapshot state;
    try {
        ComApartment com;
        Gallery gallery(database);
        std::unique_ptr<DemoService> sdk;
        std::unique_ptr<Camera> camera;
        std::unique_ptr<CapturedReferences> references;
        std::string reference_store_error;
        auto load_references = [&] {
            try {
                if(!references)references=std::make_unique<CapturedReferences>(demoDataDirectory()/L"captured-faces.db");
                state.reference_ids=references->ids();reference_store_error.clear();
            } catch(const std::exception& error) {
                references.reset();state.reference_ids.clear();reference_store_error=error.what();
            }
        };
        auto reference_store = [&]() -> CapturedReferences& {
            if(!references)throw std::runtime_error(u8"采集参考库不可用，原文件保留："+reference_store_error);
            return *references;
        };
        ReferenceDraft reference_draft;
        PhotoComparisonCache comparison;
        std::string reference;
        EnrollmentDraft enrollment;
        auto clear_enrollment = [&] {
            enrollment.clear();
            state.pending_enrollment = state.enrollment_conflict = false;
            state.conflict_id.clear();
        };
        auto clear_reference = [&] {
            reference_draft.clear(); state.pending_reference = false;
        };
        GalleryListing listing;
        std::string enrollment_notice;
        std::shared_ptr<const Image> search_source;
        struct SuspendedPhoto {
            std::shared_ptr<const Image> source, photo;
            std::shared_ptr<const ImageSearchResult> result;
            std::filesystem::path file;
            uint64_t generation = 0;
        };
        std::optional<SuspendedPhoto> suspended_photo;
        load_references();
        auto refresh = [&](bool append = false, bool preserve_loaded = false) {
            const auto loaded = preserve_loaded ? state.people.size() : 0;
            state.total = gallery.count();
            state.search_population = gallery.count(state.settings.search.group, state.settings.search.tag);
            if (state.settings.page == Page::Gallery) {
                if (append) listing.append(gallery);
                else listing.reset(gallery, state.settings.query_id, state.settings.filter_group, state.settings.filter_tag);
                while (listing.more && listing.people.size() < loaded) listing.append(gallery);
                state.people = listing.people; state.filtered = listing.filtered;
                state.offset = listing.next; state.gallery_more = listing.more;
            } else {
                listing = {}; state.people.clear(); state.filtered = state.total; state.offset = 0; state.gallery_more = false;
            }
        };
        // Create inference resources on demand; metadata-only operations use the gallery directly.
        // 按需创建推理资源；仅修改资料的操作直接使用人脸库。
        auto ensure = [&]() -> DemoService& {
            if (!sdk) sdk = std::make_unique<DemoService>(database);
            return *sdk;
        };
        // Navigation invalidates transient captures; returning from the gallery may restore
        // the offline photo search. Reapplying search parameters preserves an explicit pause.
        // 切页清理临时采集；从图库返回时恢复图片搜索；搜索页应用参数保留主动暂停状态。
        auto apply = [&](const Settings& settings) {
            const bool keep_paused = state.settings.page == Page::Search && settings.page == Page::Search && state.paused;
            const bool returning_to_photo = state.settings.page == Page::Gallery && settings.page == Page::ImageSearch;
            if (state.settings.page == Page::ImageSearch && settings.page == Page::Gallery)
                suspended_photo = SuspendedPhoto{search_source, state.search_photo, state.image_search, state.search_file, state.search_generation};
            else if (state.settings.page != settings.page && !returning_to_photo) suspended_photo.reset();
            if (sdk) {
                sdk->cancelFlow();
                if (settings.parameters_valid) {
                    if (settings.page == Page::Search) sdk->configureSearch(settings.search);
                    if (usesCamera(settings.page) && settings.page != Page::CameraSettings)
                        sdk->configureDetection(settings.detection_max, settings.detailed && settings.page == Page::Detection);
                }
                sdk->useSearch(settings.parameters_valid && settings.page == Page::Search);
                sdk->pauseSearch(keep_paused);
            }
            if (!usesCamera(settings.page) || state.settings.page != settings.page) camera.reset();
            if (state.settings.page != settings.page) {
                clear_enrollment();
                clear_reference(); comparison.clear();
                state.comparison_ready = false; state.comparison_similarity.reset();
                state.flow_summary.clear();
                state.comparison_error_a.clear(); state.comparison_error_b.clear();
                if (settings.page == Page::Verification || state.settings.page == Page::Verification) {
                    reference.clear(); state.has_reference = false; state.reference_id.clear();
                }
                state.preview.reset(); state.image_a.reset(); state.image_b.reset();
                state.aligned_a.reset(); state.aligned_b.reset(); state.captured.reset(); state.update = {};
                state.image_search.reset(); state.search_photo.reset(); search_source.reset(); state.search_file.clear();
                state.capture_fps = state.analysis_fps = state.inference_ms = 0;
            }
            state.preview_at_ms = state.analysis_at_ms = -1;
            state.flow_summary.clear();
            state.settings = settings; state.flow_active = false; state.paused = keep_paused;
            if (returning_to_photo && suspended_photo) {
                search_source = std::move(suspended_photo->source); state.search_photo = std::move(suspended_photo->photo);
                state.image_search = std::move(suspended_photo->result); state.search_file = std::move(suspended_photo->file);
                state.search_generation = suspended_photo->generation; suspended_photo.reset();
            }
            state.camera_open = bool(camera); state.offset = 0; refresh();
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
                command = commands_.take();
            }
            if (sdk && sdk->flowActive() && flow_generation != generation) {
                sdk->cancelFlow(); state.flow_active = false; state.update.message = u8"已取消当前流程"; publish(state);
            }
            if (command && !stopping_) {
                search_power.reset();
                next_search_preview = next_search_analysis = std::chrono::steady_clock::now();
                state.busy = true; state.importing = command->action == Action::ImportJson || command->action == Action::ImportImages;
                state.error = false; publish(state);
                try {
                    const auto& task = *command;
                    // Page generation cancels old tasks; comparison slots also have independent
                    // request numbers so replacing A cannot cancel the newest B.
                    // 页面代次拦截旧任务；A/B 各有请求号，换 A 不会误取消 B。
                    auto current = [&] {
                        return !stopping_ && commands_.current(task, generation);
                    };
                    auto begin_flow = [&] {
                        if (!task.settings.parameters_valid) throw std::runtime_error(u8"请先修正参数，再开始流程");
                        flow_generation = task.generation;
                        auto options = task.settings.flow;
                        options.reference = reference;
                        ensure().beginFlow(options);
                        state.flow_active = true;
                        state.update.message = u8"流程已开始，请正对摄像头";
                    };
                    // Page entry, device switching and retry share the same open/start path.
                    // 进入页面、切换设备和失败重试复用同一路径；验证页须先选择参考。
                    auto open_camera = [&] {
                        if (!task.settings.parameters_valid) throw std::runtime_error(u8"请先修正参数，再打开摄像头");
                        if (task.settings.page == Page::Reference) { load_references(); (void)reference_store(); }
                        if (task.settings.page == Page::Verification && reference.empty()) throw std::runtime_error(u8"请先选择采集基准");
                        if (task.settings.camera_link.empty()) throw std::runtime_error(u8"未找到摄像头，请连接设备后刷新并重试");
                        if (task.settings.page != Page::CameraSettings) ensure();
                        apply(task.settings);
                        if (!current()) return;
                        if (task.settings.page == Page::Enrollment) {
                            clear_enrollment();
                            state.captured.reset(); state.image_a.reset(); state.preview.reset();
                        }
                        camera.reset(); state.camera_open = false;
                        camera = std::make_unique<Camera>(task.settings.camera_index, task.settings.camera_link, task.settings.width, task.settings.height);
                        if (!current()) { camera.reset(); return; }
                        state.camera_open = true; previous_captured = analyzed = 0;
                        metric_time = last_frame = std::chrono::steady_clock::now();
                        state.update = {}; state.update.message = u8"摄像头已打开";
                        if (task.settings.page == Page::Reference) { clear_reference(); state.captured.reset(); }
                        if (task.settings.page == Page::Enrollment || task.settings.page == Page::Reference || task.settings.page == Page::Verification || task.settings.page == Page::Liveness) {
                            begin_flow();
                        } else if (task.settings.page == Page::Search && !enrollment_notice.empty()) {
                            state.update.message = std::move(enrollment_notice); enrollment_notice.clear();
                        }
                    };
                    // A cancelled queued command must not reopen a camera, stage a face or write data.
                    if (current()) { state.view_generation = task.generation; switch (task.action) {
                        case Action::EnterPage: {
                            const auto page = task.settings.page;
                            if (page == Page::Reference || page == Page::Verification) load_references();
                            // Clear the previous page even when camera/SDK initialization fails.
                            // open_camera reapplies after lazy SDK creation to configure the new session.
                            // 先清理旧页面；相机/SDK 初始化失败也留在目标页，SDK 新建后再配置会话。
                            apply(task.settings); state.update = {};
                            if (page == Page::Reference || page == Page::Verification) (void)reference_store();
                            if (!task.settings.parameters_valid)
                                state.update.message = u8"请修正尚未应用的参数，再打开摄像头开始";
                            else if (page == Page::Verification)
                                state.update.message = u8"请选择已采集的 Face ID，选择后自动开始验证";
                            else if (startsCameraOnEntry(page, task.settings.parameters_valid)) open_camera();
                            break;
                        }
                        case Action::SelectReference:
                            if (state.settings.page != Page::Verification) break;
                            if (sdk) sdk->cancelFlow();
                            camera.reset(); state.camera_open = state.flow_active = false;
                            reference.clear(); state.has_reference = false; state.reference_id.clear();
                            reference = reference_store().feature(task.settings.reference_id);
                            state.reference_id = normalizeMetadata(task.settings.reference_id); state.has_reference = true;
                            open_camera(); break;
                        case Action::OpenCamera: open_camera(); break;
                        case Action::Apply:
                            apply(task.settings); state.update = {};
                            state.update.message = state.settings.page == Page::ImageSearch && state.image_search ? state.image_search->summary
                                : state.paused ? u8"参数已应用，搜索仍暂停；点击恢复搜索后生效" : u8"参数已应用";
                            if (state.settings.page == Page::Search && !enrollment_notice.empty()) {
                                state.update.message = std::move(enrollment_notice); enrollment_notice.clear();
                            }
                            break;
                        case Action::CloseCamera:
                            state.flow_summary.clear();
                            if (sdk) sdk->cancelFlow(); camera.reset(); state.camera_open = state.flow_active = false;
                            state.preview.reset(); state.capture_fps = state.analysis_fps = state.inference_ms = 0;
                            state.update = {}; state.update.message = u8"摄像头已关闭，数据已保留"; break;
                        case Action::StartFlow: {
                            if (!camera) throw std::runtime_error("Open the camera before starting a flow");
                            apply(task.settings); if (!current()) break;
                            clear_enrollment();
                            clear_reference();
                            state.update = {}; state.captured.reset();
                            begin_flow(); break;
                        }
                        case Action::Cancel:
                            state.flow_summary.clear();
                            if (sdk) sdk->cancelFlow(); state.flow_active = false;
                            if (state.settings.page == Page::Search && sdk) { sdk->pauseSearch(true); state.paused = true; }
                            clear_enrollment();
                            clear_reference();
                            if (state.settings.page == Page::Enrollment || state.settings.page == Page::Reference) state.captured.reset();
                            if (state.settings.page == Page::ImageSearch) state.image_search.reset();
                            state.update = {}; state.update.message = state.paused ? u8"搜索已停止，点击恢复搜索重新识别" : u8"已取消；未确认的人脸不会写入人脸库"; break;
                        case Action::Pause:
                            if (!sdk || !camera || state.settings.page != Page::Search) throw std::runtime_error(u8"请先在搜索页打开摄像头");
                            sdk->pauseSearch(!state.paused); state.paused = !state.paused;
                            state.update = {}; state.analysis_fps = state.inference_ms = 0;
                            state.update.message = state.paused ? u8"搜索已暂停，缓存已释放" : u8"搜索已恢复"; break;
                        case Action::LoadA:
                        case Action::LoadB: {
                            if (task.settings.page == Page::Comparison) {
                                const unsigned slot = task.action == Action::LoadA ? 0 : 1;
                                auto& error = slot ? state.comparison_error_b : state.comparison_error_a;
                                try {
                                    auto image = std::make_shared<Image>(readImage(task.files.at(0)));
                                    if (!current()) break;
                                    state.update.message = slot ? u8"正在提取图片 B 特征…" : u8"正在提取图片 A 特征…"; publish(state);
                                    auto captured=ensure().captureWithPreview(*image);
                                    {
                                        std::lock_guard<std::mutex> lock(mutex_);
                                        if (!comparison.replace(slot, [&] { return std::move(captured); }, current)) break;
                                        if (slot) state.image_b = image; else state.image_a = image;
                                        error.clear(); state.comparison_similarity.reset();
                                        state.comparison_ready = comparison.ready(); state.update = {};
                                    }
                                    state.update.message = state.comparison_ready ? u8"两侧特征已就绪，可以比对" : u8"请继续选择另一张照片";
                                } catch (const std::exception& failure) {
                                    if (current()) { error = failure.what(); state.update.message = u8"照片处理失败，原照片和特征保留"; }
                                }
                                break;
                            }
                            const auto image = std::make_shared<Image>(readImage(task.files.at(0)));
                            if (!current()) break;
                            state.update = {}; state.aligned_a.reset(); state.aligned_b.reset();
                            if (state.settings.page == Page::Enrollment) { clear_enrollment(); state.captured.reset(); }
                            if (task.action == Action::LoadA) { state.image_a = image; state.aligned_a.reset(); }
                            else { state.image_b = image; state.aligned_b.reset(); }
                            if (task.settings.page == Page::Reference) { clear_reference(); state.captured.reset(); }
                            if (task.settings.page == Page::Detection) {
                                state.update = ensure().detectDetailed(*image, task.settings.detection_max, task.settings.detailed);
                                camera.reset(); state.camera_open = false; state.settings.mirror = false;
                                state.preview = bgraImage(*image);
                            } else if (task.settings.page == Page::Reference || task.settings.page == Page::Enrollment) {
                                if (sdk) sdk->cancelFlow(); camera.reset(); state.camera_open = false; state.settings.mirror = false;
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
                            const float score = comparison.compare();
                            state.comparison_similarity = score; state.update = {};
                            state.update.message = u8"图片相似度 " + std::to_string(score * 100) + "%";
                            break;
                        }
                        case Action::SetImageReference: {
                            if (!state.image_a) throw std::runtime_error(u8"请先选择基准照片");
                            const auto captured = ensure().captureEnrollmentImage(*state.image_a);
                            if (!current()) break;
                            reference_draft.stage(captured.text); state.pending_reference = true;
                            state.captured = std::make_shared<Image>(captured.preview);
                            state.update = {}; state.update.message = u8"基准采集成功，填写 Face ID 并确认后保存"; break;
                        }
                        case Action::ImportReference: {
                            const auto value = readFeatureFile(task.files.at(0));
                            if (!current()) break;
                            if(sdk)sdk->cancelFlow();camera.reset();state.camera_open=state.flow_active=false;
                            reference_draft.stage(value); state.pending_reference = true; state.captured.reset();state.preview.reset();state.image_a.reset();
                            state.update.message = u8"HF1 已导入为草稿，填写 Face ID 并确认后保存"; break;
                        }
                        case Action::SaveReference:
                            if (state.settings.page != Page::Reference || !current()) break;
                            reference_draft.save(reference_store(), task.settings.id);
                            state.pending_reference = false; state.captured.reset(); state.reference_ids = reference_store().ids();
                            state.update = {}; state.update.message = u8"采集基准已保存"; break;
                        case Action::ExportFeature:
                            if (reference.empty()) throw std::runtime_error(u8"请先在动态验证页选择采集基准");
                            writeFeatureFile(task.files.at(0), reference); state.update.message = u8"HF1 特征已导出"; break;
                        case Action::ExportPreview:
                            if (!state.captured) throw std::runtime_error("Capture an aligned face first");
                            writeImage(task.files.at(0), *state.captured); state.update.message = u8"333×333 对齐图已导出"; break;
                        case Action::ImageEnroll: {
                            if (state.settings.page != Page::Enrollment) throw std::runtime_error("Open the independent enrollment page first");
                            if (!state.image_a) throw std::runtime_error("Choose an image before enrollment");
                            clear_enrollment(); state.captured.reset();
                            const auto captured = ensure().captureEnrollmentImage(*state.image_a);
                            if (!current()) break;
                            enrollment.stage(captured); state.pending_enrollment = true;
                            state.captured = std::make_shared<Image>(captured.preview);
                            state.update = {}; state.update.message = u8"图片采集成功，尚未入库；核对预览和 ID 后确认保存"; break;
                        }
                        case Action::SaveEnrollment: case Action::ReplaceEnrollment: {
                            if (state.settings.page != Page::Enrollment || !current()) break;
                            const bool replace = task.action == Action::ReplaceEnrollment;
                            if (replace && (!state.enrollment_conflict || state.conflict_id != task.settings.id))
                                throw std::runtime_error(u8"人员信息已改变，请重新确认保存");
                            try { enrollment.save(gallery, task.settings.id, task.settings.group, task.settings.tag, replace); }
                            catch (const SdkError& error) {
                                if (error.status != HIFACE_STATUS_ALREADY_EXISTS || replace) throw;
                                state.enrollment_conflict = true; state.conflict_id = task.settings.id;
                                state.update.message = u8"此 ID 已存在；确认覆盖或修改 ID，当前预览保留"; break;
                            }
                            clear_enrollment(); refresh();
                            state.captured.reset();
                            enrollment_notice = u8"已录入人员 " + task.settings.id + u8"；返回后自动恢复搜索";
                            enrollment_notice += u8"；搜索范围须包含该人员的分组和标签";
                            state.update = {}; state.update.message = enrollment_notice; break;
                        }
                        case Action::NextPage: if (state.settings.page == Page::Gallery) refresh(true); break;
                        case Action::RefreshGallery:
                            state.settings = task.settings; state.people.clear();state.offset=0;state.gallery_more=false;refresh();
                            state.update.message = state.people.empty() ? (state.total == 0 ? u8"人脸库为空，请先录入人员" : u8"未找到该 Face ID 或筛选结果为空") : u8"人脸库已加载，滚动到底部自动读取更多"; break;
                        case Action::DeletePerson: {
                            const auto removed = gallery.remove(task.settings.id); refresh(false,true);
                            state.update.message = removed ? u8"人员已删除" : u8"该 ID 不存在"; break;
                        }
                        case Action::UpdatePerson:
                            gallery.updateMetadata(task.settings.id, task.settings.group, task.settings.tag); refresh(false,true); state.update.message = u8"分组和标签已更新"; break;
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
                    } }
                    notice = state.update.message; notice_until = std::chrono::steady_clock::now() + std::chrono::seconds(4);
                } catch (const std::exception& error) {
                    writeLog(error.what());
                    if (sdk) { try { sdk->cancelFlow(); } catch (...) {} }
                    state.flow_active = false;
                    // A failed old file/SDK request must not flash an error over its replacement.
                    // 已取消的旧文件/SDK 请求失败，不覆盖新请求的界面状态。
                    if (!stopping_ && command->generation == generation) {
                        state.error = true; state.update.message = error.what();
                        notice = state.update.message; notice_until = std::chrono::steady_clock::now() + std::chrono::seconds(8);
                    }
                }
                state.busy = state.importing = false; state.completed_command = command->sequence; publish(state);
            }
            if (!camera || stopping_) { search_power.reset(); continue; }
            const bool was_idle = search_power.idle();
            search_power.expire(std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count());
            if (was_idle && !search_power.idle()) next_search_preview = next_search_analysis = std::chrono::steady_clock::now();
            if (state.settings.page == Page::Search) {
                const auto deadline = std::min(next_search_preview, next_search_analysis);
                std::unique_lock<std::mutex> lock(mutex_);
                if (std::chrono::steady_clock::now() < deadline) {
                    changed_.wait_until(lock, deadline, [&] { return stopping_ || !commands_.empty(); });
                    if (stopping_ || !commands_.empty()) continue;
                }
            }
            // Paused/pending-capture pages still preview, but do not run face analysis.
            // 暂停或等待确认时继续预览，不分析人脸；搜索的活跃/待机阶段均限流。
            try {
                CameraFrame frame;
                std::chrono::steady_clock::time_point captured_at;
                if (!camera->next(frame, std::chrono::milliseconds(100), &captured_at)) {
                    if (std::chrono::steady_clock::now() - last_frame > std::chrono::seconds(15)) throw std::runtime_error("Camera produced no frames for 15 seconds; check privacy settings and connection");
                    continue;
                }
                last_frame = captured_at; frame.rotation_degrees = state.settings.rotation;
                if (state.settings.page == Page::CameraSettings || state.pending_enrollment || state.pending_reference
                    || ((state.settings.page == Page::Enrollment || state.settings.page == Page::Reference || state.settings.page == Page::Verification || state.settings.page == Page::Liveness) && !state.flow_active) || state.paused) {
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
                const bool searching = state.settings.page == Page::Search;
                const bool preview_due = !searching || begin >= next_search_preview;
                const bool analysis_due = !searching || begin >= next_search_analysis;
                if (!preview_due && !analysis_due) continue;
                if (preview_due) {
                    state.preview = std::make_shared<Image>(frame.displayBgra(state.settings.mirror));
                    state.preview_at_ms = std::chrono::duration_cast<std::chrono::milliseconds>(captured_at.time_since_epoch()).count();
                    next_search_preview = begin + std::chrono::milliseconds(search_power.previewInterval());
                }
                if (!analysis_due) { publish(state); continue; }
                next_search_analysis = begin + std::chrono::milliseconds(search_power.analysisInterval());
                const auto frame_generation = state.view_generation;
                if (frame_generation != generation) continue;
                // A queued navigation request must invalidate the old page even if
                // it arrived between the worker's flow-cancel check and this frame.
                auto update = sdk->process(frame, [&] { return !stopping_ && frame_generation == generation; });
                if (stopping_ || frame_generation != generation) continue;
                if (update.skipped) { if (preview_due) publish(state); continue; }
                state.analysis_at_ms = std::chrono::duration_cast<std::chrono::milliseconds>(captured_at.time_since_epoch()).count();
                if (searching) {
                    const auto detected_at = std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::steady_clock::now().time_since_epoch()).count();
                    const bool previous_idle = search_power.idle();
                    search_power.observeFrame(state.analysis_at_ms, detected_at, !update.faces.empty());
                    next_search_analysis = begin + std::chrono::milliseconds(search_power.analysisInterval());
                    // Apply the new cadence on this result, including unmatched/rejected faces.
                    // 本帧即切换节奏，未匹配或活体拒绝的人脸同样唤醒。
                    if (previous_idle != search_power.idle())
                        next_search_preview = begin + std::chrono::milliseconds(search_power.previewInterval());
                } else search_power.reset();
                state.inference_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - begin).count();
                state.flow_active = sdk->flowActive(); ++analyzed;
                if (update.result) {
                    if (!update.result->preview.rgba.empty()) state.captured = std::make_shared<Image>(update.result->preview);
                    if (state.settings.page == Page::Reference && update.matched && !update.result->feature.empty()) {
                        reference_draft.stage(update.result->feature); state.pending_reference = true;
                        update.message = u8"采集成功，填写 Face ID 并确认后保存到参考库";
                    }
                    if (state.settings.page == Page::Enrollment && update.matched) {
                        clear_enrollment();
                        enrollment.stage(*update.result); state.pending_enrollment = true;
                        update.message = u8"采集成功，尚未入库；请核对预览和 ID 后确认保存，或重新采集";
                    }
                    if (state.settings.page == Page::Verification || state.settings.page == Page::Liveness) {
                        state.flow_summary = update.message;
                        if (update.result->metadata.flags & HIFACE_FLOW_RESULT_HAS_SIMILARITY) {
                            const auto raw_similarity=state.flow_summary.find(u8" | 相似度=");
                            if(raw_similarity!=std::string::npos)state.flow_summary.erase(raw_similarity);
                            std::ostringstream score; score << std::fixed << std::setprecision(2) << update.result->metadata.similarity * 100;
                            state.flow_summary = u8"Face ID: " + state.reference_id + u8"\n相似度: " + score.str() + "%\n" + state.flow_summary;
                        }
                        ++state.flow_completion;
                    }
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
                if (sdk) { try { sdk->cancelFlow(); } catch (...) {} }
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
