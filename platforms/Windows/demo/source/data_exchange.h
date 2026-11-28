#pragma once
#include "types.h"
#include <functional>
#include <unordered_map>
namespace hiface_demo {
// Worker-owned metadata listing. Exact ID lookup never shares the selected edit ID.
class GalleryListing {
public:
    std::vector<Person> people;
    // total counts the whole library; filtered counts only the current management query.
    uint64_t total = 0, filtered = 0;
    // Database offset consumed so far, independent of duplicate IDs merged into visible rows.
    uint32_t next = 0;
    bool more = false;
    void reset(const Gallery& database, const std::string& query, const std::string& group = {}, const std::string& tag = {});
    void append(const Gallery& database, const std::function<void(const std::string&)>& on_row = {});
private:
    std::string query_, group_, tag_;
    // Face ID to visible-row index, used to update a repeated ID without appending a duplicate.
    std::unordered_map<std::string, size_t> positions_;
};
struct ImportProgress {
    size_t processed = 0, total = 0, saved = 0, failed = 0;
    bool stopped = false;
};
using ImportCallback = std::function<bool(const ImportProgress&)>;
using ImportSavedCallback = std::function<void(const std::string&)>;
ImportProgress importDataset(Gallery& database, const std::filesystem::path& file,
    const ImportCallback& progress = {}, const ImportSavedCallback& saved = {});
size_t exportDataset(const Gallery& database, const std::filesystem::path& file, const std::string& group = {}, const std::string& tag = {});
}
