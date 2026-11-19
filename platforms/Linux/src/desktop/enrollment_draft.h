#pragma once
#include "gallery.h"
namespace hiface_linux_demo {
// Worker-owned HF1; only the aligned preview and pending flag reach the UI.
// 工作线程持有 HF1；仅将对齐预览和待确认标记交给界面。
class EnrollmentDraft {
public:
    bool pending() const { return !feature_.empty(); }
    void clear() { feature_.clear(); }
    void stage(const Feature& feature) { clear(); const auto text = encodeFeature(feature); feature_ = text.data(); }
    // Keep the confirmed sample available for retry if validation or the database write fails.
    void save(Database& database, const std::string& id, const std::string& group, const std::string& tag, bool overwrite = false) {
        require(pending(), "Capture a face before confirming enrollment");
        require(id.find_first_not_of(" \t\r\n") != std::string::npos && id.find_first_of("\r\n") == std::string::npos
            && id.find('\0') == std::string::npos && group.find('\0') == std::string::npos && tag.find('\0') == std::string::npos
            && id.size() <= HIFACE_SEARCH_MAX_TEXT_BYTES && group.size() <= HIFACE_SEARCH_MAX_TEXT_BYTES
            && tag.size() <= HIFACE_SEARCH_MAX_TEXT_BYTES, "Enter a nonempty face ID and valid metadata (at most 1024 UTF-8 bytes)");
        saveEntry(database, {id, feature_, group, tag}, overwrite); clear();
    }
private:
    std::string feature_;
};
}
