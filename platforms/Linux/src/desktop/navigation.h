#pragma once
#include "rgbir/page.h"
#include <string_view>
namespace hiface_linux_demo {
struct DemoPage {
    const char* route;
    const char* title;
    const char* description;
    char camera_mode;
};
// Each feature owns a route; camera rendering and SDK lifetime stay shared.
// 每个功能拥有独立路由，相机绘制与 SDK 生命周期仍共用。
inline constexpr DemoPage demo_pages[] = {
    {"detection", "Live Detection", "View facial landmarks and contours", 'D'},
    {"capture", "Face Capture", "Capture a face and save its feature", 'C'},
    {"verification", "1:1 Face Verification", "Select a Face ID, then verify with liveness", 'V'},
    {"liveness", "Liveness", "Random action challenges and passive liveness detection", 'L'},
    {"camera", "Face Search and Recognition", "RGB camera search and recognition; 1:N liveness also uses the RGB camera", 'S'},
    {RgbIrSearchPage::route, RgbIrSearchPage::title, "RGB camera search and recognition. The IR camera checks liveness.", 0},
    {"images", "Photo 1:1 Comparison", "Compare faces in two photos", 0},
    {"image-search", "Image Face Search", "Find faces in a photo and search the face library", 0},
    {"camera-settings", "SDK Settings", "Set analysis resolution and coordinate mirroring", 0},
    {"enrollment", "Face enrollment", "Capture, review the preview, then confirm saving to the library", 'E'},
    {"gallery", "Face library", "Manage identities and import or export HF1 JSON", 0},
    {"settings", "Feature settings", "Adjust parameters, then apply to save", 0},
    {"references", "Select a Face ID", "Choose a reference saved by Face Capture", 0},
};
// Embedded keeps Android's nine entries; ordinary desktop omits RGB/IR entirely.
// 嵌入式保留九项入口；普通桌面仅八项，不展示双目占位页。
inline constexpr int home_page_count = 9;
inline int homePageCount(bool embedded) { return embedded ? home_page_count : home_page_count-1; }
inline const DemoPage& homePageAt(int index,bool embedded) { return demo_pages[index+(!embedded && index>=5?1:0)]; }
inline bool homePage(std::string_view route,bool embedded=true) {
    for (int i = 0; i < homePageCount(embedded); ++i) if (homePageAt(i,embedded).route == route) return true;
    return false;
}
inline const DemoPage* demoPage(std::string_view route) {
    for (const auto& page : demo_pages) if (page.route == route) return &page;
    return nullptr;
}
inline bool cameraPage(std::string_view route) {
    const auto* page = demoPage(route);
    return page && page->camera_mode;
}
inline bool pageAvailable(std::string_view route,bool embedded) {
    return demoPage(route) && (embedded || route!=RgbIrSearchPage::route);
}
inline constexpr const char* smoke_pages[] = {
    "camera", "images", "gallery", "settings", "image-search", "home",
    "detection", "capture", "verification", "liveness", "enrollment", "camera-settings", "references",
    RgbIrSearchPage::route
};
inline constexpr unsigned smoke_page_count = sizeof(smoke_pages) / sizeof(smoke_pages[0]);
inline unsigned smokePageCount(bool embedded) { return smoke_page_count-(embedded?0:1); }
}
