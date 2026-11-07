#pragma once
#include "types.h"
#include <functional>
#include <unordered_map>
namespace hiface_demo {
// Worker-owned metadata listing. Exact ID lookup never shares the selected edit ID.
class GalleryListing {
public:
    std::vector<Person> people;
    uint64_t total = 0, filtered = 0;
    uint32_t next = 0;
    bool more = false;
    void reset(const Gallery& database, const std::string& query, const std::string& group = {}, const std::string& tag = {});
    void append(const Gallery& database);
private:
    std::string query_, group_, tag_;
    std::unordered_map<std::string, size_t> positions_;
};
struct ImportProgress {
    size_t processed = 0, total = 0, saved = 0, failed = 0;
    bool stopped = false;
};
using ImportCallback = std::function<bool(const ImportProgress&)>;
ImportProgress importDataset(Gallery& database, const std::filesystem::path& file, const ImportCallback& progress = {});
size_t exportDataset(const Gallery& database, const std::filesystem::path& file, const std::string& group = {}, const std::string& tag = {});
}
