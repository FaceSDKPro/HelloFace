#include "data_exchange.h"
#include "enrollment_draft.h"
#include <algorithm>
#include <chrono>
#include <fstream>
#include <map>
#ifdef _WIN32
#include <windows.h>
#endif
namespace hiface_demo {
void GalleryListing::reset(const Gallery& database, const std::string& query, const std::string& group, const std::string& tag) {
    GalleryListing fresh;
    fresh.query_ = normalizeMetadata(query); fresh.group_ = normalizeMetadata(group); fresh.tag_ = normalizeMetadata(tag);
    fresh.total = database.count();
    if (!fresh.query_.empty()) {
        try {
            auto person = database.get(fresh.query_);
            person.feature.clear(); // Never put HF1 payloads into UI snapshots.
            fresh.people.push_back(std::move(person));
        } catch (const SdkError& error) {
            if (error.status != HIFACE_STATUS_NOT_FOUND) throw;
        }
        fresh.filtered = fresh.people.size(); fresh.next = static_cast<uint32_t>(fresh.people.size());
    } else {
        fresh.filtered = database.count(fresh.group_, fresh.tag_); fresh.more = fresh.filtered > 0;
        fresh.append(database);
    }
    *this = std::move(fresh);
}
void GalleryListing::append(const Gallery& database) {
    if (!more || !query_.empty()) return;
    auto batch = database.list(next, 100, group_, tag_);
    // Read before mutating the cursor so a failed append can be retried.
    const auto count = database.count(group_, tag_);
    for (auto& person : batch) {
        person.feature.clear();
        // Keep an ID index across pages: repeatedly scanning all loaded rows is
        // quadratic for large libraries. Overlapping pages still update one row.
        // 跨页维护 ID 索引，避免大库反复扫描；重叠分页仍只更新已有一行。
        const auto found = positions_.find(person.id);
        if (found != positions_.end()) people[found->second] = std::move(person);
        else {
            const auto id = person.id;
            people.push_back(std::move(person));
            try { positions_.emplace(id, people.size() - 1); }
            catch (...) { people.pop_back(); throw; }
        }
    }
    next += static_cast<uint32_t>(batch.size()); filtered = count;
    more = !batch.empty() && next < filtered;
}
namespace {
// The interchange format is Android's JSON envelope, parsed without a runtime
// dependency. Bounds, escaped Unicode, duplicate keys and trailing input matter
// here because a malformed import must never silently change identity metadata.
// 交换格式采用 Android 的 JSON 外层结构，无额外运行时依赖；严格处理边界、Unicode 转义、重复键和尾部输入，避免损坏的导入静默改变身份元数据。
struct Json {
    enum Kind { Object, Array, String, Number, Other } kind = Other;
    std::string text;
    std::map<std::string, Json> object;
    std::vector<Json> array;
    const Json& field(const char* key) const {
        if (kind != Object || !object.count(key)) throw std::runtime_error(std::string("Missing JSON field: ") + key);
        return object.at(key);
    }
    std::string string() const { if (kind != String) throw std::runtime_error("Expected JSON string"); return text; }
    std::string optional(const char* key) const {
        const auto found = object.find(key);
        return found == object.end() || (found->second.kind == Other && found->second.text == "null") ? "" : found->second.string();
    }
    int64_t integer() const {
        if (kind != Number || text.find_first_of(".eE") != std::string::npos) throw std::runtime_error("Expected JSON integer");
        size_t end = 0; auto value = std::stoll(text, &end);
        if (end != text.size()) throw std::runtime_error("Invalid JSON integer");
        return value;
    }
};
class JsonReader {
public:
    explicit JsonReader(std::string text) : text_(std::move(text)) {}
    Json read() { auto value = parse(0); space(); if (at_ != text_.size()) fail(); return value; }
private:
    std::string text_; size_t at_ = 0;
    [[noreturn]] void fail() const { throw std::runtime_error("Invalid dataset JSON near byte " + std::to_string(at_)); }
    void validateUtf8(const std::string& text) const {
        for (size_t i = 0; i < text.size();) {
            uint32_t point = static_cast<unsigned char>(text[i++]);
            if (point < 0x80) continue;
            unsigned following = 0; uint32_t minimum = 0;
            if (point >= 0xc2 && point <= 0xdf) { point &= 31; following = 1; minimum = 0x80; }
            else if (point >= 0xe0 && point <= 0xef) { point &= 15; following = 2; minimum = 0x800; }
            else if (point >= 0xf0 && point <= 0xf4) { point &= 7; following = 3; minimum = 0x10000; }
            else fail();
            for (unsigned j = 0; j < following; ++j) {
                if (i == text.size()) fail();
                const auto byte = static_cast<unsigned char>(text[i++]); if ((byte & 0xc0) != 0x80) fail();
                point = (point << 6) | (byte & 63);
            }
            if (point < minimum || point > 0x10ffff || (point >= 0xd800 && point <= 0xdfff)) fail();
        }
    }
    void space() { while (at_ < text_.size() && (text_[at_] == ' ' || text_[at_] == '\t' || text_[at_] == '\r' || text_[at_] == '\n')) ++at_; }
    bool take(char c) { space(); if (at_ < text_.size() && text_[at_] == c) { ++at_; return true; } return false; }
    uint32_t hex4() {
        uint32_t value = 0;
        for (int i = 0; i < 4; ++i) {
            if (at_ >= text_.size()) fail();
            const char c = text_[at_++];
            const int digit = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
            if (digit < 0) fail(); value = value * 16 + static_cast<uint32_t>(digit);
        }
        return value;
    }
    std::string string() {
        if (!take('"')) fail();
        std::string result;
        while (at_ < text_.size()) {
            unsigned char c = text_[at_++];
            if (c == '"') { validateUtf8(result); return result; }
            if (c < 32) fail();
            if (c != '\\') { result += static_cast<char>(c); continue; }
            if (at_ >= text_.size()) fail(); c = text_[at_++];
            switch (c) {
                case '"': case '\\': case '/': result += static_cast<char>(c); break;
                case 'b': result += '\b'; break; case 'f': result += '\f'; break;
                case 'n': result += '\n'; break; case 'r': result += '\r'; break; case 't': result += '\t'; break;
                case 'u': {
                    uint32_t point = hex4();
                    if (point >= 0xd800 && point <= 0xdbff) {
                        if (at_ + 2 > text_.size() || text_.substr(at_, 2) != "\\u") fail();
                        at_ += 2; const auto low = hex4();
                        if (low < 0xdc00 || low > 0xdfff) fail();
                        point = 0x10000 + ((point - 0xd800) << 10) + low - 0xdc00;
                    } else if (point >= 0xdc00 && point <= 0xdfff) fail();
                    if (point < 0x80) result += static_cast<char>(point);
                    else if (point < 0x800) { result += static_cast<char>(0xc0 | (point >> 6)); result += static_cast<char>(0x80 | (point & 63)); }
                    else if (point < 0x10000) { result += static_cast<char>(0xe0 | (point >> 12)); result += static_cast<char>(0x80 | ((point >> 6) & 63)); result += static_cast<char>(0x80 | (point & 63)); }
                    else { result += static_cast<char>(0xf0 | (point >> 18)); result += static_cast<char>(0x80 | ((point >> 12) & 63)); result += static_cast<char>(0x80 | ((point >> 6) & 63)); result += static_cast<char>(0x80 | (point & 63)); }
                    break;
                }
                default: fail();
            }
        }
        fail();
    }
    Json parse(unsigned depth) {
        if (depth > 32) fail();
        space(); if (at_ >= text_.size()) fail();
        Json value;
        if (text_[at_] == '"') { value.kind = Json::String; value.text = string(); return value; }
        if (take('{')) {
            value.kind = Json::Object;
            if (!take('}')) do {
                auto key = string(); if (!take(':')) fail();
                if (!value.object.emplace(std::move(key), parse(depth + 1)).second) fail();
                if (take('}')) return value;
            } while (take(',')); else return value;
            fail();
        }
        if (take('[')) {
            value.kind = Json::Array;
            if (!take(']')) do { value.array.push_back(parse(depth + 1)); if (take(']')) return value; } while (take(','));
            else return value;
            fail();
        }
        const size_t begin = at_;
        while (at_ < text_.size() && text_[at_] != ',' && text_[at_] != '}' && text_[at_] != ']' && text_[at_] != ' ' && text_[at_] != '\r' && text_[at_] != '\n' && text_[at_] != '\t') ++at_;
        value.text = text_.substr(begin, at_ - begin);
        if (value.text == "null" || value.text == "true" || value.text == "false") return value;
        // Interchange files use integer fields only; reject non-JSON spellings.
        // 交换文件只使用整数字段，拒绝不符合 JSON 的数值写法。
        if (value.text.empty()) fail();
        size_t i = value.text.front() == '-' ? 1 : 0;
        if (i == value.text.size()) fail();
        if (value.text[i] == '0' && i + 1 != value.text.size()) fail();
        for (; i < value.text.size(); ++i) if (value.text[i] < '0' || value.text[i] > '9') fail();
        value.kind = Json::Number; return value;
    }
};
std::string escaped(const std::string& text) {
    static const char hex[] = "0123456789abcdef";
    std::string result = "\"";
    for (unsigned char c : text) {
        if (c == '"' || c == '\\') { result += '\\'; result += static_cast<char>(c); }
        else if (c < 32) { result += "\\u00"; result += hex[c >> 4]; result += hex[c & 15]; }
        else result += static_cast<char>(c);
    }
    return result + '"';
}
}
ImportProgress importDataset(Gallery& database, const std::filesystem::path& file, const ImportCallback& callback) {
    std::ifstream input(file, std::ios::binary | std::ios::ate);
    if (!input || input.tellg() <= 0 || input.tellg() > 64 * 1024 * 1024) throw std::runtime_error("Expected a dataset JSON file of at most 64 MiB");
    std::string text(static_cast<size_t>(input.tellg()), '\0'); input.seekg(0);
    if (!input.read(text.data(), static_cast<std::streamsize>(text.size()))) throw std::runtime_error("Cannot read dataset JSON");
    if (text.compare(0, 3, "\xef\xbb\xbf") == 0) text.erase(0, 3);
    const auto json = JsonReader(std::move(text)).read();
    if (json.field("schemaVersion").integer() != 1 || json.field("featureFormat").string() != "HF1"
        || json.field("featureSpaceId").string() != HIFACE_FEATURE_SPACE_ID) throw std::runtime_error("Dataset schema or feature space does not match this SDK");
    const auto& entries = json.field("entries");
    if (entries.kind != Json::Array || entries.array.size() > HIFACE_SEARCH_MAX_ENTRIES
        || json.field("entryCount").integer() != static_cast<int64_t>(entries.array.size())) throw std::runtime_error("Invalid dataset entry count");
    ImportProgress progress; progress.total = entries.array.size();
    std::vector<Person> batch;
    auto commit = [&] { if (!batch.empty()) { database.save(batch, true); progress.saved += batch.size(); batch.clear(); } };
    for (const auto& entry : entries.array) {
        if (callback && !callback(progress)) { commit(); progress.stopped = true; return progress; }
        try {
            Person person{entry.field("faceId").string(), entry.optional("group"), entry.optional("tag"), entry.field("feature").string(), 0};
            if (entry.object.count("updateTimeMillis")) person.updated = entry.field("updateTimeMillis").integer();
            if (person.id.empty() || person.id.size() > HIFACE_SEARCH_MAX_TEXT_BYTES || person.id.find('\0') != std::string::npos
                || person.group.size() > HIFACE_SEARCH_MAX_TEXT_BYTES || person.tag.size() > HIFACE_SEARCH_MAX_TEXT_BYTES
                || person.group.find('\0') != std::string::npos || person.tag.find('\0') != std::string::npos || person.updated < 0)
                throw std::runtime_error("Invalid dataset metadata");
            auto decoded = decodeFeature(person.feature); std::fill(decoded.begin(), decoded.end(), 0);
            batch.push_back(std::move(person));
        } catch (const std::bad_alloc&) { throw; }
        catch (const std::exception&) { ++progress.failed; }
        ++progress.processed;
        if (batch.size() == HIFACE_SEARCH_MAX_BATCH_ENTRIES) commit();
    }
    commit(); if (callback) callback(progress); return progress;
}
size_t exportDataset(const Gallery& database, const std::filesystem::path& file, const std::string& group, const std::string& tag) {
    auto temporary = file; temporary += ".tmp-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
    struct Cleanup { std::filesystem::path path; ~Cleanup() { std::error_code ignored; std::filesystem::remove(path, ignored); } } cleanup{temporary};
    const auto total = database.count(group, tag);
    std::ofstream output(temporary, std::ios::binary);
    if (!output) throw std::runtime_error("Cannot create JSON export");
    output << "{\"schemaVersion\":1,\"featureFormat\":\"HF1\",\"featureSpaceId\":" << escaped(HIFACE_FEATURE_SPACE_ID)
        << ",\"entryCount\":" << total << ",\"entries\":[";
    size_t written = 0;
    for (uint32_t offset = 0;;) {
        const auto page = database.list(offset, 1000, group, tag, true);
        if (page.empty()) break;
        for (const auto& person : page) {
            if (written++) output << ',';
            output << "{\"faceId\":" << escaped(person.id) << ",\"group\":" << escaped(person.group) << ",\"tag\":" << escaped(person.tag)
                << ",\"feature\":" << escaped(person.feature) << ",\"updateTimeMillis\":" << person.updated << '}';
        }
        offset += static_cast<uint32_t>(page.size());
    }
    if (written != total) throw std::runtime_error("Gallery changed during export; retry when other writers are idle");
    output << "]}\n"; output.close(); if (!output) throw std::runtime_error("Cannot finish JSON export");
#ifdef _WIN32
    if (!MoveFileExW(temporary.c_str(), file.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) throw std::runtime_error("Cannot commit JSON export");
#else
    std::filesystem::rename(temporary, file);
#endif
    return written;
}
}
