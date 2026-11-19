#pragma once
#include <cstddef>
#include <vector>
namespace hiface_demo {
enum class Page { Detection, Reference, Verification, Liveness, Search, ImageSearch, Comparison, Gallery, CameraSettings, Enrollment, Home, Recognition };
struct PageInfo { const wchar_t* title; const wchar_t* description; bool camera; };
inline constexpr PageInfo page_info[] = {
    {L"实时人脸检测", L"五点与双眼、鼻、嘴、脸部轮廓", true},
    {L"人脸采集", L"采集预览、确认 Face ID 后保存基准", true},
    {L"1:1 人脸识别 + 活体检测", L"基准比对、动作挑战和静默活体", true},
    {L"仅活体检测", L"动作挑战与静默活体检测", true},
    {L"人脸搜索识别", L"RGB相机搜索识别，1:N搜索活体也用RGB相机", true},
    {L"图片人脸搜索", L"本地图片逐脸搜索，无需摄像头", false},
    {L"双图片 1:1 比对", L"选择两张图片，比较最大人脸", false},
    {L"人脸库管理", L"人员维护、分页、JSON 和图片导入", false},
    {L"SDK参数设置", L"设备、分辨率、旋转、镜像与预览", true},
    {L"人脸录入", L"独立采集、预览确认后保存到人脸库", true},
    {L"功能首页", L"选择一个独立功能开始演示", false},
    {L"人脸识别", L"通过相机进行 1:1 人脸识别与活体检测", false}
};
inline constexpr int kPageCount = int(sizeof(page_info) / sizeof(page_info[0]));
inline constexpr int kFeatureCount = 6;
inline constexpr int kStatusControl = 950;
inline constexpr int kBackControl = 900, kParametersControl = 901, kHomePreviousControl = 902, kHomeNextControl = 903;
// Capture, verification and liveness belong to the recognition menu.
inline constexpr Page feature_pages[] = {Page::Detection, Page::Recognition,
    Page::Search, Page::Comparison, Page::ImageSearch, Page::CameraSettings};
inline constexpr Page recognition_pages[] = {Page::Verification, Page::Liveness};
inline bool menuPage(Page page) { return page == Page::Home || page == Page::Recognition; }
// Route inventory for validation, not a global navigation sidebar.
// 完整路由用于检查，不生成全局侧栏。
inline constexpr Page navigation_pages[] = {Page::Home, Page::Detection, Page::Reference, Page::Verification, Page::Liveness,
    Page::Search, Page::Comparison, Page::ImageSearch, Page::CameraSettings, Page::Enrollment, Page::Gallery, Page::Recognition};
static_assert(sizeof(feature_pages) / sizeof(Page) == kFeatureCount);
static_assert(sizeof(navigation_pages) / sizeof(Page) == kPageCount);
inline bool isCapturePage(Page page) { return page == Page::Reference || page == Page::Enrollment; }
inline bool guidedRecognition(Page page) { return page == Page::Verification || page == Page::Liveness; }
inline bool usesCamera(Page page) { return page_info[static_cast<std::size_t>(page)].camera; }
inline bool startsCameraOnEntry(Page page, bool parameters_valid = true) {
    return parameters_valid && usesCamera(page) && page != Page::CameraSettings && page != Page::Verification;
}
inline int homeIndex(Page page) {
    for (int i = 0; i < kFeatureCount; ++i) if (feature_pages[i] == page) return i;
    return -1;
}
inline bool hasFeatureParameters(Page page) {
    return page == Page::Detection || page == Page::Verification || page == Page::Liveness || page == Page::Search;
}
struct PageHistory {
    std::vector<Page> pages;
    Page parent(Page current) const {
        if (!pages.empty()) return pages.back();
        if (guidedRecognition(current)) return Page::Recognition;
        return current == Page::Enrollment || current == Page::Gallery ? Page::Search : Page::Home;
    }
    void moved(Page from, Page next) {
        if (from == next) return;
        if (!pages.empty() && pages.back() == next) pages.pop_back();
        else if (next == Page::Home) pages.clear();
        else if (homeIndex(next) >= 0) pages = {Page::Home};
        else if (from == Page::Home) pages = {Page::Home,
            guidedRecognition(next) ? Page::Recognition : Page::Search};
        else pages.push_back(from);
    }
};
}
