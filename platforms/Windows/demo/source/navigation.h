#pragma once
#include <cstddef>
#include <vector>
namespace hiface_demo {
enum class Page { Detection, Reference, Verification, Liveness, Search, ImageSearch, Comparison, Gallery, CameraSettings, Enrollment, Home };
struct PageInfo { const wchar_t* title; const wchar_t* description; bool camera; };
inline constexpr PageInfo page_info[] = {
    {L"实时人脸检测", L"人脸框、五点、468 点与头姿", true},
    {L"人脸采集", L"采集人脸并保存参考特征", true},
    {L"动态 1:1 验证", L"基准比对、动作挑战和静默活体", true},
    {L"活体检测", L"动作挑战与静默活体检测", true},
    {L"人脸搜索识别", L"RGB相机搜索识别，1:N搜索活体也用RGB相机", true},
    {L"图片人脸搜索", L"本地图片逐脸搜索，无需摄像头", false},
    {L"双图片 1:1 比对", L"选择两张图片，比较最大人脸", false},
    {L"人脸库管理", L"人员维护、分页、JSON 和图片导入", false},
    {L"SDK参数设置", L"设备、分辨率、旋转、镜像与预览", true},
    {L"人脸录入", L"独立采集、预览确认后保存到人脸库", true},
    {L"功能首页", L"选择一个独立功能开始演示", false}
};
inline constexpr int kPageCount = int(sizeof(page_info) / sizeof(page_info[0]));
inline constexpr int kFeatureCount = 8;
inline constexpr int kBackControl = 900, kParametersControl = 901, kHomePreviousControl = 902, kHomeNextControl = 903;
// Eight primary features. Enrollment/library are child destinations.
// 首页保留八项；录入、人脸库由所属功能页进入。
inline constexpr Page feature_pages[] = {Page::Detection, Page::Reference, Page::Verification, Page::Liveness,
    Page::Search, Page::Comparison, Page::ImageSearch, Page::CameraSettings};
// Route inventory for validation, not a global navigation sidebar.
// 完整路由用于检查，不生成全局侧栏。
inline constexpr Page navigation_pages[] = {Page::Home, Page::Detection, Page::Reference, Page::Verification, Page::Liveness,
    Page::Search, Page::Comparison, Page::ImageSearch, Page::CameraSettings, Page::Enrollment, Page::Gallery};
static_assert(sizeof(feature_pages) / sizeof(Page) == kFeatureCount);
static_assert(sizeof(navigation_pages) / sizeof(Page) == kPageCount);
inline bool usesCamera(Page page) { return page_info[static_cast<std::size_t>(page)].camera; }
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
        return current == Page::Enrollment || current == Page::Gallery ? Page::Search : Page::Home;
    }
    void moved(Page from, Page next) {
        if (from == next) return;
        if (!pages.empty() && pages.back() == next) pages.pop_back();
        else if (next == Page::Home) pages.clear();
        else if (homeIndex(next) >= 0) pages = {Page::Home};
        else if (from == Page::Home) pages = {Page::Home, Page::Search};
        else pages.push_back(from);
    }
};
}
