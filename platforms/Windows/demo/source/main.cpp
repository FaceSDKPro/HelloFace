#include "app.h"
#include "camera_preferences.h"
#include "win_util.h"
#include "theme.h"
#include "image_search_view.h"
#include "enrollment_draft.h"
#include "search_power.h"
#include "workflow_state.h"
#include <commctrl.h>
#include <commdlg.h>
#include <shellapi.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <chrono>
#include <iomanip>
#include <numeric>
#include <random>
#include <sstream>
#include <utility>
#include <windowsx.h>

namespace {
using namespace hiface_demo;
constexpr wchar_t kWebsiteUrl[] = L"https://helloface.pages.dev/";
constexpr UINT_PTR kWebsiteToastTimer = 1;
constexpr UINT_PTR kSearchDisplayTimer = 2, kGalleryQueryTimer = 3;

bool chineseUi() {
    return PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_CHINESE;
}

std::wstring aboutTitle() {
    return std::wstring(chineseUi() ? L"关于 HelloFace SDK " : L"About HelloFace SDK ") + widen(HIFACE_DEMO_SDK_VERSION);
}
enum Control {
    Device = 100, RefreshDevices, Open, Close, Resolution, Rotation, Mirror, Apply, Logs, Help,
    PersonId, Group, Tag, MaxFaces, Details, SearchMode, Silent, Threshold, Interval, Timeout,
    Actions, CustomActions, Multiple, StartFlow, Enroll, Cancel, Pause, PickA, PickB, Compare,
    ImageReference, ImportReference, ExportFeature, ExportPreview, ImageEnroll,
    RefreshGallery, NextPage, DeletePerson, UpdatePerson, ImportJson, ExportJson,
    ImportImages, PickSearchImage, SearchImageAgain, GoGallery, SearchGuide, SaveEnrollment, ReleaseMemory, People, Status = kStatusControl, Metrics, Primary,
    SearchResults, SearchCaption, CopySearch, Back = kBackControl, Parameters = kParametersControl, HomePrevious = kHomePreviousControl, HomeNext = kHomeNextControl,
    QueryId = 920, LookupPerson, ClearQuery, GalleryMenu, ConfirmReplacement, ResetSearch, CancelSettings, ImportSynthetic, SaveReference, ReferenceChoice, ShowFlowResult,
    HomeVersion = 4998, WebsiteToast, ParameterPane = 5000, NavBase = 6000, HomeBase = 7000
};
constexpr int kLabelOffset = 1000;
RECT workingArea(HWND window) {
    MONITORINFO monitor{}; monitor.cbSize = sizeof(monitor);
    if (GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY), &monitor)) return monitor.rcWork;
    RECT area{}; SystemParametersInfoW(SPI_GETWORKAREA, 0, &area, 0); return area;
}
LandscapeSize landscapeWindow(HWND window,int width,int height){
    const UINT dpi=GetDpiForWindow(window)?GetDpiForWindow(window):96;
    RECT frame{};AdjustWindowRectExForDpi(&frame,static_cast<DWORD>(GetWindowLongPtrW(window,GWL_STYLE)),FALSE,static_cast<DWORD>(GetWindowLongPtrW(window,GWL_EXSTYLE)),dpi);
    const int dx=frame.right-frame.left,dy=frame.bottom-frame.top;const auto work=workingArea(window);
    const auto size=landscapeSize(MulDiv(std::max(1,width-dx),96,dpi),MulDiv(std::max(1,height-dy),96,dpi),MulDiv(std::max(1,static_cast<int>(work.right-work.left)-dx),96,dpi),MulDiv(std::max(1,static_cast<int>(work.bottom-work.top)-dy),96,dpi));
    return {MulDiv(size.width,dpi,96)+dx,MulDiv(size.height,dpi,96)+dy};
}
// UI owns controls and editable drafts; App owns native resources on its worker.
// UI 持有控件和每页草稿，App 工作线程持有 SDK/相机/数据库资源。
struct Ui {
    struct Draft {
        std::wstring max_faces = L"3", threshold = L"0.80", actions = L"2,1,0", interval = L"0", timeout = L"3000";
        std::wstring id = L"person-001", group, tag;
        int action_preset = 1, search_mode = 0;
        bool silent = true, multiple = true, detailed = true;
    };
    Theme theme;
    ImageSearchView image_search;
    HWND pane = nullptr;
    RECT canvas{}, parameters{};
    int scroll = 0, content_height = 0, view_height = 0;
    uint64_t pending_command = 0, search_request_generation = 0;
    bool creating = true, dirty = false, rendering_list = false;
    Page page = Page::Home;
    PageHistory history;
    bool parameters_open = false;
    bool capture_preview = false;
    uint64_t handled_conflict = 0, handled_flow_completion = 0;
    std::vector<std::string> rendered_reference_ids;
    bool comparison_score_visible = false;
    uint64_t close_settings_after = 0;
    bool gallery_append_queued = false;
    bool metadata_editor_open = false;
    int home_scroll = 0;
    uint64_t return_after_save = 0, return_after_reference = 0;
    unsigned initial_camera = 0;
    uint64_t rendered_gallery = UINT64_MAX;
    uint32_t rendered_offset = UINT32_MAX;
    std::vector<Person> rendered_people;
    std::array<Draft, kPageCount> drafts;
    std::wstring parameter_notice;
    std::wstring last_search_results;
    bool search_overlay_fresh = false;
    int card_top = 160, main_left = 24, parameter_width = 296;
    // Last member dies first: stop/join even on exceptions before releasing UI state.
    // 最后声明、最先析构：异常退出也先停止工作线程，再释放主题与页面状态。
    App app;
};
HWND child(HWND window, int id) {
    if (const auto direct = GetDlgItem(window, id)) return direct;
    return GetDlgItem(GetDlgItem(window, ParameterPane), id);
}
LRESULT send(HWND window, int id, UINT message, WPARAM wparam, LPARAM lparam) { return SendMessageW(child(window, id), message, wparam, lparam); }
std::wstring text(HWND window, int id) {
    HWND control = child(window, id);
    const auto length = GetWindowTextLengthW(control);
    std::wstring value(static_cast<size_t>(length) + 1, L'\0');
    GetWindowTextW(control, value.data(), length + 1); value.resize(length); return value;
}
void setText(HWND window, int id, const std::wstring& value) { SetWindowTextW(child(window, id), value.c_str()); }
bool checked(HWND window, int id) { return send(window, id, BM_GETCHECK, 0, 0) == BST_CHECKED; }
void checkBox(HWND window, int id, bool value) { send(window, id, BM_SETCHECK, value ? BST_CHECKED : BST_UNCHECKED, 0); }
int selection(HWND window, int id) { return static_cast<int>(send(window, id, CB_GETCURSEL, 0, 0)); }
unsigned integer(HWND window, int id, unsigned minimum, unsigned maximum) {
    try {
        const auto value = text(window, id); size_t end = 0;
        const auto parsed = std::stoul(value, &end);
        if (end == value.size() && parsed >= minimum && parsed <= maximum) return static_cast<unsigned>(parsed);
    } catch (const std::exception&) {}
    throw std::runtime_error(utf8(text(window, id + kLabelOffset) + L"：请输入 " + std::to_wstring(minimum) + L"–" + std::to_wstring(maximum) + L" 范围内的整数。"));
}
float threshold(HWND window) {
    try {
        const auto value = text(window, Threshold); size_t end = 0;
        const float parsed = std::stof(value, &end);
        if (end == value.size() && std::isfinite(parsed) && parsed >= 0 && parsed <= 1) return parsed;
    } catch (const std::exception&) {}
    throw std::runtime_error(u8"相似度阈值：请输入 0–1 范围内的数字。");
}
HWND control(Ui& ui, const wchar_t* type, const wchar_t* label, int id, DWORD style = 0) {
    if (std::wstring(type) == L"STATIC") style |= SS_NOPREFIX;
    HWND value = CreateWindowExW(std::wstring(type) == L"EDIT" || std::wstring(type) == L"LISTBOX" ? WS_EX_CLIENTEDGE : 0,
        type, label, WS_CHILD | WS_VISIBLE | style, 0, 0, 10, 10, ui.app.window,
        reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr), nullptr);
    if (!value) throw std::runtime_error("Cannot create Demo controls");
    ui.theme.style(value); return value;
}
void field(Ui& ui, int id, const wchar_t* label, const wchar_t* initial) {
    control(ui, L"STATIC", label, id + kLabelOffset);
    const auto edit = control(ui, L"EDIT", initial, id, ES_AUTOHSCROLL | WS_TABSTOP);
    SendMessageW(edit, EM_SETLIMITTEXT, id == PersonId || id == Group || id == Tag ? 256 : 32, 0);
}
void combo(Ui& ui, int id, std::initializer_list<const wchar_t*> items) {
    const auto box = control(ui, L"COMBOBOX", L"", id, CBS_DROPDOWNLIST | WS_VSCROLL | WS_TABSTOP);
    for (const auto item : items) SendMessageW(box, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(item));
    SendMessageW(box, CB_SETCURSEL, 0, 0);
}
void button(Ui& ui, int id, const wchar_t* label) { control(ui, L"BUTTON", label, id, BS_OWNERDRAW | WS_TABSTOP); }
std::vector<std::filesystem::path> choose(HWND owner, bool save, bool multiple, const wchar_t* filter, const wchar_t* extension = nullptr) {
    std::vector<wchar_t> buffer(65536, 0);
    const auto local = executableDirectory() / L"data";
    const auto directory = std::filesystem::is_directory(local) ? local : executableDirectory().parent_path() / L"data";
    OPENFILENAMEW dialog{}; dialog.lStructSize = sizeof(dialog); dialog.hwndOwner = owner;
    dialog.lpstrFilter = filter; dialog.lpstrFile = buffer.data(); dialog.nMaxFile = static_cast<DWORD>(buffer.size());
    dialog.lpstrDefExt = extension; dialog.lpstrInitialDir = directory.c_str();
    dialog.Flags = OFN_EXPLORER | OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST | (save ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST)
        | (multiple ? OFN_ALLOWMULTISELECT : 0);
    if (!(save ? GetSaveFileNameW(&dialog) : GetOpenFileNameW(&dialog))) {
        if (CommDlgExtendedError()) throw std::runtime_error("Windows file picker failed; choose fewer files at once");
        return {};
    }
    std::vector<std::filesystem::path> paths;
    const std::filesystem::path first(buffer.data());
    const wchar_t* next = buffer.data() + wcslen(buffer.data()) + 1;
    if (!multiple || !*next) paths.push_back(first);
    else while (*next) { paths.push_back(first / next); next += wcslen(next) + 1; }
    return paths;
}
constexpr wchar_t kImages[] = L"Images (JPEG/PNG/BMP/TIFF)\0*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff\0All files\0*.*\0";
constexpr wchar_t kJson[] = L"HiFace HF1 dataset (*.json)\0*.json\0";
constexpr wchar_t kFeature[] = L"HiFace HF1 feature (*.hf1;*.txt)\0*.hf1;*.txt\0";
// Camera switching keeps the applied SDK parameters; a draft threshold/action
// must neither block switching nor silently become active with the new device.
// 切换相机沿用已应用的 SDK 参数，不校验或偷偷应用尚未确认的阈值/动作草稿。
void readCameraSettings(Ui& ui, Settings& settings) {
    const auto window = ui.app.window;
    settings.camera_link.clear();
    const int device = selection(window, Device);
    if (device >= 0 && static_cast<size_t>(device) < ui.app.cameras.size()) {
        settings.camera_index = static_cast<unsigned>(device); settings.camera_link = ui.app.cameras[static_cast<size_t>(device)].symbolic_link;
    }
    const int resolution = selection(window, Resolution);
    if (resolution == 1) { settings.width = 1280; settings.height = 720; }
    else if (resolution == 2) { settings.width = 1920; settings.height = 1080; }
    settings.rotation = std::max(0, selection(window, Rotation)) * 90; settings.mirror = checked(window, Mirror);
}
// Validate one immutable command payload. Navigation separately preserves invalid
// draft text so editing errors cannot trap a user on the current page.
// 校验后生成命令参数；导航单独保留无效输入，避免参数错误阻止返回。
Settings readSettings(Ui& ui) {
    const auto window = ui.app.window;
    Settings settings; settings.page = ui.page;
    settings.id = normalizeMetadata(utf8(text(window, PersonId))); settings.group = normalizeMetadata(utf8(text(window, Group))); settings.tag = normalizeMetadata(utf8(text(window, Tag)));
    settings.query_id = normalizeMetadata(utf8(text(window, QueryId)));
    const int reference = selection(window, ReferenceChoice);
    if (reference >= 0 && static_cast<size_t>(reference) < ui.rendered_reference_ids.size()) settings.reference_id = ui.rendered_reference_ids[static_cast<size_t>(reference)];
    if(ui.page==Page::Gallery){settings.group.clear();settings.tag.clear();settings.filter_group.clear();settings.filter_tag.clear();}
    readCameraSettings(ui, settings);
    settings.detailed = checked(window, Details);
    if (ui.page == Page::Detection) settings.detection_max = integer(window, MaxFaces, 1, 10);
    settings.flow.kind = ui.page == Page::Liveness ? FlowKind::Liveness : ui.page == Page::Verification ? FlowKind::Verification : FlowKind::Capture;
    settings.flow.silent_liveness = checked(window, Silent);
    settings.flow.allow_multiple = (ui.page == Page::Verification || ui.page == Page::Liveness) && checked(window, Multiple);
    if (ui.page == Page::Verification) settings.flow.threshold = threshold(window);
    if (ui.page == Page::Verification || ui.page == Page::Liveness) {
        const int preset = selection(window, Actions);
        if (preset == 1) {
            settings.flow.actions = {0, 1, 2, 3};
            std::mt19937 random(GetTickCount()); std::shuffle(settings.flow.actions.begin(), settings.flow.actions.end(), random);
            settings.flow.actions.resize(ui.page == Page::Verification ? 2 : 3);
        } else if (preset >= 2 && preset <= 5) settings.flow.actions = {preset == 2 ? HIFACE_ACTION_BLINK : preset == 3 ? HIFACE_ACTION_NOD_HEAD : preset == 4 ? HIFACE_ACTION_SHAKE_HEAD : HIFACE_ACTION_MOUTH_OPEN};
        else if (preset == 6) settings.flow.actions = {HIFACE_ACTION_BLINK, HIFACE_ACTION_NOD_HEAD};
        else if (preset == 7) {
            std::wistringstream values(text(window, CustomActions)); std::wstring token;
            while (std::getline(values, token, L',')) {
                size_t end = 0; auto action = std::stoi(token, &end);
                if (end != token.size() || action < 0 || action > 3 || settings.flow.actions.size() >= 4)
                    throw std::runtime_error("Custom actions: 0=shake, 1=nod, 2=blink, 3=mouth; at most four comma-separated steps");
                settings.flow.actions.push_back(action);
            }
        }
    }
    if (ui.page == Page::Search) {
        settings.search.multi_face = selection(window, SearchMode) == 1;
        settings.search.liveness = !settings.search.multi_face && checked(window, Silent);
        settings.search.max_faces = settings.search.multi_face ? integer(window, MaxFaces, 1, 5) : 1;
        settings.search.threshold = threshold(window);
        settings.search.interval_ms = integer(window, Interval, 0, 3000); settings.search.timeout_ms = integer(window, Timeout, 1000, 3000);
        settings.search.group = settings.group; settings.search.tag = settings.tag;
        if (settings.search.threshold < .75f || settings.search.threshold > .85f) throw std::runtime_error(u8"搜索相似度阈值：请输入 0.75–0.85 范围内的数字。");
    }
    return settings;
}
// Validate/persist the draft before enqueueing. The queue advances the view epoch
// only on successful admission, so invalid edits cannot silently stop analysis.
// 先校验参数再入队，成功入队才推进代次，避免错误输入静默停止当前分析。
void submit(Ui& ui, Action action, std::vector<std::filesystem::path> files = {}) {
    const bool independent = action == Action::Cancel || action == Action::CloseCamera || action == Action::Pause
        || action == Action::NextPage || action == Action::ReleaseMemory
        || action == Action::ExportPreview || action == Action::ExportFeature;
    auto settings = independent ? ui.app.current()->settings : readSettings(ui);
    if (action == Action::Pause && !ui.app.current()->paused && ui.dirty)
        ui.parameter_notice = L"搜索已暂停；修改后的参数仍需点击应用修改。";
    if (action == Action::Apply || action == Action::OpenCamera)
        saveCameraPreferences(demoDataDirectory() / L"camera-settings.txt", {settings.width, settings.height, settings.rotation, settings.mirror});
    ui.pending_command = ui.app.enqueue({action, std::move(settings), std::move(files), 0});
    if (action == Action::SearchPhoto || action == Action::SearchPhotoAgain)
        ui.search_request_generation = ui.app.generation;
    if (action == Action::Apply && ui.page == Page::Search && ui.parameters_open) ui.close_settings_after = ui.pending_command;
    if (action != Action::Pause) ui.parameter_notice.clear();
    if (action == Action::Apply || action == Action::OpenCamera) ui.dirty = false;
}
void refreshDevices(Ui& ui) {
    const auto index = selection(ui.app.window, Device);
    const auto old = index >= 0 && static_cast<size_t>(index) < ui.app.cameras.size() ? ui.app.cameras[static_cast<size_t>(index)].symbolic_link : std::wstring();
    ui.app.cameras = Camera::devices(); const auto box = child(ui.app.window, Device);
    SendMessageW(box, CB_RESETCONTENT, 0, 0);
    size_t selected = ui.app.cameras.empty() ? 0 : std::min(static_cast<size_t>(ui.initial_camera), ui.app.cameras.size() - 1);
    for (size_t i = 0; i < ui.app.cameras.size(); ++i) {
        SendMessageW(box, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(ui.app.cameras[i].name.c_str()));
        if (ui.app.cameras[i].symbolic_link == old) selected = i;
    }
    if (!ui.app.cameras.empty()) SendMessageW(box, CB_SETCURSEL, selected, 0);
    writeLog("Enumerated cameras=" + std::to_string(ui.app.cameras.size()));
}
std::optional<Person> selectedPerson(Ui& ui) {
    const auto state = ui.app.current();
    if (ui.page != Page::Gallery || state->settings.page != Page::Gallery || state->view_generation != ui.app.generation
        || state->busy || ui.pending_command || ui.gallery_append_queued || state->fatal) return {};
    const int index = ListView_GetNextItem(child(ui.app.window,People),-1,LVNI_SELECTED);
    if (index < 0 || static_cast<size_t>(index) >= ui.rendered_people.size()) return {};
    return ui.rendered_people[static_cast<size_t>(index)];
}
void prefetchGallery(Ui& ui) {
    const auto state=ui.app.current();
    if (ui.page!=Page::Gallery || ui.metadata_editor_open || !state->gallery_more || state->busy || state->fatal || state->error || ui.pending_command || ui.gallery_append_queued
        || state->view_generation!=ui.app.generation || ui.rendered_people.empty()) return;
    const auto list=child(ui.app.window,People);
    if (ListView_GetTopIndex(list)+ListView_GetCountPerPage(list) < static_cast<int>(ui.rendered_people.size())-10) return;
    ui.gallery_append_queued=true;
    PostMessageW(ui.app.window,WM_COMMAND,MAKEWPARAM(NextPage,BN_CLICKED),0);
}
void galleryMenu(Ui& ui, POINT position) {
    const auto menu=CreatePopupMenu(); if (!menu) throw std::runtime_error("Cannot create library menu");
    struct Cleanup { HMENU value; ~Cleanup(){DestroyMenu(value);} } cleanup{menu};
    const bool selected=selectedPerson(ui).has_value();
    const UINT flags=MF_STRING | (selected?MF_ENABLED:MF_GRAYED);
    AppendMenuW(menu,flags,UpdatePerson,L"编辑所选人员资料…"); AppendMenuW(menu,flags,DeletePerson,L"删除所选人员…");
    AppendMenuW(menu,MF_SEPARATOR,0,nullptr);
    AppendMenuW(menu,MF_STRING,RefreshGallery,L"刷新当前查询");
    if(std::filesystem::is_regular_file(executableDirectory()/L"data/features_10000.json")||std::filesystem::is_regular_file(executableDirectory().parent_path()/L"data/features_10000.json"))
        AppendMenuW(menu,MF_STRING,ImportSynthetic,L"导入演示特征（10000 条）…");
    AppendMenuW(menu,MF_STRING,ImportJson,L"导入 HF1 JSON…"); AppendMenuW(menu,MF_STRING,ImportImages,L"导入本地图片…");
    AppendMenuW(menu,MF_STRING,ExportJson,L"导出全库 HF1 JSON…"); AppendMenuW(menu,MF_STRING,ReleaseMemory,L"释放人脸库缓存");
    const auto command=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_RIGHTBUTTON,position.x,position.y,0,ui.app.window,nullptr);
    if(command)PostMessageW(ui.app.window,WM_COMMAND,MAKEWPARAM(command,BN_CLICKED),0);
}
struct MetadataEditor { Ui* ui; Person person; uint64_t saving=0; };
INT_PTR CALLBACK metadataProcedure(HWND dialog, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* editor=reinterpret_cast<MetadataEditor*>(GetWindowLongPtrW(dialog,DWLP_USER));
    if(message==WM_INITDIALOG){
        editor=reinterpret_cast<MetadataEditor*>(lparam);SetWindowLongPtrW(dialog,DWLP_USER,lparam);
        auto& theme=editor->ui->theme; auto px=[&](int value){return theme.px(value);};
        const auto add=[&](const wchar_t* type,const wchar_t* value,int id,int x,int y,int w,int h,DWORD style){
            const auto field=CreateWindowExW(std::wstring(type)==L"EDIT"?WS_EX_CLIENTEDGE:0,type,value,WS_CHILD|WS_VISIBLE|style,
                px(x),px(y),px(w),px(h),dialog,reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),GetModuleHandleW(nullptr),nullptr);
            theme.style(field);if(std::wstring(type)==L"EDIT")SendMessageW(field,EM_SETLIMITTEXT,256,0);
        };
        RECT parent{};GetWindowRect(editor->ui->app.window,&parent);
        SetWindowPos(dialog,nullptr,parent.left+(parent.right-parent.left-px(480))/2,parent.top+(parent.bottom-parent.top-px(310))/2,px(480),px(310),SWP_NOZORDER);
        add(L"STATIC",(L"Face ID: "+widen(editor->person.id)).c_str(),0,20,20,420,40,SS_NOPREFIX);
        add(L"STATIC",L"分组",0,20,68,70,28,0);add(L"EDIT",widen(editor->person.group).c_str(),10,100,68,330,30,ES_AUTOHSCROLL|WS_TABSTOP);
        add(L"STATIC",L"标签",0,20,112,70,28,0);add(L"EDIT",widen(editor->person.tag).c_str(),11,100,112,330,30,ES_AUTOHSCROLL|WS_TABSTOP);
        add(L"BUTTON",L"保存",IDOK,240,190,90,34,BS_DEFPUSHBUTTON|WS_TABSTOP);add(L"BUTTON",L"取消",IDCANCEL,340,190,90,34,WS_TABSTOP);
        return TRUE;
    }
    if(!editor)return FALSE;
    if(message==WM_COMMAND && LOWORD(wparam)==IDOK && !editor->saving){
        try {
            const auto read=[&](int id){const auto field=GetDlgItem(dialog,id);std::wstring value(static_cast<size_t>(GetWindowTextLengthW(field))+1,L'\0');GetWindowTextW(field,value.data(),static_cast<int>(value.size()));value.resize(wcslen(value.c_str()));return normalizeMetadata(utf8(value));};
            auto settings=editor->ui->app.current()->settings;settings.id=editor->person.id;settings.group=read(10);settings.tag=read(11);
            EnrollmentDraft::validateMetadata(settings.id,settings.group,settings.tag);
            editor->saving=editor->ui->app.enqueue({Action::UpdatePerson,std::move(settings),{},0});
            for(int id:{10,11,IDOK,IDCANCEL})EnableWindow(GetDlgItem(dialog,id),FALSE);
            SetTimer(dialog,1,50,nullptr);
        }catch(const std::exception& error){MessageBoxW(dialog,widen(error.what()).c_str(),L"保存失败",MB_OK|MB_ICONERROR);}
        return TRUE;
    }
    if(message==WM_TIMER && editor->saving){
        const auto state=editor->ui->app.current();
        if(state->fatal||state->completed_command>=editor->saving){
            KillTimer(dialog,1);editor->saving=0;
            if(!state->error&&!state->fatal){EndDialog(dialog,IDOK);return TRUE;}
            for(int id:{10,11,IDOK,IDCANCEL})EnableWindow(GetDlgItem(dialog,id),TRUE);
            if(state->fatal)EnableWindow(GetDlgItem(dialog,IDOK),FALSE);
            MessageBoxW(dialog,widen(state->update.message).c_str(),L"保存失败，可修改后重试",MB_OK|MB_ICONERROR);
        }
        return TRUE;
    }
    if(message==WM_CLOSE || (message==WM_COMMAND&&LOWORD(wparam)==IDCANCEL)){if(!editor->saving)EndDialog(dialog,IDCANCEL);return TRUE;}
    return FALSE;
}
void editMetadata(Ui& ui,const Person& person){
    ui.metadata_editor_open=true;
    struct EditorScope{Ui& ui;~EditorScope(){ui.metadata_editor_open=false;}} scope{ui};
    std::vector<WORD> storage(128,0);auto* form=reinterpret_cast<DLGTEMPLATE*>(storage.data());
    form->style=WS_POPUP|WS_CAPTION|WS_SYSMENU|DS_MODALFRAME;form->cx=300;form->cy=180;
    auto* title=reinterpret_cast<wchar_t*>(reinterpret_cast<BYTE*>(form)+sizeof(DLGTEMPLATE)+2*sizeof(WORD));
    std::copy_n(L"编辑人员资料",7,title);
    MetadataEditor editor{&ui,person,0};
    if(DialogBoxIndirectParamW(GetModuleHandleW(nullptr),form,ui.app.window,metadataProcedure,reinterpret_cast<LPARAM>(&editor))==-1)
        throw std::runtime_error("Cannot open metadata editor");
}
int primaryAction(Page page) {
    switch (page) {
        case Page::Reference: case Page::Verification: case Page::Liveness: case Page::Enrollment: return StartFlow;
        case Page::Search: return Pause;
        case Page::ImageSearch: return PickSearchImage;
        case Page::Comparison: return Compare;
        case Page::Gallery: return RefreshGallery;
        default: return PickA;
    }
}
const wchar_t* primaryTitle(Page page) {
    switch (page) {
        case Page::Reference: return L"开始采集基准";
        case Page::Verification: return L"开始 1:1 验证";
        case Page::Liveness: return L"开始活体检测";
        case Page::Search: return L"暂停搜索";
        case Page::Enrollment: return L"开始 / 重新采集";
        case Page::ImageSearch: return L"选择图片并搜索";
        case Page::Comparison: return L"开始图片比对";
        case Page::Gallery: return L"筛选并刷新人脸库";
        default: return L"选择图片并检测";
    }
}
HomeLayout homeGeometry(const Ui& ui) {
    RECT client{}; GetClientRect(ui.app.window,&client);
    return {MulDiv(client.right,96,ui.theme.dpi),MulDiv(client.bottom,96,ui.theme.dpi),kFeatureCount};
}
// Lay out in logical pixels, then scale once for the current monitor DPI.
// Capture confirmation actions stay outside the scrolling parameter pane.
// 先用逻辑像素布局，再统一按 DPI 缩放；采集确认操作不随参数区滚动。
void layout(Ui& ui) {
    if(!ui.pane)return;
    const auto window=ui.app.window;RECT client{};GetClientRect(window,&client);
    const int width=MulDiv(client.right,96,ui.theme.dpi),height=MulDiv(client.bottom,96,ui.theme.dpi);
    auto px=[&](int v){return ui.theme.px(v);};
    auto rect=[&](int x,int y,int w,int h){return RECT{px(x),px(y),px(x+w),px(y+h)};};
    auto move=[&](int id,int x,int y,int w,int h=34){MoveWindow(child(window,id),px(x),px(y),px(std::max(1,w)),px(std::max(1,h)),TRUE);};
    const bool home=ui.page==Page::Home,gallery=ui.page==Page::Gallery,comparison=ui.page==Page::Comparison,settings=ui.page==Page::CameraSettings;
    const bool capture=ui.page==Page::Reference||ui.page==Page::Enrollment;
    const bool pane=!home&&!gallery&&!comparison&&!settings&&ui.page!=Page::ImageSearch&&(!capture||ui.capture_preview)&&(!hasFeatureParameters(ui.page)||ui.parameters_open);
    ui.main_left=24;ui.parameter_width=width<1100?272:296;
    for(int id:{PickA,PickB,ImageEnroll,ImageReference,ImportReference,StartFlow}){
        const bool footer=id==StartFlow&&capture&&ui.capture_preview;
        const bool direct=footer||(((capture&&!ui.capture_preview)||comparison)&&id!=StartFlow);
        const auto parent=direct?window:ui.pane;const auto control=child(window,id);
        if(GetParent(control)!=parent)SetParent(control,parent);
    }
    for(int id=PersonId;id<=ReleaseMemory;++id){ShowWindow(child(window,id),SW_HIDE);ShowWindow(child(window,id+kLabelOffset),SW_HIDE);}
    for(int id:{Device,RefreshDevices,Open,Close,Resolution,Rotation,Mirror,Apply,People,Enroll,GoGallery,Parameters,SearchImageAgain,HomePrevious,HomeNext,SearchResults,SearchCaption,CopySearch,QueryId,LookupPerson,ClearQuery,GalleryMenu,ResetSearch,CancelSettings,ReferenceChoice,SaveReference})ShowWindow(child(window,id),SW_HIDE);
    for(int i=0;i<kFeatureCount;++i)ShowWindow(child(window,HomeBase+i),SW_HIDE);
    move(Back,24,18,82);ShowWindow(child(window,Back),home?SW_HIDE:SW_SHOW);
    move(Logs,width-204,18,64);move(Help,width-128,18,104);ShowWindow(child(window,Help),home?SW_HIDE:SW_SHOW);
    move(HomeVersion,width-274,height-50,250);ShowWindow(child(window,HomeVersion),home?SW_SHOW:SW_HIDE);
    move(WebsiteToast,width/2-180,height-116,360);
    ShowWindow(ui.pane,pane?SW_SHOW:SW_HIDE);
    ShowWindow(child(window,Primary),home||gallery||settings?SW_HIDE:SW_SHOW);
    ShowWindow(child(window,Cancel),home||gallery||settings||comparison||ui.page==Page::Search?SW_HIDE:SW_SHOW);
    move(Status,32,height-29,std::max(1,width/2-48),22);move(Metrics,width/2,height-29,width/2-24,22);
    if(home){
        const auto view=homeGeometry(ui);ui.home_scroll=view.clampScroll(ui.home_scroll);
        for(int i=0;i<kFeatureCount;++i){
            const auto area=view.card(i,ui.home_scroll),visible=view.visible(i,ui.home_scroll);
            move(HomeBase+i,area.left,area.top,area.width(),area.height());const auto handle=child(window,HomeBase+i);
            if(visible.height()){const auto region=CreateRectRgn(0,px(visible.top-area.top),px(area.width()),px(visible.bottom-area.top));if(!SetWindowRgn(handle,region,TRUE))DeleteObject(region);ShowWindow(handle,SW_SHOW);}
        }
        if(view.clampScroll(100000)>0){move(HomePrevious,32,height-58,92,30);move(HomeNext,136,height-58,92,30);ShowWindow(child(window,HomePrevious),SW_SHOW);ShowWindow(child(window,HomeNext),SW_SHOW);}
        EnableWindow(child(window,HomePrevious),ui.home_scroll>0);
        EnableWindow(child(window,HomeNext),ui.home_scroll<view.clampScroll(100000));
        move(Status,32,height-29,std::max(1,width-320),22);
        ui.image_search.layout({},false);return;
    }
    ToolbarLayout toolbar(32,width-24,86);
    auto tool=[&](int id,int w){const auto area=toolbar.place(w);move(id,area.left,area.top,area.width(),id==Device||id==ReferenceChoice||id==Resolution||id==Rotation?280:34);ShowWindow(child(window,id),SW_SHOW);};
    const bool camera=usesCamera(ui.page)&&!(capture&&ui.capture_preview);
    if(camera){
        tool(Device,width<1100?180:224);tool(RefreshDevices,48);
        const auto area=toolbar.place(104);move(Open,area.left,area.top,area.width());move(Close,area.left,area.top,area.width());
        const bool opened=ui.app.current()->settings.page==ui.page&&ui.app.current()->camera_open;
        ShowWindow(child(window,opened?Close:Open),SW_SHOW);
    }
    if(settings){tool(Resolution,116);tool(Rotation,108);tool(Mirror,104);}
    if(ui.page==Page::Search){tool(Enroll,104);tool(GoGallery,104);}
    if(ui.page==Page::ImageSearch)tool(GoGallery,104);
    if(ui.page==Page::Verification){if(ui.rendered_reference_ids.empty())tool(GoGallery,124);else tool(ReferenceChoice,width<1100?220:280);}
    if(hasFeatureParameters(ui.page))tool(Parameters,104);
    if(capture&&!ui.capture_preview){tool(PickA,136);tool(ui.page==Page::Enrollment?ImageEnroll:ImageReference,136);if(ui.page==Page::Reference)tool(ImportReference,116);}
    if(comparison){tool(PickA,144);tool(PickB,144);}
    if(gallery){tool(QueryId,std::max(180,width-338));tool(LookupPerson,72);tool(ClearQuery,64);tool(GalleryMenu,72);}
    setText(window,GoGallery,ui.page==Page::Verification?L"先采集基准":L"人脸库");
    ui.card_top=toolbar.y+50;const int left=pane?ui.main_left+ui.parameter_width+16:ui.main_left;
    const int bottom=comparison?height-(ui.comparison_score_visible?132:90):height-94;
    ui.parameters=rect(24,ui.card_top,ui.parameter_width,std::max(1,height-48-ui.card_top));
    ui.canvas=rect(left,ui.card_top,std::max(1,width-left-24),std::max(1,bottom-ui.card_top));
    const int form_top=ui.card_top+(ui.page==Page::Search&&pane?84:40);
    const int form_bottom=height-(hasFeatureParameters(ui.page)&&pane?104:56);
    ui.view_height=std::max(1,form_bottom-form_top);
    MoveWindow(ui.pane,px(34),px(form_top),px(ui.parameter_width-20),px(ui.view_height),TRUE);
    int y=4;
    auto row=[&](int id,bool labelled=true){
        ShowWindow(child(window,id),SW_SHOW);
        if(labelled&&child(window,id+kLabelOffset)){
            ShowWindow(child(window,id+kLabelOffset),SW_SHOW);move(id+kLabelOffset,8,y-ui.scroll,ui.parameter_width-54,20);move(id,8,y+22-ui.scroll,ui.parameter_width-54,32);y+=64;
        }else{move(id,8,y-ui.scroll,ui.parameter_width-54,id==SearchMode||id==Actions?280:34);y+=42;}
    };
    if(capture&&ui.capture_preview){move(SearchGuide,8,y-ui.scroll,ui.parameter_width-54,62);ShowWindow(child(window,SearchGuide),SW_SHOW);y+=72;row(PersonId);if(ui.page==Page::Enrollment){row(Group);row(Tag);}}
    switch(ui.page){
        case Page::Detection:row(MaxFaces);row(Details,false);break;
        case Page::Reference:if(ui.capture_preview){row(PickA,false);row(ImageReference,false);row(ImportReference,false);row(ExportPreview,false);}break;
        case Page::Enrollment:if(ui.capture_preview){row(PickA,false);row(ImageEnroll,false);}break;
        case Page::Verification:row(Threshold);row(Actions,false);if(selection(window,Actions)==7)row(CustomActions);row(Silent,false);row(Multiple,false);row(ExportFeature,false);break;
        case Page::Liveness:row(Actions,false);if(selection(window,Actions)==7)row(CustomActions);row(Multiple,false);row(ExportPreview,false);break;
        case Page::Search:row(SearchMode,false);if(selection(window,SearchMode)==1)row(MaxFaces);else row(Silent,false);row(Threshold);row(Group);row(Tag);row(Interval);row(Timeout);break;
        default:break;
    }
    ui.content_height=y;const int next=std::clamp(ui.scroll,0,std::max(0,y-ui.view_height));
    if(next!=ui.scroll){ui.scroll=next;layout(ui);return;}
    SCROLLINFO info{sizeof(info),SIF_RANGE|SIF_PAGE|SIF_POS,0,std::max(0,y-1),static_cast<UINT>(ui.view_height),ui.scroll,0};SetScrollInfo(ui.pane,SB_VERT,&info,TRUE);
    if(hasFeatureParameters(ui.page)&&pane){move(Apply,40,height-94,ui.parameter_width-32);ShowWindow(child(window,Apply),SW_SHOW);}
    if(ui.page==Page::Search&&pane){const int half=(ui.parameter_width-40)/2;move(ResetSearch,40,ui.card_top+40,half,30);move(CancelSettings,48+half,ui.card_top+40,half,30);ShowWindow(child(window,ResetSearch),SW_SHOW);ShowWindow(child(window,CancelSettings),SW_SHOW);}
    const int action_width=std::max(1,width-left-40),slot=std::min(220,action_width/3);
    move(Primary,left+8,height-76,slot);move(Cancel,left+slot+20,height-76,std::min(144,slot));
    if(capture&&ui.capture_preview){move(StartFlow,left+slot+20,height-76,std::min(132,slot));move(Cancel,left+slot*2+32,height-76,std::min(132,slot));ShowWindow(child(window,StartFlow),SW_SHOW);}
    if(ui.page==Page::ImageSearch){move(SearchImageAgain,left+slot+20,height-76,slot);ShowWindow(child(window,SearchImageAgain),SW_SHOW);move(Cancel,left+slot*2+32,height-76,slot);}
    if(comparison)move(Primary,32,height-68,std::max(1,width-64));
    if(ui.page==Page::Search){
        const int details=64;ui.canvas.bottom-=px(details);move(SearchCaption,left+8,bottom-details+2,std::max(1,width-left-116),28);move(CopySearch,width-96,bottom-details+2,68,28);move(SearchResults,left+8,bottom-details+32,std::max(1,width-left-40),28);
        for(int id:{SearchCaption,SearchResults,CopySearch})ShowWindow(child(window,id),SW_SHOW);
        for(int id:{SearchCaption,SearchResults})SendMessageW(child(window,id),WM_SETFONT,reinterpret_cast<WPARAM>(ui.theme.body),TRUE);
    }
    if(gallery){ui.canvas=rect(24,ui.card_top,width-48,height-ui.card_top-48);move(People,32,ui.card_top+44,width-64,height-ui.card_top-102);ShowWindow(child(window,People),SW_SHOW);}
    const int columns[]={std::max(180,width-550),120,140,190};for(int i=0;i<4;++i)ListView_SetColumnWidth(child(window,People),i,px(columns[i]));
    setText(window,MaxFaces+kLabelOffset,ui.page==Page::Search?L"最多人脸（1–5）":L"最多人脸（1–10）");
    setText(window,Group+kLabelOffset,ui.page==Page::Search?L"搜索范围分组（留空为全部）":L"人员分组");
    setText(window,Tag+kLabelOffset,ui.page==Page::Search?L"搜索范围标签（留空为全部）":L"人员标签");
    setText(window,Threshold+kLabelOffset,ui.page==Page::Search?L"相似度阈值（0.75–0.85）":L"相似度阈值（0–1）");
    setText(window,Primary,primaryTitle(ui.page));setText(window,StartFlow,capture&&ui.capture_preview?L"重新采集":primaryTitle(ui.page));
    setText(window,PickA,ui.page==Page::Detection?L"选择图片并检测":ui.page==Page::Enrollment?L"选择待录入图片":ui.page==Page::Comparison?L"选择图片 A":L"选择基准图片");
    ui.image_search.layout(ui.canvas,ui.page==Page::ImageSearch);InvalidateRect(ui.pane,nullptr,TRUE);
}
void scrollHome(Ui& ui,int position){ui.home_scroll=homeGeometry(ui).clampScroll(position);layout(ui);InvalidateRect(ui.app.window,nullptr,TRUE);}
std::wstring updatedTime(int64_t milliseconds) {
    if (milliseconds <= 0 || milliseconds > INT64_C(253402300799999)) return L"—";
    ULARGE_INTEGER ticks{}; ticks.QuadPart = (static_cast<ULONGLONG>(milliseconds) + 11644473600000ULL) * 10000ULL;
    FILETIME file{ticks.LowPart, ticks.HighPart}; SYSTEMTIME utc{}, local{};
    if (!FileTimeToSystemTime(&file, &utc) || !SystemTimeToTzSpecificLocalTime(nullptr, &utc, &local)) return L"—";
    std::wostringstream value; value << std::setfill(L'0') << local.wYear << L"-" << std::setw(2) << local.wMonth << L"-" << std::setw(2) << local.wDay
        << L" " << std::setw(2) << local.wHour << L":" << std::setw(2) << local.wMinute << L":" << std::setw(2) << local.wSecond;
    return value.str();
}
// Render a worker snapshot. Only matching page/request generations may expose
// identities or schedule a confirmation/result dialog. No SDK calls occur here.
// 仅根据快照更新 UI；页面/请求代次匹配后才显示身份或弹窗，此处不调用 SDK。
void update(Ui& ui) {
    const auto state = ui.app.current(); const auto window = ui.app.window;
    const bool current_view = state->view_generation == ui.app.generation && state->settings.page == ui.page;
    ui.search_overlay_fresh = searchOverlayFresh(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count(), state->preview_at_ms, state->analysis_at_ms);
    if (ui.page == Page::Gallery) ShowWindow(child(window,People),current_view?SW_SHOW:SW_HIDE);
    const bool preview = current_view && ((ui.page == Page::Enrollment && state->pending_enrollment) || (ui.page == Page::Reference && state->pending_reference));
    if (ui.comparison_score_visible != (state->comparison_similarity.has_value()||(state->error&&ui.page==Page::Comparison))) {ui.comparison_score_visible=state->comparison_similarity.has_value()||(state->error&&ui.page==Page::Comparison);layout(ui);}
    if(ui.rendered_reference_ids!=state->reference_ids){
        const bool creating=ui.creating;ui.creating=true;
        const int previous=selection(window,ReferenceChoice);
        const auto id=previous>=0&&static_cast<size_t>(previous)<ui.rendered_reference_ids.size()?ui.rendered_reference_ids[static_cast<size_t>(previous)]:std::string();
        ui.rendered_reference_ids=state->reference_ids;send(window,ReferenceChoice,CB_RESETCONTENT,0,0);
        int selected=-1;
        for(size_t i=0;i<ui.rendered_reference_ids.size();++i){const auto value=widen(ui.rendered_reference_ids[i]);send(window,ReferenceChoice,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(value.c_str()));if(ui.rendered_reference_ids[i]==id)selected=static_cast<int>(i);}
        send(window,ReferenceChoice,CB_SETCURSEL,selected,0);ui.creating=creating;layout(ui);
    }
    if (ui.capture_preview != preview) { ui.capture_preview = preview; layout(ui); }
    setText(window, Status, ui.page==Page::Home&&!state->error&&!state->fatal?L"人脸数据在本机处理与保存":ui.parameter_notice.empty() ? widen(state->update.message) : ui.parameter_notice);
    ShowWindow(child(window,Metrics),ui.page==Page::Home||ui.page==Page::Search||ui.page==Page::Comparison?SW_HIDE:SW_SHOW);
    ShowWindow(child(window,Status),ui.page==Page::Search||ui.page==Page::Comparison?SW_HIDE:SW_SHOW);
    std::wostringstream metrics;
    metrics << L"人脸库 " << state->total << L" 条 | 采集基准 " << state->reference_ids.size() << L" 份";
    if(ui.page==Page::Detection)metrics << L" | 当前人脸 " << state->update.faces.size();
    if(ui.page==Page::Verification&&!state->reference_id.empty())metrics << L" | Face ID: " << widen(state->reference_id);
    if (ui.page == Page::Search) metrics << L" | 当前搜索范围 " << state->search_population << L" 条";
    if (state->camera_open) metrics << std::fixed << std::setprecision(1) << L" | 采集 " << state->capture_fps << L" FPS | 分析 " << state->analysis_fps << L" FPS | 推理 " << state->inference_ms << L" ms";
    if (ui.page == Page::Gallery) metrics << L" | 已加载 " << (current_view ? state->people.size() : 0) << L" / " << state->filtered << L" 条";
    setText(window, Metrics, metrics.str());
    if (state->completed_command >= ui.pending_command) ui.pending_command = 0;
    if (state->fatal) { ui.pending_command=ui.return_after_save=ui.return_after_reference=ui.close_settings_after=0; }
    const bool ready = !state->busy && !ui.pending_command && !state->flow_active && !state->fatal;
    for (int id = PersonId; id <= ReleaseMemory; ++id) EnableWindow(child(window, id), ready);
    EnableWindow(child(window, Open), ready && !state->camera_open && !ui.app.cameras.empty() && usesCamera(ui.page));
    const bool camera_tools=usesCamera(ui.page)&&!((ui.page==Page::Reference||ui.page==Page::Enrollment)&&ui.capture_preview);
    ShowWindow(child(window,Open),camera_tools&&(!current_view||!state->camera_open)?SW_SHOW:SW_HIDE);
    ShowWindow(child(window,Close),camera_tools&&current_view&&state->camera_open?SW_SHOW:SW_HIDE);
    EnableWindow(child(window, Close), state->camera_open || state->busy);
    EnableWindow(child(window, StartFlow), ready && (state->camera_open||((ui.page==Page::Reference||ui.page==Page::Enrollment)&&!ui.app.cameras.empty())) && (ui.page != Page::Verification || state->has_reference));
    EnableWindow(child(window, Enroll), ready);
    EnableWindow(child(window, Pause), ready && state->camera_open);
    EnableWindow(child(window, Cancel), state->flow_active || state->busy);
    EnableWindow(child(window, Device),!state->busy&&!ui.pending_command&&!state->fatal&&!state->pending_enrollment&&!state->pending_reference&&(ui.page!=Page::Verification||state->has_reference));
    EnableWindow(child(window, RefreshDevices), ready && !state->camera_open);
    EnableWindow(child(window, Resolution), ready);
    const bool can_navigate = (!state->busy && !ui.pending_command) || ui.page == Page::ImageSearch;
    for (int i = 0; i < kFeatureCount; ++i) EnableWindow(child(window, HomeBase + i), can_navigate && !state->fatal);
    EnableWindow(child(window, Back), TRUE);
    EnableWindow(child(window, Parameters), can_navigate && !state->fatal);
    EnableWindow(child(window, HomePrevious), ui.home_scroll > 0);
    EnableWindow(child(window, HomeNext), ui.home_scroll < homeGeometry(ui).clampScroll(100000));
    EnableWindow(child(window, Apply), ready);
    EnableWindow(child(window, Silent), ready && (ui.page != Page::Search || selection(window, SearchMode) == 0));
    EnableWindow(child(window, MaxFaces), ready && (ui.page != Page::Search || selection(window, SearchMode) == 1));
    EnableWindow(child(window, CustomActions), ready && selection(window, Actions) == 7);
    EnableWindow(child(window, Compare), ready && state->comparison_ready);
    EnableWindow(child(window,SaveReference),ready&&state->pending_reference);
    EnableWindow(child(window,ReferenceChoice),!state->busy&&!ui.pending_command&&!state->fatal);
    if(ui.page==Page::Comparison)for(int id:{PickA,PickB})EnableWindow(child(window,id),!state->fatal);
    EnableWindow(child(window, ImageReference), ready && state->image_a);
    EnableWindow(child(window, ImageEnroll), ready && state->image_a);
    if(ui.page==Page::Enrollment||ui.page==Page::Reference){EnableWindow(child(window,PickA),!state->busy&&!ui.pending_command&&!state->fatal);EnableWindow(child(window,ImportReference),!state->busy&&!ui.pending_command&&!state->fatal);}
    EnableWindow(child(window, SaveEnrollment), ready && state->pending_enrollment);
    EnableWindow(child(window, ExportFeature), ready && state->has_reference);
    EnableWindow(child(window, ExportPreview), ready && state->captured);
    EnableWindow(child(window, NextPage), ready && state->gallery_more);
    EnableWindow(child(window, QueryId), !state->importing && !state->fatal);
    for (int id : {LookupPerson, ClearQuery, GalleryMenu}) EnableWindow(child(window,id), ready);
    EnableWindow(child(window, SearchImageAgain), ready && state->search_photo);
    EnableWindow(child(window, PickSearchImage), !state->fatal && ui.page == Page::ImageSearch);
    EnableWindow(child(window, GoGallery), !state->fatal);
    EnableWindow(child(window, Rotation), ready && ui.page != Page::ImageSearch);
    EnableWindow(child(window, Mirror), ready && ui.page != Page::ImageSearch);
    const bool current_photo = state->settings.page == ui.page && (!ui.search_request_generation || state->search_generation == ui.search_request_generation);
    if (ui.page == Page::ImageSearch) {
        ui.image_search.setState(state->busy || ui.pending_command, state->error || state->fatal,
            current_photo ? widen(state->update.message) : L"正在读取图片并检测人脸…", current_photo ? state->search_file.filename().wstring() : L"");
        if (current_photo) ui.image_search.setContent(state->search_photo, state->image_search);
        else if (!ui.pending_command) ui.image_search.setContent(nullptr, nullptr);
    }
    EnableWindow(child(window, Primary), IsWindowEnabled(child(window, primaryAction(ui.page))));
    EnableWindow(child(window, Cancel), state->flow_active || state->busy || ui.pending_command || state->pending_enrollment || state->pending_reference
        || (ui.page == Page::Search && state->camera_open && !state->paused));
    setText(window, Apply, ui.dirty ? L"应用修改 *" : L"应用参数");
    setText(window, Parameters, ui.parameters_open ? L"收起参数" : ui.dirty ? L"参数设置 *" : L"参数设置");
    for (auto* returning : {&ui.return_after_save, &ui.return_after_reference}) {
        if (*returning && state->completed_command >= *returning) {
            const bool leave = !state->error && !state->fatal &&
                (returning == &ui.return_after_save ? ui.page == Page::Enrollment && !state->pending_enrollment : ui.page == Page::Reference && !state->pending_reference);
            *returning = 0;
            if (leave) PostMessageW(window, WM_COMMAND, MAKEWPARAM(Back, BN_CLICKED), 0);
        }
    }
    if (ui.close_settings_after && state->completed_command >= ui.close_settings_after) {
        ui.close_settings_after = 0;
        if (!state->error && ui.page == Page::Search) { ui.parameters_open = false; layout(ui); }
    }
    if (current_view && state->enrollment_conflict && state->pending_enrollment && !state->busy
        && state->completed_command != ui.handled_conflict) {
        ui.handled_conflict = state->completed_command;
        PostMessageW(window, WM_COMMAND, MAKEWPARAM(ConfirmReplacement, BN_CLICKED), 0);
    }
    if(current_view&&!state->flow_summary.empty()&&(ui.page==Page::Liveness||ui.page==Page::Verification)&&state->flow_completion>ui.handled_flow_completion){
        ui.handled_flow_completion=state->flow_completion;PostMessageW(window,WM_COMMAND,MAKEWPARAM(ShowFlowResult,BN_CLICKED),0);
    }
    if(ui.page==Page::Reference){
        setText(window,SearchGuide,L"核对预览与 Face ID。\r\n确认后保存到独立采集参考库。\r\n已有同名参考将更新。");
        setText(window,Primary,state->pending_reference?L"确认保存":state->camera_open?L"重新采集基准":L"打开摄像头重试");
        EnableWindow(child(window,Primary),ready&&(state->pending_reference||state->camera_open||!ui.app.cameras.empty()));
    }
    if(ui.page==Page::Liveness||ui.page==Page::Verification){
        if(!state->camera_open)setText(window,Primary,L"打开摄像头重试");
        if(!state->camera_open)EnableWindow(child(window,Primary),ready&&!ui.app.cameras.empty()&&(ui.page!=Page::Verification||state->has_reference));
    }
    setText(window, Pause, state->paused ? L"恢复搜索" : L"暂停搜索 / 释放缓存");
    if (ui.page == Page::Search) {
        setText(window, Primary, !state->camera_open ? L"打开摄像头重试" : state->paused ? L"恢复搜索" : L"暂停搜索");
        EnableWindow(child(window,Primary), state->camera_open ? IsWindowEnabled(child(window,Pause)) : ready && !ui.app.cameras.empty());
    }
    if (ui.page == Page::Enrollment) {
        setText(window, SearchGuide, state->pending_enrollment
            ? L"第 2 步 / 共 2 步\r\n核对预览与人员信息，再确认保存。\r\n已有 ID 需再次确认覆盖。"
            : L"第 1 步 / 共 2 步\r\n请正对摄像头，正在引导采集。\r\n采集后确认保存才会入库。");
        setText(window, Primary, state->pending_enrollment ? L"确认保存" : L"开始 / 重新采集");
        EnableWindow(child(window, Primary), ready && (state->pending_enrollment || state->camera_open || !ui.app.cameras.empty()));
        setText(window, Cancel, state->pending_enrollment ? L"丢弃本次预览" : L"取消采集");
    } else setText(window, Cancel, ui.page==Page::Reference&&state->pending_reference?L"丢弃本次预览":ui.page==Page::ImageSearch?L"取消搜索":L"取消流程");
    if (ui.page == Page::Search && !current_view) {
        ui.last_search_results.clear();setText(window,SearchCaption,L"RGB 人脸搜索");setText(window,SearchResults,L"正在切换流程，等待新结果…");
    }
    if (ui.page == Page::Search && current_view) {
        const auto& options = state->settings.search;
        std::wostringstream mode, detail;
        mode << (options.multi_face ? L"M:N · 不检测活体" : options.liveness ? L"1:N · 活体已开启" : L"1:N · 活体未开启");
        mode << std::fixed << std::setprecision(2) << L" | 阈值 " << options.threshold << L" | 范围 " << state->search_population << L" 人";
        if(!options.group.empty())mode << L" | 分组 " << widen(options.group);
        if(!options.tag.empty())mode << L" | 标签 " << widen(options.tag);
        if (state->error || state->fatal) detail << widen(state->update.message);
        else if (!ui.parameter_notice.empty()) detail << ui.parameter_notice;
        else if (ui.dirty) detail << L"参数有未应用修改，请先应用参数。";
        else if (state->paused || !state->camera_open || state->search_population == 0)
            detail << (state->paused ? L"已暂停；恢复后重新识别。" : !state->search_population
                ? L"当前范围没有人员；请录入或检查分组/标签。" : L"打开摄像头开始搜索。");
        else if (!ui.search_overlay_fresh) detail << L"等待新的识别结果…";
        else if (state->update.faces.empty()) detail << widen(state->update.message);
        else {
            const auto best = bestSearchMatchCaption(state->update, !options.multi_face && options.liveness);
            detail << widen(best.empty() ? searchStatusText(state->update) : best);
        }
        const auto full=mode.str()+L"\r\n"+detail.str();
        if(full!=ui.last_search_results){
            ui.last_search_results=full;
            auto line=detail.str();std::replace(line.begin(),line.end(),L'\r',L' ');std::replace(line.begin(),line.end(),L'\n',L' ');
            setText(window,SearchCaption,mode.str());setText(window,SearchResults,line);
        }
    }

    if (ui.page != Page::Gallery || !current_view) { InvalidateRect(window,nullptr,FALSE); return; }
    bool changed = state->total != ui.rendered_gallery || state->offset != ui.rendered_offset || state->people.size() != ui.rendered_people.size();
    if (!changed) for (size_t i = 0; i < state->people.size(); ++i) {
        const auto& a = state->people[i]; const auto& b = ui.rendered_people[i];
        if (a.id != b.id || a.group != b.group || a.tag != b.tag || a.updated != b.updated) { changed = true; break; }
    }
    if (changed) {
        const auto list = child(window, People);
        const auto selected_index = ListView_GetNextItem(list,-1,LVNI_SELECTED);
        const auto selected_id = selected_index >= 0 && static_cast<size_t>(selected_index) < ui.rendered_people.size() ? ui.rendered_people[static_cast<size_t>(selected_index)].id : std::string();
        const int top = ListView_GetTopIndex(list);
        bool append = state->people.size() >= ui.rendered_people.size();
        for (size_t i=0; append && i<ui.rendered_people.size(); ++i) {
            const auto& a=state->people[i]; const auto& b=ui.rendered_people[i];
            append=a.id==b.id && a.group==b.group && a.tag==b.tag && a.updated==b.updated;
        }
        ui.rendering_list = true;
        SendMessageW(list, WM_SETREDRAW, FALSE, 0); if (!append) ListView_DeleteAllItems(list);
        for (size_t index = append ? ui.rendered_people.size() : 0; index < state->people.size(); ++index) {
            const auto& person = state->people[index]; const auto id = widen(person.id);
            LVITEMW item{}; item.mask = LVIF_TEXT; item.iItem = static_cast<int>(index); item.pszText = const_cast<wchar_t*>(id.c_str());
            ListView_InsertItem(list, &item);
            auto group = widen(person.group), tag = widen(person.tag), updated = updatedTime(person.updated);
            ListView_SetItemText(list, item.iItem, 1, group.data()); ListView_SetItemText(list, item.iItem, 2, tag.data()); ListView_SetItemText(list, item.iItem, 3, updated.data());
            if (person.id == selected_id) ListView_SetItemState(list, item.iItem, LVIS_SELECTED, LVIS_SELECTED);
        }
        if (!append && !state->people.empty()) {
            RECT row{};
            if(ListView_GetItemRect(list,0,&row,LVIR_BOUNDS))ListView_Scroll(list,0,std::min(top,static_cast<int>(state->people.size()-1))*(row.bottom-row.top));
        }
        SendMessageW(list, WM_SETREDRAW, TRUE, 0); InvalidateRect(list, nullptr, TRUE);
        ui.rendered_people = state->people; ui.rendered_gallery = state->total; ui.rendered_offset = state->offset; ui.rendering_list = false;
    }
    InvalidateRect(window, nullptr, FALSE);
}
struct Fit { int x = 0, y = 0, width = 0, height = 0; double scale = 0; };
Fit bitmap(HDC dc, const Image& image, const RECT& area) {
    Fit fit; if (image.width <= 0 || image.height <= 0 || image.rgba.empty()) return fit;
    fit.scale = std::min(double(area.right - area.left) / image.width, double(area.bottom - area.top) / image.height);
    fit.width = static_cast<int>(image.width * fit.scale); fit.height = static_cast<int>(image.height * fit.scale);
    fit.x = area.left + (area.right - area.left - fit.width) / 2; fit.y = area.top + (area.bottom - area.top - fit.height) / 2;
    BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER); info.bmiHeader.biWidth = image.width; info.bmiHeader.biHeight = -image.height;
    info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
    SetStretchBltMode(dc, HALFTONE); SetBrushOrgEx(dc, 0, 0, nullptr);
    StretchDIBits(dc, fit.x, fit.y, fit.width, fit.height, 0, 0, image.width, image.height, image.rgba.data(), &info, DIB_RGB_COLORS, SRCCOPY);
    return fit;
}
void paint(Ui& ui) {
    PAINTSTRUCT paint{}; HDC target = BeginPaint(ui.app.window, &paint); RECT client{}; GetClientRect(ui.app.window, &client);
    HDC dc = CreateCompatibleDC(target); const auto buffer = CreateCompatibleBitmap(target, std::max(1L, client.right), std::max(1L, client.bottom));
    const auto old_bitmap = SelectObject(dc, buffer);
    auto px = [&](int value) { return ui.theme.px(value); };
    auto rect = [&](int x, int y, int w, int h) { return RECT{px(x), px(y), px(x + w), px(y + h)}; };
    const bool is_home = ui.page == Page::Home;
    fill(dc, client, is_home ? home_colors::background : colors::background);
    const int logical_width = MulDiv(client.right, 96, ui.theme.dpi);
    const int title_left = ui.page == Page::Home ? 32 : 128;
    label(dc, ui.page == Page::Home ? L"HelloFace SDK" : page_info[static_cast<int>(ui.page)].title, rect(title_left, 18, std::max(1, logical_width - title_left - 244), 38), ui.theme.title, is_home ? home_colors::text : colors::ink, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    label(dc, ui.page == Page::Home ? L"Offline | Private | Fast" : page_info[static_cast<int>(ui.page)].description, rect(ui.main_left + 8, 56, std::max(1, logical_width - ui.main_left - 30), 20), ui.theme.small, is_home ? home_colors::secondary : colors::muted, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    if (IsWindowVisible(ui.pane)) {
        card(dc, ui.parameters, colors::surface, colors::line, px(14));
        label(dc, ui.page==Page::Reference?L"确认采集基准":ui.page==Page::Enrollment?L"核对并确认录入":L"参数与操作", rect(ui.main_left + 18, ui.card_top + 8, ui.parameter_width - 36, 26), ui.theme.body, colors::ink);
    }
    if (ui.page == Page::Home) {
        label(dc, L"选择功能开始体验 · 录入与人脸库在搜索页中", rect(32, 78, logical_width - 56, 22), ui.theme.small, home_colors::secondary);
        const auto home = homeGeometry(ui);
        if (home.clampScroll(100000)) label(dc, L"滚动查看八个功能入口", rect(32, MulDiv(client.bottom, 96, ui.theme.dpi) - 84, logical_width - 64, 20), ui.theme.small, home_colors::secondary);
        BitBlt(target, 0, 0, client.right, client.bottom, dc, 0, 0, SRCCOPY); SelectObject(dc, old_bitmap);
        DeleteObject(buffer); DeleteDC(dc); EndPaint(ui.app.window, &paint); return;
    }
    const auto state = ui.app.current();
    const wchar_t* badge = state->fatal || state->error ? L"发生错误 · 查看下方提示" : state->busy || ui.pending_command ? L"处理中，请稍候…" : state->flow_active ? L"流程进行中" : ui.page == Page::Enrollment && state->pending_enrollment ? L"待确认录入 · 尚未写入人脸库" : ui.page == Page::CameraSettings ? L"相机预览 · 不执行人脸分析" : ui.page == Page::ImageSearch ? L"图片搜索 · 无需摄像头" : state->camera_open ? state->paused ? L"摄像头已连接 · 搜索暂停" : L"摄像头已连接" : L"摄像头未打开";
    RECT badge_area{ui.canvas.left + px(10), ui.canvas.top - px(32), ui.canvas.right, ui.canvas.top - px(6)};
    label(dc, badge, badge_area, ui.theme.small, state->error || state->fatal ? colors::error : colors::muted, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    RECT area = ui.canvas;
    card(dc, area, ui.page == Page::Gallery ? colors::surface : colors::canvas, colors::line, px(14));
    if (ui.page == Page::Gallery) {
        RECT title = area; title.left += px(18); title.top += px(10); title.bottom = title.top + px(32);
        const bool current=state->settings.page==Page::Gallery&&state->view_generation==ui.app.generation;
        const auto caption = !current || state->busy ? L"正在加载人员…" : state->people.empty()
            ? state->error ? L"加载失败，可从菜单重试" : state->total==0 ? L"人脸库为空，请先录入或导入人员" : L"未找到该 Face ID，清空查询可查看全库"
            : L"双击编辑资料 · 右键操作 · 滚动自动加载更多";
        label(dc, caption, title, ui.theme.body, colors::ink);
    }

    if (state->settings.page == ui.page && ui.page != Page::Gallery && ui.page != Page::ImageSearch) {
        InflateRect(&area, -px(2), -px(2));
        const auto saved = SaveDC(dc); IntersectClipRect(dc, area.left, area.top, area.right, area.bottom);
        SelectObject(dc, ui.theme.body); SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(240, 240, 240));
        if (ui.page == Page::Comparison) {
            const ComparisonLayout view({area.left,area.top,area.right,area.bottom},static_cast<int>(ui.theme.dpi));
            const std::shared_ptr<const Image> photos[]={state->image_a,state->image_b};
            const std::string errors[]={state->comparison_error_a,state->comparison_error_b};
            for(int slot=0;slot<2;++slot){
                const auto& bounds=view.slots[slot];const RECT box{bounds.left,bounds.top,bounds.right,bounds.bottom};
                fill(dc,box,RGB(31,43,60));
                if(photos[slot])bitmap(dc,*bgraImage(*photos[slot]),box);
                else label(dc,slot?L"点击选择图片 B":L"点击选择图片 A",box,ui.theme.body,RGB(220,230,240),DT_CENTER|DT_VCENTER|DT_SINGLELINE);
                const auto& error=view.errors[slot];const RECT detail{error.left,error.top,error.right,error.bottom};
                label(dc,errors[slot].empty()?(slot?L"图片 B":L"图片 A"):widen(errors[slot]).c_str(),detail,ui.theme.small,
                    errors[slot].empty()?RGB(220,230,240):RGB(255,150,150),DT_CENTER|DT_WORDBREAK|DT_END_ELLIPSIS);
            }
        } else if ((ui.page == Page::Enrollment || ui.page == Page::Reference) && state->captured && (state->pending_enrollment || state->pending_reference)) {
            bitmap(dc, *bgraImage(*state->captured), area);
        } else if (!state->preview) {
            RECT title = area; title.left += px(24); title.right -= px(24);
            title.top = (area.top + area.bottom) / 2 - px(38); title.bottom = title.top + px(34);
            label(dc, L"准备开始", title, ui.theme.title, RGB(230, 237, 250), DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            title.top += px(42); title.bottom = title.top + px(70);
            const wchar_t* hint = state->pending_reference ? L"已导入 HF1 基准；此文件不包含预览图片。请填写 Face ID 并确认保存。" : ui.page == Page::Detection ? L"打开摄像头查看实时结果，或选择图片检测"
                : ui.page == Page::Verification ? L"先从上方选择采集 Face ID，随后自动开始动态验证"
                : ui.page == Page::CameraSettings ? L"选择设备并打开以检查画面；分辨率、旋转和镜像修改后自动保存"
                : ui.page == Page::Enrollment ? L"相机采集或选择图片，核对预览后确认保存人员"
                : ui.page == Page::Search ? L"打开摄像头开始搜索；录入人员请进入独立录入页"
                : L"选择并打开摄像头，然后点击下方开始按钮";
            label(dc, hint, title, ui.theme.body, RGB(157, 176, 204), DT_CENTER | DT_WORDBREAK);
        } else if (state->preview) {
            const auto fit = bitmap(dc, *state->preview, area);
            const auto old_brush = SelectObject(dc, GetStockObject(NULL_BRUSH));
            const bool show_search = ui.page != Page::Search || (state->camera_open && !state->paused && !state->error
                && state->view_generation==ui.app.generation && searchOverlayFresh(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(),state->preview_at_ms,state->analysis_at_ms));
            for (size_t i = 0; show_search && (ui.page==Page::Search||ui.page==Page::Detection) && i < state->update.faces.size(); ++i) {
                const auto& face = state->update.faces[i];
                const bool passed = ui.page == Page::Search ? searchFaceAccepted(state->update, face) : state->update.matched;
                const bool rejected = ui.page == Page::Search && (state->update.end_reason == HIFACE_SEARCH_END_SPOOF_DETECTED
                    || state->update.end_reason == HIFACE_SEARCH_END_TIMEOUT || state->update.end_reason == HIFACE_SEARCH_END_MATCH_FOUND);
                const auto color = passed ? RGB(40,220,90) : ui.page!=Page::Search ? RGB(255,190,40) : rejected ? RGB(255,120,120) : RGB(174,184,198);
                const auto pen = CreatePen(PS_SOLID, px(2), color); const auto previous_pen = SelectObject(dc, pen);
                auto x = [&](float value) { return fit.x + static_cast<int>((state->settings.mirror ? state->preview->width - value : value) * fit.scale); };
                auto y = [&](float value) { return fit.y + static_cast<int>(value * fit.scale); };
                int left = x(face.x), right = x(face.x + face.width); if (left > right) std::swap(left, right);
                if(ui.page!=Page::Detection)Rectangle(dc, left, y(face.y), right, y(face.y + face.height));
                if (i < state->update.details.size()) {
                    const auto& detail = state->update.details[i];
                    const auto contours=detectionContours(detail.mesh);
                    for(int pass=0;pass<2;++pass){
                        const auto contour_pen=CreatePen(PS_SOLID,px(pass?1:3),pass?RGB(0,188,205):RGB(0,45,52));
                        const auto saved_pen=SelectObject(dc,contour_pen);
                        for(const auto& line:contours){MoveToEx(dc,x(line.start.x),y(line.start.y),nullptr);LineTo(dc,x(line.end.x),y(line.end.y));}
                        SelectObject(dc,saved_pen);DeleteObject(contour_pen);
                    }
                }
                if(ui.page==Page::Detection){
                    const auto dot_brush=SelectObject(dc,GetStockObject(DC_BRUSH));SetDCBrushColor(dc,RGB(156,39,176));
                    const auto dot_pen=CreatePen(PS_SOLID,1,RGB(156,39,176));const auto prior_pen=SelectObject(dc,dot_pen);
                    for(size_t point=0;point<HIFACE_MAX_LANDMARKS;++point){
                        if(!std::isfinite(face.landmarks[point*2])||!std::isfinite(face.landmarks[point*2+1]))continue;
                        const int cx=x(face.landmarks[point*2]),cy=y(face.landmarks[point*2+1]),r=px(2);
                        Ellipse(dc,cx-r,cy-r,cx+r+1,cy+r+1);
                    }
                    SelectObject(dc,prior_pen);SelectObject(dc,dot_brush);DeleteObject(dot_pen);
                }
                if (face.has_similarity) {
                    const auto label = widen(ui.page == Page::Search ? searchFaceText(state->update, face) : std::string(face.face_id) + " " + std::to_string(face.similarity));
                    TextOutW(dc, left, y(face.y) - px(22), label.c_str(), static_cast<int>(label.size()));
                }
                SelectObject(dc, previous_pen); DeleteObject(pen);
            }
            SelectObject(dc, old_brush);
            if((ui.page==Page::Enrollment||ui.page==Page::Reference||ui.page==Page::Verification||ui.page==Page::Liveness)&&!state->pending_enrollment&&!state->pending_reference){
                const int size=std::min(area.right-area.left,area.bottom-area.top)*3/4;
                const int cx=(area.left+area.right)/2,cy=(area.top+area.bottom)/2;
                const auto pen=CreatePen(PS_SOLID,px(3),RGB(103,173,91));const auto previous_pen=SelectObject(dc,pen);
                const auto previous_brush=SelectObject(dc,GetStockObject(NULL_BRUSH));
                Ellipse(dc,cx-size/2,cy-size/2,cx+size/2,cy+size/2);
                SelectObject(dc,previous_pen);SelectObject(dc,previous_brush);DeleteObject(pen);
                RECT hint{area.left+px(12),area.top+px(8),area.right-px(12),area.top+px(54)};
                label(dc,widen(state->update.message).c_str(),hint,ui.theme.body,RGB(255,255,255),DT_CENTER|DT_VCENTER|DT_WORDBREAK);
            }
        }
        if (state->captured && ui.page != Page::Comparison && ui.page != Page::Detection && ui.page != Page::Enrollment && ui.page != Page::Reference) {
            RECT thumb{area.right - px(170), area.bottom - px(196), area.right - px(6), area.bottom - px(6)};
            FillRect(dc, &thumb, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH))); bitmap(dc, *bgraImage(*state->captured), thumb);
            TextOutW(dc, thumb.left, thumb.top - px(20), L"最近对齐抓拍", 6);
        }
        RestoreDC(dc, saved);
    }
    if(ui.page==Page::Comparison){
        const int height=MulDiv(client.bottom,96,ui.theme.dpi);
        if(state->comparison_similarity){std::wostringstream score;score<<std::fixed<<std::setprecision(2)<<L"相似度 "<<*state->comparison_similarity*100<<L"%";
            label(dc,score.str().c_str(),rect(32,height-116,logical_width-64,34),ui.theme.result,colors::ink,DT_CENTER|DT_VCENTER|DT_SINGLELINE);
        }else if(state->error)label(dc,widen(state->update.message).c_str(),rect(32,height-116,logical_width-64,40),ui.theme.body,colors::error,DT_CENTER|DT_WORDBREAK);
    }
    BitBlt(target, 0, 0, client.right, client.bottom, dc, 0, 0, SRCCOPY);
    SelectObject(dc, old_bitmap); DeleteObject(buffer); DeleteDC(dc);
    EndPaint(ui.app.window, &paint);
}
void layout(Ui& ui);
LRESULT CALLBACK paneProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    const auto parent = GetParent(window); auto* ui = reinterpret_cast<Ui*>(GetWindowLongPtrW(parent, GWLP_USERDATA));
    if (!ui) return DefWindowProcW(window, message, wparam, lparam);
    if (message == WM_COMMAND || message == WM_DRAWITEM || message == WM_CTLCOLORSTATIC || message == WM_CTLCOLOREDIT || message == WM_CTLCOLORBTN)
        return SendMessageW(parent, message, wparam, lparam);
    if (message == WM_ERASEBKGND) return 1;
    if (message == WM_PAINT) { PAINTSTRUCT paint{}; auto dc = BeginPaint(window, &paint); FillRect(dc, &paint.rcPaint, ui->theme.surface); EndPaint(window, &paint); return 0; }
    if (message == kRevealFocusedControl) {
        RECT focused{}; GetWindowRect(reinterpret_cast<HWND>(lparam), &focused);
        MapWindowPoints(nullptr, window, reinterpret_cast<POINT*>(&focused), 2);
        const int top = MulDiv(focused.top, 96, ui->theme.dpi), bottom = MulDiv(focused.bottom, 96, ui->theme.dpi);
        if (top < 0) ui->scroll += top - 8;
        else if (bottom > ui->view_height) ui->scroll += bottom - ui->view_height + 8;
        ui->scroll = std::clamp(ui->scroll, 0, std::max(0, ui->content_height - ui->view_height)); layout(*ui); return 0;
    }
    if (message == WM_VSCROLL || message == WM_MOUSEWHEEL) {
        int next = ui->scroll;
        if (message == WM_MOUSEWHEEL) next -= GET_WHEEL_DELTA_WPARAM(wparam) / WHEEL_DELTA * 84;
        else {
            SCROLLINFO info{}; info.cbSize = sizeof(info); info.fMask = SIF_TRACKPOS; GetScrollInfo(window, SB_VERT, &info);
            switch (LOWORD(wparam)) {
                case SB_LINEUP: next -= 28; break; case SB_LINEDOWN: next += 28; break;
                case SB_PAGEUP: next -= ui->view_height; break; case SB_PAGEDOWN: next += ui->view_height; break;
                case SB_THUMBTRACK: case SB_THUMBPOSITION: next = info.nTrackPos; break;
                case SB_TOP: next = 0; break; case SB_BOTTOM: next = ui->content_height; break;
            }
        }
        ui->scroll = std::clamp(next, 0, std::max(0, ui->content_height - ui->view_height)); layout(*ui); return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}
void create(Ui& ui) {
    const auto window = ui.app.window;
    ui.theme.setDpi(GetDpiForWindow(window));
    WNDCLASSW panel{}; panel.lpfnWndProc = paneProcedure; panel.hInstance = GetModuleHandleW(nullptr);
    panel.lpszClassName = L"HiFaceParameterPane"; panel.hCursor = LoadCursorW(nullptr, IDC_ARROW); RegisterClassW(&panel);
    ui.pane = CreateWindowExW(WS_EX_CONTROLPARENT, panel.lpszClassName, L"参数与操作", WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_CLIPCHILDREN,
        0, 0, 10, 10, window, reinterpret_cast<HMENU>(ParameterPane), panel.hInstance, nullptr);
    if (!ui.pane) throw std::runtime_error("Cannot create parameter panel");
    for (int i = 0; i < kFeatureCount; ++i) button(ui, HomeBase + i, page_info[static_cast<int>(feature_pages[i])].title);
    button(ui, Back, L"返回"); button(ui, Parameters, L"参数设置");
    button(ui, HomePrevious, L"上一屏"); button(ui, HomeNext, L"下一屏");
    control(ui,L"EDIT",L"",QueryId,ES_AUTOHSCROLL|WS_TABSTOP);
    SendMessageW(child(window,QueryId),EM_SETLIMITTEXT,256,0);
    SendMessageW(child(window,QueryId),EM_SETCUEBANNER,TRUE,reinterpret_cast<LPARAM>(L"输入完整 Face ID；留空显示全库"));
    button(ui,LookupPerson,L"查询");button(ui,ClearQuery,L"清空");button(ui,GalleryMenu,L"菜单 ▾");
    button(ui,ResetSearch,L"恢复默认");button(ui,CancelSettings,L"取消修改");
    button(ui,SaveReference,L"确认保存采集基准");SetParent(child(window,SaveReference),ui.pane);
    combo(ui,ReferenceChoice,{});send(window,ReferenceChoice,CB_SETCURSEL,-1,0);
    send(window,ReferenceChoice,CB_SETCUEBANNER,0,reinterpret_cast<LPARAM>(L"选择已采集的 Face ID"));
    button(ui, Primary, L"开始");
    combo(ui, Device, {}); button(ui, RefreshDevices, L"刷新"); button(ui, Open, L"打开摄像头"); button(ui, Close, L"关闭摄像头"); button(ui, Logs, L"日志"); button(ui, Help, L"关于 SDK");
    button(ui, HomeVersion, aboutTitle().c_str());
    const auto toast = control(ui, L"STATIC", L"", WebsiteToast, SS_CENTER | SS_CENTERIMAGE);
    ShowWindow(toast, SW_HIDE);
    combo(ui, Resolution, {L"640×480", L"1280×720", L"1920×1080"}); combo(ui, Rotation, {L"旋转 0°", L"旋转 90°", L"旋转 180°", L"旋转 270°"});
    control(ui, L"BUTTON", L"镜像预览", Mirror, BS_AUTOCHECKBOX | WS_TABSTOP); button(ui, Apply, L"应用参数");
    field(ui, PersonId, L"人员 ID", L"person-001"); field(ui, Group, L"分组", L""); field(ui, Tag, L"标签", L"");
    field(ui, MaxFaces, L"最多人脸", L"3"); field(ui, Threshold, L"相似度阈值", L"0.80"); field(ui, Interval, L"成功间隔 ms", L"0"); field(ui, Timeout, L"搜索超时 ms", L"3000");
    field(ui, CustomActions, L"动作序列", L"2,1,0");
    control(ui, L"BUTTON", L"显示关键轮廓", Details, BS_AUTOCHECKBOX | WS_TABSTOP); checkBox(window, Details, true);
    control(ui, L"BUTTON", L"启用静默活体", Silent, BS_AUTOCHECKBOX | WS_TABSTOP); checkBox(window, Silent, true);
    control(ui, L"BUTTON", L"允许多人（处理主目标）", Multiple, BS_AUTOCHECKBOX | WS_TABSTOP); checkBox(window, Multiple, true);
    combo(ui, SearchMode, {L"1:N 单人搜索", L"M:N 多人搜索（无活体）"});
    combo(ui, Actions, {L"不要求动作", L"随机动作（验证2步／活体3步）", L"眨眼", L"点头", L"摇头", L"张嘴", L"眨眼 → 点头", L"自定义：0摇头 1点头 2眨眼 3张嘴"}); send(window, Actions, CB_SETCURSEL, 1, 0);
    button(ui, StartFlow, L"开始本轮"); button(ui, Enroll, L"人脸录入");
    button(ui, SaveEnrollment, L"确认预览并保存人员"); button(ui, Cancel, L"取消流程 / 停止导入"); button(ui, Pause, L"暂停搜索 / 释放缓存");
    button(ui, PickA, L"选择图片 A"); button(ui, PickB, L"选择图片 B"); button(ui, Compare, L"比对两张图片（最大人脸）");
    button(ui, ImageReference, L"从图片采集"); button(ui, ImportReference, L"导入 HF1");
    button(ui, ExportFeature, L"导出 1:1 基准 HF1"); button(ui, ExportPreview, L"导出最近对齐抓拍 PNG"); button(ui, ImageEnroll, L"从图片采集");
    button(ui, RefreshGallery, L"按分组 / 标签筛选并刷新"); button(ui, NextPage, L"下一页（100 条）"); button(ui, DeletePerson, L"删除该人员 ID"); button(ui, UpdatePerson, L"保存人员分组 / 标签");
    button(ui, ImportJson, L"批量导入 Android HF1 JSON"); button(ui, ExportJson, L"导出筛选结果 HF1 JSON"); button(ui, ImportImages, L"多选本地图片提取并导入"); button(ui, ReleaseMemory, L"释放数据库内存缓存");
    button(ui, PickSearchImage, L"选择图片并搜索"); button(ui, SearchImageAgain, L"重新搜索当前图片"); button(ui, GoGallery, L"打开人脸库");
    control(ui, L"STATIC", L"最多 10 张脸 · 阈值 0.80", SearchGuide);
    // Two fixed single-line controls; copying keeps the full, unabridged result.
    // 固定两个单行控件，复制时保留未缩略的完整结果。
    control(ui, L"EDIT", L"", SearchCaption, ES_READONLY | ES_AUTOHSCROLL | WS_TABSTOP);
    control(ui, L"EDIT", L"", SearchResults, ES_READONLY | ES_AUTOHSCROLL | WS_TABSTOP);
    control(ui, L"BUTTON", L"复制", CopySearch, WS_TABSTOP);
    const auto list = control(ui, WC_LISTVIEWW, L"", People, LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | WS_TABSTOP);
    ListView_SetExtendedListViewStyle(list, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
    const wchar_t* columns[] = {L"人员 ID", L"分组", L"标签", L"更新时间"};
    for (int i = 0; i < 4; ++i) { LVCOLUMNW column{}; column.mask = LVCF_TEXT | LVCF_WIDTH; column.cx = ui.theme.px(160); column.pszText = const_cast<wchar_t*>(columns[i]); ListView_InsertColumn(list, i, &column); }
    control(ui, L"STATIC", L"正在打开人脸库...", Status, SS_ENDELLIPSIS); control(ui, L"STATIC", L"", Metrics, SS_ENDELLIPSIS);
    for (int id = PersonId; id <= ReleaseMemory; ++id) {
        if (id == Cancel || id == Enroll || id == GoGallery || id == SearchImageAgain) continue;
        if (const auto field = child(window, id)) SetParent(field, ui.pane);
        if (const auto label = child(window, id + kLabelOffset)) SetParent(label, ui.pane);
    }
    HWND after = HWND_TOP;
    for (const int id : {Back, HomePrevious, HomeNext}) {
        const auto field = child(window, id);
        SetWindowPos(field, after, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE); after = field;
    }
    for (int i = 0; i < kFeatureCount; ++i) {
        const auto field = child(window, HomeBase+i);
        SetWindowPos(field, after, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE); after = field;
    }
    const int tab_order[] = {Enroll, GoGallery, ReferenceChoice, QueryId, LookupPerson, ClearQuery, GalleryMenu, Parameters, Device, RefreshDevices, Open, Close, Resolution, Rotation, Mirror, Apply, ParameterPane, Primary, SearchImageAgain, Cancel, SearchResults, People, Logs, Help, HomeVersion};
    for (const int id : tab_order) {
        const auto field = child(window, id); SetWindowPos(field, after, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE); after = field;
    }
    const auto preferences = loadCameraPreferences(demoDataDirectory() / L"camera-settings.txt");
    send(window, Resolution, CB_SETCURSEL, preferences.width == 1920 ? 2 : preferences.width == 1280 ? 1 : 0, 0);
    send(window, Rotation, CB_SETCURSEL, preferences.rotation / 90, 0); checkBox(window, Mirror, preferences.mirror);
    ui.image_search.create(window, ui.theme);
    ui.drafts[static_cast<size_t>(Page::Enrollment)].id.clear();
    ui.drafts[static_cast<size_t>(Page::Reference)].id.clear();
    ui.drafts[static_cast<size_t>(Page::Detection)].max_faces=L"10";
    SetTimer(window,kSearchDisplayTimer,100,nullptr);
    ui.creating = false; layout(ui);
    try { refreshDevices(ui); } catch (const std::exception& error) { writeLog(error.what()); setText(window, Status, widen(error.what())); }
    ui.app.start();
}
// Route native events to navigation or worker commands. Successful queue admission
// invalidates the old page before its in-flight capture/search can publish again.
// 分派导航与工作线程命令；成功入队时使旧页失效，拒绝旧采集/搜索结果。
void action(Ui& ui, int id, int notification) {
    const auto window = ui.app.window;
    if (ui.creating) return;
    if (id == HomePrevious || id == HomeNext) {
        scrollHome(ui, ui.home_scroll + (id == HomePrevious ? -1 : 1) * std::max(96, homeGeometry(ui).viewport.height() - 20)); return;
    }
    if (id == Parameters || (id == Back && ui.parameters_open)) {
        ui.parameters_open = !ui.parameters_open;
        layout(ui); update(ui); InvalidateRect(window, nullptr, TRUE); SetFocus(child(window, ui.parameters_open ? Apply : Back)); return;
    }
    if (id == Back) {
        if (ui.page == Page::Home) return;
        if ((ui.return_after_save || ui.return_after_reference) && ui.pending_command) return;
        if (ui.app.current()->importing && MessageBoxW(window, L"停止导入并返回上一级？已保存的批次会保留。", L"停止导入并返回", MB_YESNO | MB_ICONQUESTION) != IDYES) return;
        id = NavBase + static_cast<int>(ui.history.parent(ui.page));
    }
    if (id >= HomeBase && id < HomeBase + kFeatureCount) id = NavBase + static_cast<int>(feature_pages[id - HomeBase]);
    if (id >= NavBase && id < NavBase + kPageCount) {
        if (ui.page == static_cast<Page>(id - NavBase)) return;
        auto& previous = ui.drafts[static_cast<size_t>(ui.page)];
        previous.max_faces = text(window, MaxFaces); previous.threshold = text(window, Threshold);
        previous.actions = text(window, CustomActions); previous.action_preset = selection(window, Actions);
        previous.silent = checked(window, Silent); previous.multiple = checked(window, Multiple); previous.detailed = checked(window, Details);
        previous.interval = text(window, Interval); previous.timeout = text(window, Timeout); previous.search_mode = selection(window, SearchMode);
        previous.id = text(window, PersonId); previous.group = text(window, Group); previous.tag = text(window, Tag);
        const auto next_page = static_cast<Page>(id - NavBase), old_page = ui.page;
        if(next_page==Page::Verification)send(window,ReferenceChoice,CB_SETCURSEL,-1,0);
        if ((old_page == Page::ImageSearch && next_page != Page::Gallery) || (old_page == Page::Gallery && next_page != Page::ImageSearch))
            ui.image_search.setContent(nullptr, nullptr);
        ui.history.moved(old_page, next_page);
        KillTimer(window,kGalleryQueryTimer);
        ui.page = next_page; ui.scroll = 0; ui.dirty = false; ui.search_request_generation = 0; ui.parameters_open = false;
        ui.capture_preview=false;ui.handled_flow_completion=ui.app.current()->flow_completion;ui.gallery_append_queued=false;ui.close_settings_after=0;
        if (next_page==Page::Gallery) { ui.rendered_people.clear();ListView_DeleteAllItems(child(window,People));ui.rendered_gallery=UINT64_MAX; }
        ui.return_after_save = ui.return_after_reference = 0;
        const auto& next = ui.drafts[static_cast<size_t>(ui.page)];
        ui.creating = true;
        setText(window, MaxFaces, next.max_faces); setText(window, Threshold, next.threshold); setText(window, CustomActions, next.actions);
        send(window, Actions, CB_SETCURSEL, next.action_preset, 0); checkBox(window, Silent, next.silent); checkBox(window, Multiple, next.multiple);
        setText(window, Interval, next.interval); setText(window, Timeout, next.timeout); send(window, SearchMode, CB_SETCURSEL, next.search_mode, 0);
        checkBox(window, Details, next.detailed); setText(window, PersonId, next.id); setText(window, Group, next.group); setText(window, Tag, next.tag);
        ui.creating = false; ui.parameter_notice.clear();
        Settings settings;
        try { settings = readSettings(ui); }
        catch (const std::exception&) {
            // A saved invalid draft must not trap navigation or silently change the text.
            // 已保存的无效草稿不能阻止导航，也不能静默修改输入文字。
            settings = ui.app.current()->settings; settings.page = ui.page; settings.parameters_valid = false; ui.dirty = true;
            ui.parameter_notice = L"已保留未应用的参数，请修正后再执行操作。";
        }
        layout(ui);
        ui.pending_command = ui.app.current()->fatal ? 0 : ui.app.enqueue({Action::EnterPage, std::move(settings), {}, 0});
        update(ui);
        if (ui.page == Page::Home) SetFocus(child(window, HomeBase + std::max(0, homeIndex(old_page))));
        else SetFocus(child(window, Back));
        InvalidateRect(window, nullptr, TRUE); return;
    }
    if (id == Primary) { if (!IsWindowEnabled(child(window, Primary))) return;
        const auto state=ui.app.current();
        id = ui.page==Page::Reference&&state->pending_reference?SaveReference:ui.page==Page::Enrollment&&state->pending_enrollment?SaveEnrollment
            : ui.page!=Page::Detection&&usesCamera(ui.page)&&!state->camera_open?Open:primaryAction(ui.page);
    }
    if (id==QueryId && notification==EN_CHANGE && ui.page==Page::Gallery) {
        ++ui.app.generation; // Hide old rows during the debounce; the query command is queued later.
        ListView_SetItemState(child(window,People),-1,0,LVIS_SELECTED);
        SetTimer(window,kGalleryQueryTimer,text(window,QueryId).empty()?1:300,nullptr);update(ui);return;
    }
    if ((notification == EN_CHANGE && id >= PersonId && id <= CustomActions)
        || (notification == CBN_SELCHANGE && (id == Resolution || id == Rotation || id == SearchMode || id == Actions))
        || (notification == BN_CLICKED && (id == Mirror || id == Details || id == Silent || id == Multiple))) {
        ui.dirty = true; ui.parameter_notice.clear(); setText(window, Apply, L"应用修改 *");
    }
    if(ui.page==Page::CameraSettings && ((notification==CBN_SELCHANGE&&(id==Resolution||id==Rotation))||(notification==BN_CLICKED&&id==Mirror))){
        submit(ui,id==Resolution&&ui.app.current()->camera_open?Action::OpenCamera:Action::Apply);update(ui);return;
    }
    switch (id) {
        case SearchMode:
            if (notification == CBN_SELCHANGE) { checkBox(window, Silent, selection(window, SearchMode) == 0); layout(ui); update(ui); }
            break;
        case Device:
            if(notification==CBN_SELCHANGE && ui.app.current()->settings.parameters_valid && usesCamera(ui.page)&&(ui.page!=Page::CameraSettings||ui.app.current()->camera_open)&&(ui.page!=Page::Verification||ui.app.current()->has_reference)) {
                auto settings = ui.app.current()->settings; settings.page = ui.page;
                readCameraSettings(ui, settings);
                ui.pending_command=ui.app.enqueue({Action::OpenCamera,std::move(settings),{},0});
            }
            break;
        case ResetSearch:
            send(window,SearchMode,CB_SETCURSEL,0,0);checkBox(window,Silent,true);
            setText(window,MaxFaces,L"3");setText(window,Threshold,L"0.80");setText(window,Interval,L"0");setText(window,Timeout,L"3000");
            setText(window,Group,L"");setText(window,Tag,L"");ui.dirty=true;layout(ui);break;
        case CancelSettings: {
            const auto applied=ui.app.current();const auto& options=applied->settings.search;
            send(window,SearchMode,CB_SETCURSEL,options.multi_face?1:0,0);checkBox(window,Silent,options.liveness);
            setText(window,MaxFaces,std::to_wstring(options.max_faces));
            std::wostringstream value;value<<std::fixed<<std::setprecision(2)<<options.threshold;setText(window,Threshold,value.str());
            setText(window,Interval,std::to_wstring(options.interval_ms));setText(window,Timeout,std::to_wstring(options.timeout_ms));
            setText(window,Group,widen(options.group));setText(window,Tag,widen(options.tag));
            ui.parameters_open=false;ui.dirty=false;ui.parameter_notice.clear();layout(ui);break;
        }
        case Actions: if (notification == CBN_SELCHANGE) {layout(ui);update(ui);} break;
        case RefreshDevices: refreshDevices(ui); update(ui); break;
        case Open:
            if (selection(window, Device) < 0) throw std::runtime_error("Connect a camera and allow desktop camera access in Windows Settings, then refresh");
            submit(ui, Action::OpenCamera); break;
        case Close: submit(ui, Action::CloseCamera); break;
        case Apply: submit(ui, Action::Apply); break;
        case Logs:
            if (reinterpret_cast<INT_PTR>(ShellExecuteW(window, L"open", logDirectory().c_str(), nullptr, nullptr, SW_SHOWNORMAL)) <= 32) throw std::runtime_error("Cannot open log directory");
            break;
        case Help: case HomeVersion: {
            const auto toast = child(window, WebsiteToast);
            SHELLEXECUTEINFOW launch{};
            launch.cbSize = sizeof(launch);
            launch.fMask = SEE_MASK_FLAG_NO_UI;
            launch.hwnd = window;
            launch.lpVerb = L"open";
            launch.lpFile = kWebsiteUrl;
            launch.nShow = SW_SHOWNORMAL;
            if (ShellExecuteExW(&launch)) {
                KillTimer(window, kWebsiteToastTimer);
                ShowWindow(toast, SW_HIDE);
            } else {
                setText(window, WebsiteToast, std::wstring(chineseUi() ? L"更多：" : L"More: ") + kWebsiteUrl);
                SetWindowPos(toast, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
                SetTimer(window, kWebsiteToastTimer, 3000, nullptr);
            }
            break;
        }
        case ReferenceChoice:
            if(notification==CBN_SELCHANGE&&ui.page==Page::Verification){submit(ui,Action::SelectReference);}break;
        case ShowFlowResult: {
            const auto state=ui.app.current();
            if((ui.page!=Page::Verification&&ui.page!=Page::Liveness)||state->view_generation!=ui.app.generation||state->flow_completion!=ui.handled_flow_completion||state->flow_active||state->busy||state->flow_summary.empty())break;
            const TASKDIALOG_BUTTON buttons[]={{IDRETRY,L"重试"},{IDCANCEL,L"关闭"}};
            TASKDIALOGCONFIG dialog{};dialog.cbSize=sizeof(dialog);dialog.hwndParent=window;dialog.dwFlags=TDF_ALLOW_DIALOG_CANCELLATION|TDF_SIZE_TO_CONTENT;
            dialog.pszWindowTitle=ui.page==Page::Verification?L"动态验证结果":L"活体检测结果";
            const auto summary=widen(state->flow_summary);dialog.pszContent=summary.c_str();dialog.cButtons=2;dialog.pButtons=buttons;dialog.nDefaultButton=IDRETRY;
            int selected=IDCANCEL;
            if(FAILED(TaskDialogIndirect(&dialog,&selected,nullptr,nullptr)))selected=MessageBoxW(window,(summary+L"\n重试？").c_str(),dialog.pszWindowTitle,MB_RETRYCANCEL);
            if(selected==IDRETRY){submit(ui,Action::StartFlow);}else{ui.parameters_open=false;PostMessageW(window,WM_COMMAND,MAKEWPARAM(Back,BN_CLICKED),0);}
            break;
        }
        case SaveReference: {
            const auto id=normalizeMetadata(utf8(text(window,PersonId)));EnrollmentDraft::validateMetadata(id,"","");
            if(ui.app.current()->pending_reference&&MessageBoxW(window,(L"确认保存 Face ID: "+widen(id)+L"？已有同名参考将更新。").c_str(),L"保存采集基准",MB_YESNO|MB_ICONQUESTION)==IDYES){submit(ui,Action::SaveReference);ui.return_after_reference=ui.pending_command;}break;
        }
        case StartFlow: submit(ui,ui.app.current()->camera_open?Action::StartFlow:Action::OpenCamera); break;
        case Enroll: action(ui, NavBase + static_cast<int>(Page::Enrollment), BN_CLICKED); break;
        case SaveEnrollment:
            EnrollmentDraft::validateMetadata(normalizeMetadata(utf8(text(window, PersonId))), normalizeMetadata(utf8(text(window, Group))), normalizeMetadata(utf8(text(window, Tag))));
            if (ui.app.current()->pending_enrollment && MessageBoxW(window,
                (L"确认将当前预览保存为人员 ID: " + widen(normalizeMetadata(utf8(text(window, PersonId)))) + L"？").c_str(),
                L"确认人脸录入", MB_YESNO | MB_ICONQUESTION) == IDYES) { submit(ui, Action::SaveEnrollment); ui.return_after_save = ui.pending_command; }
            break;
        case ConfirmReplacement: {
            const auto state=ui.app.current();
            if(ui.page!=Page::Enrollment||!state->pending_enrollment||!state->enrollment_conflict||state->view_generation!=ui.app.generation
                ||normalizeMetadata(utf8(text(window,PersonId)))!=state->conflict_id)break;
            if(MessageBoxW(window,(L"Face ID: "+widen(state->conflict_id)+L" 已存在。\n是否用当前人脸与资料覆盖？选择“否”将保留当前预览。").c_str(),L"确认覆盖已有人员",MB_YESNO|MB_DEFBUTTON2|MB_ICONWARNING)==IDYES){
                submit(ui,Action::ReplaceEnrollment);ui.return_after_save=ui.pending_command;
            }
            break;
        }
        case Cancel: submit(ui, Action::Cancel); break;
        case Pause:
            if (ui.app.current()->paused && ui.dirty) { ui.parameter_notice = L"请先应用修改，再恢复搜索。"; break; }
            submit(ui, Action::Pause); break;
        case PickA: case PickB: {
            auto files = choose(window, false, false, kImages); if (!files.empty()) submit(ui, id == PickA ? Action::LoadA : Action::LoadB, std::move(files)); break;
        }
        case PickSearchImage: {
            auto files = choose(window, false, false, kImages);
            if (!files.empty()) submit(ui, Action::SearchPhoto, std::move(files));
            break;
        }
        case SearchImageAgain: submit(ui, Action::SearchPhotoAgain); break;
        case CopySearch: {
            if (!OpenClipboard(window)) break;
            const auto bytes=(ui.last_search_results.size()+1)*sizeof(wchar_t);
            HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,bytes);
            if (memory) {
                auto data=static_cast<wchar_t*>(GlobalLock(memory));
                if (data) {
                    std::copy(ui.last_search_results.c_str(),ui.last_search_results.c_str()+ui.last_search_results.size()+1,data);
                    GlobalUnlock(memory);
                    if (!EmptyClipboard() || !SetClipboardData(CF_UNICODETEXT,memory)) GlobalFree(memory);
                } else GlobalFree(memory);
            }
            CloseClipboard();break;
        }
        case GoGallery: action(ui, NavBase + static_cast<int>(ui.page==Page::Verification?Page::Reference:Page::Gallery), BN_CLICKED); break;
        case Compare: submit(ui, Action::Compare); break;
        case ImageReference: submit(ui, Action::SetImageReference); break;
        case ImportReference: {
            auto files = choose(window, false, false, kFeature); if (!files.empty()) submit(ui, Action::ImportReference, std::move(files)); break;
        }
        case ExportFeature: {
            auto files = choose(window, true, false, kFeature, L"hf1"); if (!files.empty()) submit(ui, Action::ExportFeature, std::move(files)); break;
        }
        case ExportPreview: {
            auto files = choose(window, true, false, L"PNG image\0*.png\0", L"png"); if (!files.empty()) submit(ui, Action::ExportPreview, std::move(files)); break;
        }
        case ImageEnroll: submit(ui, Action::ImageEnroll); break;
        case GalleryMenu: {RECT bounds{};GetWindowRect(child(window,GalleryMenu),&bounds);galleryMenu(ui,{bounds.left,bounds.bottom});break;}
        case ClearQuery: setText(window,QueryId,L"");[[fallthrough]];
        case LookupPerson: case RefreshGallery:
            KillTimer(window,kGalleryQueryTimer);submit(ui,Action::RefreshGallery);break;
        case NextPage:
            ui.gallery_append_queued=false;
            if(ui.page==Page::Gallery && !ui.pending_command && !ui.app.current()->busy && ui.app.current()->gallery_more
                && ui.app.current()->view_generation==ui.app.generation) submit(ui, Action::NextPage);
            break;
        case DeletePerson: {
            const auto person=selectedPerson(ui);if(!person)break;
            if (MessageBoxW(window, (L"确认删除 ID: " + widen(person->id) + L"？此操作不能撤销。").c_str(), L"删除人员", MB_YESNO | MB_DEFBUTTON2 | MB_ICONWARNING) == IDYES){
                setText(window,PersonId,widen(person->id));submit(ui, Action::DeletePerson);
            }break;
        }
        case UpdatePerson: {const auto person=selectedPerson(ui);if(person)editMetadata(ui,*person);break;}
        case ImportSynthetic: case ImportJson: case ImportImages: {
            std::vector<std::filesystem::path> files;
            if(id==ImportSynthetic){
                auto file=executableDirectory()/L"data/features_10000.json";
                if(!std::filesystem::is_regular_file(file))file=executableDirectory().parent_path()/L"data/features_10000.json";
                if(!std::filesystem::is_regular_file(file))throw std::runtime_error(u8"未找到随包演示特征，请完整解压 Demo");
                files.push_back(std::move(file));
            }else files=choose(window, false, id == ImportImages, id == ImportImages ? kImages : kJson);
            if (!files.empty() && MessageBoxW(window, L"将按 Face ID 新增或覆盖记录。JSON 必须匹配当前 HF1 特征空间；图片以文件名为ID。\n取消会保留已保存数据，是否开始？", L"批量导入", MB_YESNO | MB_ICONQUESTION) == IDYES)
                submit(ui, id == ImportImages ? Action::ImportImages : Action::ImportJson, std::move(files));
            break;
        }
        case ExportJson: {
            auto files = choose(window, true, false, kJson, L"json"); if (!files.empty()) submit(ui, Action::ExportJson, std::move(files)); break;
        }
        case ReleaseMemory: submit(ui, Action::ReleaseMemory); break;

    }
    update(ui);
}
bool shortcut(Ui& ui, const MSG& message) {
    if (message.message != WM_KEYDOWN || GetKeyState(VK_MENU) < 0) return false;
    if (ui.page == Page::Home && (message.wParam == VK_PRIOR || message.wParam == VK_NEXT || message.wParam == VK_HOME || message.wParam == VK_END)) {
        const int delta = std::max(96, homeGeometry(ui).viewport.height() - 20);
        scrollHome(ui, message.wParam == VK_HOME ? 0 : message.wParam == VK_END ? 100000 : ui.home_scroll + (message.wParam == VK_PRIOR ? -delta : delta)); return true;
    }
    if(ui.page==Page::Home && message.wParam>=VK_LEFT && message.wParam<=VK_DOWN){
        const int focused=GetDlgCtrlID(GetFocus())-HomeBase;
        if(focused>=0&&focused<kFeatureCount){
            const int columns=homeGeometry(ui).columns;int next=focused;
            if(message.wParam==VK_LEFT&&focused%columns>0)--next;
            if(message.wParam==VK_RIGHT&&focused%columns<columns-1&&focused+1<kFeatureCount)++next;
            if(message.wParam==VK_UP&&focused>=columns)next-=columns;
            if(message.wParam==VK_DOWN&&focused+columns<kFeatureCount)next+=columns;
            const auto target=child(ui.app.window,HomeBase+next);
            if(IsWindowEnabled(target))SetFocus(target);
            return true;
        }
    }
    int id = 0;
    if (message.wParam == VK_ESCAPE) id = Back;
    else if(ui.page==Page::Gallery){
        if(message.wParam==VK_RETURN && GetFocus()==child(ui.app.window,QueryId))id=LookupPerson;
        else if(message.wParam==VK_F5)id=RefreshGallery;
        else if(GetFocus()==child(ui.app.window,People)&&message.wParam==VK_DELETE)id=DeletePerson;
        else if(GetFocus()==child(ui.app.window,People)&&message.wParam==VK_RETURN)id=UpdatePerson;
    }
    else if (ui.page == Page::ImageSearch) {
        if (message.wParam == 'O' && GetKeyState(VK_CONTROL) < 0) id = PickSearchImage;
        else if (message.wParam == VK_F5 && GetKeyState(VK_CONTROL) >= 0) id = SearchImageAgain;
    }
    if (!id) return false;
    if (!(message.lParam & (LPARAM(1) << 30)) && IsWindowEnabled(child(ui.app.window, id))) {
        try { action(ui, id, BN_CLICKED); }
        catch (const std::exception& error) {
            writeLog(error.what()); MessageBoxW(ui.app.window, widen(error.what()).c_str(), L"HiFace", MB_OK | MB_ICONERROR);
        }
    }
    return true;
}
LRESULT CALLBACK windowProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* ui = reinterpret_cast<Ui*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        ui = static_cast<Ui*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams); ui->app.window = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(ui));
    }
    if (!ui) return DefWindowProcW(window, message, wparam, lparam);
    try {
        switch (message) {
            case WM_CREATE: create(*ui); return 0;
            case WM_SIZE: layout(*ui); InvalidateRect(window, nullptr, TRUE); return 0;
            case WM_GETMINMAXINFO: {
                const auto work=workingArea(window);const auto minimum=landscapeWindow(window,1,1),maximum=landscapeWindow(window,work.right-work.left,work.bottom-work.top);
                auto* info=reinterpret_cast<MINMAXINFO*>(lparam);info->ptMinTrackSize={minimum.width,minimum.height};info->ptMaxTrackSize={maximum.width,maximum.height};info->ptMaxSize={maximum.width,maximum.height};
                MONITORINFO monitor{};monitor.cbSize=sizeof(monitor);if(GetMonitorInfoW(MonitorFromWindow(window,MONITOR_DEFAULTTONEAREST),&monitor))info->ptMaxPosition={work.left-monitor.rcMonitor.left,work.top-monitor.rcMonitor.top};
                return 0;
            }
            case WM_SIZING: {
                auto* bounds=reinterpret_cast<RECT*>(lparam);const auto size=landscapeWindow(window,bounds->right-bounds->left,bounds->bottom-bounds->top);
                if(wparam==WMSZ_LEFT||wparam==WMSZ_TOPLEFT||wparam==WMSZ_BOTTOMLEFT)bounds->left=bounds->right-size.width;else bounds->right=bounds->left+size.width;
                if(wparam==WMSZ_TOP||wparam==WMSZ_TOPLEFT||wparam==WMSZ_TOPRIGHT)bounds->top=bounds->bottom-size.height;else bounds->bottom=bounds->top+size.height;return TRUE;
            }
            case WM_WINDOWPOSCHANGING: {
                auto* position=reinterpret_cast<WINDOWPOS*>(lparam);
                if(!(position->flags&SWP_NOSIZE)&&position->cx>=160&&position->cy>=100&&!IsIconic(window)){const auto size=landscapeWindow(window,position->cx,position->cy);position->cx=size.width;position->cy=size.height;}
                break;
            }
            case WM_DPICHANGED: {
                ui->theme.setDpi(HIWORD(wparam));
                EnumChildWindows(window, [](HWND child, LPARAM context) -> BOOL { reinterpret_cast<Ui*>(context)->theme.style(child); return TRUE; }, reinterpret_cast<LPARAM>(ui));
                const auto* bounds = reinterpret_cast<RECT*>(lparam); SetWindowPos(window, nullptr, bounds->left, bounds->top, bounds->right - bounds->left, bounds->bottom - bounds->top, SWP_NOZORDER | SWP_NOACTIVATE); layout(*ui); return 0;
            }
            case WM_ERASEBKGND: return 1;
            case WM_TIMER:
                if(wparam==kGalleryQueryTimer){KillTimer(window,kGalleryQueryTimer);if(ui->page==Page::Gallery)action(*ui,LookupPerson,BN_CLICKED);return 0;}
                if(wparam==kSearchDisplayTimer){
                    if(ui->page==Page::Search){
                        const auto state=ui->app.current();
                        const bool fresh=searchOverlayFresh(std::chrono::duration_cast<std::chrono::milliseconds>(
                            std::chrono::steady_clock::now().time_since_epoch()).count(),state->preview_at_ms,state->analysis_at_ms);
                        // New snapshots trigger their own paint; the timer only expires old overlays.
                        // 新快照自行触发绘制；定时器只负责清除过期叠加层，避免重复重绘。
                        if(fresh!=ui->search_overlay_fresh)update(*ui);
                    }
                    else if(ui->page==Page::Gallery)prefetchGallery(*ui);
                    return 0;
                }
                if (wparam != kWebsiteToastTimer) break;
                KillTimer(window, kWebsiteToastTimer);
                ShowWindow(child(window, WebsiteToast), SW_HIDE);
                return 0;
            case WM_CONTEXTMENU:
                if(ui->page==Page::Gallery&&reinterpret_cast<HWND>(wparam)==child(window,People)&&!ui->app.current()->busy){
                    POINT position{GET_X_LPARAM(lparam),GET_Y_LPARAM(lparam)};
                    if(position.x==-1&&position.y==-1){RECT bounds{};GetWindowRect(child(window,People),&bounds);position={bounds.left+20,bounds.top+30};}
                    else{auto local=position;ScreenToClient(child(window,People),&local);LVHITTESTINFO hit{};hit.pt=local;const int index=ListView_HitTest(child(window,People),&hit);
                        ListView_SetItemState(child(window,People),-1,0,LVIS_SELECTED);if(index>=0)ListView_SetItemState(child(window,People),index,LVIS_SELECTED|LVIS_FOCUSED,LVIS_SELECTED|LVIS_FOCUSED);}
                    galleryMenu(*ui,position);return 0;
                }break;
            case kRevealFocusedControl: {
                const int id = GetDlgCtrlID(reinterpret_cast<HWND>(lparam));
                if (ui->page == Page::Home && id >= HomeBase && id < HomeBase + kFeatureCount)
                    scrollHome(*ui, homeGeometry(*ui).reveal(id - HomeBase, ui->home_scroll));
                return 0;
            }
            case WM_LBUTTONUP:
                if(ui->page==Page::Comparison){
                    const auto& area=ui->canvas;const ComparisonLayout view({area.left,area.top,area.right,area.bottom},static_cast<int>(ui->theme.dpi));
                    const int slot=view.slotAt(GET_X_LPARAM(lparam),GET_Y_LPARAM(lparam));if(slot>=0)action(*ui,slot?PickB:PickA,BN_CLICKED);return 0;
                }break;
            case WM_MOUSEWHEEL: {
                if (ui->page == Page::Home) { scrollHome(*ui, ui->home_scroll - GET_WHEEL_DELTA_WPARAM(wparam) / WHEEL_DELTA * 84); return 0; }
                const POINT pointer{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
                const auto hover = WindowFromPoint(pointer);
                const auto photo = ui->image_search.window();
                if (ui->page == Page::ImageSearch && (hover == photo || IsChild(photo, hover))) return SendMessageW(photo, message, wparam, lparam);
                return IsWindowVisible(ui->pane) ? SendMessageW(ui->pane, message, wparam, lparam) : 0;
            }
            case WM_DRAWITEM: {
                const auto& item = *reinterpret_cast<DRAWITEMSTRUCT*>(lparam);
                if (item.CtlID >= HomeBase && item.CtlID < HomeBase + kFeatureCount) {
                    const auto& feature = page_info[static_cast<int>(feature_pages[item.CtlID - HomeBase])];
                    const bool enabled = !(item.itemState & ODS_DISABLED);
                    const bool active = enabled && ((item.itemState & ODS_SELECTED) || GetPropW(item.hwndItem, L"HiFaceHover"));
                    fill(item.hDC, item.rcItem, home_colors::background);
                    card(item.hDC, item.rcItem, active ? home_colors::hover : home_colors::surface,
                         active ? home_colors::hover_line : home_colors::line, ui->theme.px(12));
                    RECT number=item.rcItem;number.left+=ui->theme.px(14);number.top+=ui->theme.px(14);number.right=number.left+ui->theme.px(28);number.bottom=number.top+ui->theme.px(28);
                    card(item.hDC,number,home_colors::hover,home_colors::hover_line,ui->theme.px(8));
                    label(item.hDC,std::to_wstring(item.CtlID-HomeBase+1).c_str(),number,ui->theme.body,home_colors::text,DT_CENTER|DT_VCENTER|DT_SINGLELINE);
                    RECT title=item.rcItem;title.left+=ui->theme.px(52);title.right-=ui->theme.px(14);title.top+=ui->theme.px(12);title.bottom=title.top+ui->theme.px(30);
                    label(item.hDC,feature.title,title,ui->theme.result,enabled?home_colors::text:home_colors::surface_secondary,DT_LEFT|DT_VCENTER|DT_SINGLELINE|DT_END_ELLIPSIS);
                    RECT detail=item.rcItem;detail.left+=ui->theme.px(16);detail.right-=ui->theme.px(16);detail.top=title.bottom+ui->theme.px(8);detail.bottom-=ui->theme.px(10);
                    label(item.hDC,feature.description,detail,ui->theme.small,home_colors::surface_secondary,DT_LEFT|DT_WORDBREAK|DT_END_ELLIPSIS);
                    if (item.itemState & ODS_FOCUS) { RECT focus = item.rcItem; InflateRect(&focus, -4, -4); DrawFocusRect(item.hDC, &focus); }
                    return TRUE;
                }
                if (ui->page == Page::Home) ui->theme.homeButton(item, item.CtlID == HomeVersion);
                else ui->theme.button(item, item.CtlID == Primary || item.CtlID == Open, item.CtlID == Parameters && ui->parameters_open, false);
                return TRUE;
            }
            case WM_CTLCOLORSTATIC: case WM_CTLCOLOREDIT: case WM_CTLCOLORBTN: {
                const auto dc = reinterpret_cast<HDC>(wparam); const auto control = reinterpret_cast<HWND>(lparam);
                const auto state = ui->app.current();
                const bool panel = GetParent(control) == ui->pane || GetDlgCtrlID(control) == WebsiteToast;
                if (ui->page == Page::Home && !panel) {
                    SetTextColor(dc, GetDlgCtrlID(control) == Status && (state->error || state->fatal) ? home_colors::error : home_colors::secondary);
                    SetBkColor(dc, home_colors::background);
                    return reinterpret_cast<LRESULT>(ui->theme.home_background);
                }
                SetTextColor(dc, GetDlgCtrlID(control) == Status && (state->error || state->fatal) ? colors::error : GetDlgCtrlID(control) == Metrics ? colors::muted : colors::ink);
                SetBkColor(dc, panel || message == WM_CTLCOLOREDIT ? colors::surface : colors::background);
                return reinterpret_cast<LRESULT>(panel || message == WM_CTLCOLOREDIT ? ui->theme.surface : ui->theme.background);
            }
            case WM_NOTIFY: {
                const auto* event = reinterpret_cast<NMHDR*>(lparam);
                if(event->idFrom==People&&event->code==NM_DBLCLK&&!ui->rendering_list){action(*ui,UpdatePerson,BN_CLICKED);return 0;}
                if (event->idFrom == People && event->code == LVN_ITEMCHANGED && !ui->rendering_list && !ui->app.current()->busy) {
                    const int index = ListView_GetNextItem(child(window, People), -1, LVNI_SELECTED);
                    if (index >= 0 && static_cast<size_t>(index) < ui->rendered_people.size()) {
                        const auto& person = ui->rendered_people[static_cast<size_t>(index)];
                        setText(window, PersonId, widen(person.id)); setText(window, Group, widen(person.group)); setText(window, Tag, widen(person.tag));
                    }
                }
                return 0;
            }
            case WM_COMMAND: action(*ui, LOWORD(wparam), HIWORD(wparam)); return 0;
            case kFrameReady: ui->app.notification_pending = false; update(*ui); return 0;
            case WM_PAINT: paint(*ui); return 0;
            case WM_CLOSE:
                if((ui->return_after_save||ui->return_after_reference)&&ui->pending_command)return 0;
                if(ui->app.current()->importing&&MessageBoxW(window,L"停止导入并退出？已保存批次会保留。",L"停止导入",MB_YESNO|MB_DEFBUTTON2|MB_ICONQUESTION)!=IDYES)return 0;
                ui->app.stop(); DestroyWindow(window); return 0;
            case WM_DESTROY: PostQuitMessage(0); return 0;
        }
    } catch (const std::exception& error) {
        writeLog(error.what()); MessageBoxW(window, widen(error.what()).c_str(), L"HiFace", MB_OK | MB_ICONERROR);
        if (message == WM_CREATE) return -1;
        return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}
}
// Startup: UI COM/DPI -> controls -> worker -> Windows message loop. App::stop
// joins the worker before UI/COM teardown, including failure/early-exit paths.
// 启动顺序：UI COM/DPI、控件、工作线程、消息循环；销毁 UI/COM 前等待工作线程退出。
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    try {
        ComApartment com(true); initializeLog("demo");
        INITCOMMONCONTROLSEX common{sizeof(common), ICC_LISTVIEW_CLASSES | ICC_STANDARD_CLASSES}; InitCommonControlsEx(&common);
        Ui ui; ui.app.database = demoDataDirectory() / L"hiface-search.db";
        int argc = 0; wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
        if (!argv) throw std::runtime_error("Cannot parse command line");
        struct Arguments { wchar_t** values; ~Arguments() { LocalFree(values); } } arguments{argv};
        for (int i = 1; i < argc; ++i) {
            const std::wstring option = argv[i];
            if (i + 1 >= argc) throw std::runtime_error("Usage: hiface_demo [--database FILE] [--camera INDEX]");
            if (option == L"--database") ui.app.database = argv[++i];
            else if (option == L"--camera") {
                const std::wstring value = argv[++i]; size_t end = 0;
                const auto index = std::stoul(value, &end);
                if (end != value.size() || index > 32) throw std::runtime_error("Invalid camera index");
                ui.initial_camera = static_cast<unsigned>(index);
            }
            else throw std::runtime_error("Unknown Demo option");
        }
        WNDCLASSEXW type{}; type.cbSize = sizeof(type); type.lpfnWndProc = windowProcedure; type.hInstance = instance;
        type.hIcon = static_cast<HICON>(LoadImageW(instance, MAKEINTRESOURCEW(101), IMAGE_ICON,
            GetSystemMetrics(SM_CXICON), GetSystemMetrics(SM_CYICON), LR_SHARED));
        type.hIconSm = static_cast<HICON>(LoadImageW(instance, MAKEINTRESOURCEW(101), IMAGE_ICON,
            GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_SHARED));
        type.lpszClassName = L"HiFaceWindowsDemo"; type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        type.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        if (!RegisterClassExW(&type)) throw std::runtime_error("Cannot register Demo window");
        const auto work = workingArea(nullptr);
        const int width = std::max(1, std::min(1440, static_cast<int>(work.right - work.left) - 16));
        const int height = std::max(1, std::min({800,static_cast<int>(work.bottom-work.top)-16,width*2/3}));
        HWND window = CreateWindowExW(0, type.lpszClassName, L"HiFace Windows Demo",
            WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, width, height, nullptr, nullptr, instance, &ui);
        if (!window) throw std::runtime_error("Cannot create Demo window");
        ShowWindow(window, show); UpdateWindow(window);
        MSG message{}; BOOL result;
        while ((result = GetMessageW(&message, nullptr, 0, 0)) > 0) {
            if (!shortcut(ui, message) && !IsDialogMessageW(window, &message)) { TranslateMessage(&message); DispatchMessageW(&message); }
        }
        if (result == -1) throw std::runtime_error("Windows message loop failed");
        return 0;
    } catch (const std::exception& error) {
        writeLog(error.what()); MessageBoxW(nullptr, widen(error.what()).c_str(), L"HiFace startup failed", MB_OK | MB_ICONERROR); return 1;
    }
}
