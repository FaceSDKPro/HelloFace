#pragma once
#include "rgbir/page.h"
#include "rgbir/settings.h"
#include <atomic>
#include <functional>
#include <thread>

namespace hiface_linux_demo::rgbir {
// The desktop workflow owns this object for one dual-camera search run.
// Destruction joins the search and capture threads before either camera is reused.
class DesktopSearch {
public:
    using Publish = std::function<void(std::shared_ptr<const RgbIrView>)>;
    DesktopSearch(std::string database, RgbIrSettings settings, Publish publish, bool diagnostics);
    ~DesktopSearch();
private:
    void run(const std::string& database, const RgbIrSettings& settings, const Publish& publish, bool diagnostics);
    std::atomic<bool> stop_{false};
    std::thread worker_;
};
}
