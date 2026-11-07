#pragma once
#include "hiface/frame.hpp"
#include "hiface/error.hpp"
#include <array>
#include <filesystem>
#include <string>

namespace hiface {
struct Person {
    std::string id, group, tag, feature;
    int64_t updated = 0;
};
struct SearchMatch { Person entry; float score = 0; };
// Database operations do not initialize inference or load models. Use one worker
// per owner; strings returned here own their bytes beyond the C result lifetime.
// 数据库操作不初始化推理或加载模型；每个持有者使用一个工作线程，返回字符串独占字节，生命周期超出 C 结果。
// IDs are nonempty; IDs/group/tag are at most 1024 UTF-8 bytes and contain no NUL.
// Metadata and paths are never silently truncated at the C string boundary.
// ID 非空；ID/分组/标签最多 1024 个 UTF-8 字节且不得包含 NUL，路径和元数据不静默截断。
class Database {
public:
    explicit Database(const std::filesystem::path& path);
    ~Database();
    Database(const Database&) = delete;
    Database& operator=(const Database&) = delete;
    HiFaceSearchDatabaseHandle nativeHandle() const { return database_; }
    uint64_t count(const std::string& group = {}, const std::string& tag = {}) const;
    std::vector<Person> list(uint32_t offset = 0, uint32_t limit = 100,
        const std::string& group = {}, const std::string& tag = {}, bool features = false, bool recent = false) const;
    Person get(const std::string& id) const;
    // One atomic batch: overwrite=false rejects existing IDs; true updates them.
    // 单次原子批量写入；false 拒绝已有 ID，true 按 ID 新增或覆盖。
    void save(const std::vector<Person>& people, bool overwrite);
    uint64_t remove(const std::string& id);
    void updateMetadata(const std::string& id, const std::string& group, const std::string& tag);
    void releaseMemory();
    bool contains(const std::string& id) const;
    // Exact HF1 search, using the shared Q7 decoder and Core similarity.
    // Matches own their metadata; no model or camera session is needed.
    // 使用共享 Q7 解码和 Core 相似度进行精确 HF1 搜索；匹配结果独占元数据，不需要模型或相机会话。
    std::vector<SearchMatch> search(const std::string& feature, uint32_t top_k = 1,
        float threshold = HIFACE_DEFAULT_VERIFICATION_THRESHOLD,
        const std::string& group = {}, const std::string& tag = {}) const;
private:
    HiFaceSearchDatabaseHandle database_ = nullptr;
};
std::string encodeFeature(const Feature& feature);
Feature decodeFeature(const std::string& text);
float compareFeatureText(const std::string& left, const std::string& right);
}
