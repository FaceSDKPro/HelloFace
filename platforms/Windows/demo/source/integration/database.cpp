#include "hiface/database.hpp"
#include "hiface/client.hpp"
#include <memory>
namespace hiface {
namespace {
// std::string owns its full length, while the C metadata API uses NUL termination.
// Reject embedded NUL before crossing that boundary, rather than selecting another ID/scope.
// std::string 可含 NUL；传给 C 接口前必须拒绝，防止身份或筛选范围被静默截断。
void validateText(const std::string& text, bool required = false) {
    if ((required && text.empty()) || text.size() > HIFACE_SEARCH_MAX_TEXT_BYTES
        || text.find('\0') != std::string::npos)
        throw std::invalid_argument("Invalid gallery metadata text");
}
using Results = std::unique_ptr<HiFaceSearchResultsOpaque, decltype(&hiface_search_results_destroy_v1)>;
std::vector<Person> copyResults(HiFaceSearchResultsHandle raw) {
    Results results(raw, hiface_search_results_destroy_v1);
    std::vector<Person> people;
    for (uint32_t i = 0; i < hiface_search_results_count_v1(raw); ++i) {
        HiFaceSearchEntryV1 entry{}; entry.struct_size = sizeof(entry);
        float unused_score = 0;
        check(hiface_search_results_get_v1(raw, i, &entry, &unused_score), "read gallery entry");
        people.push_back({entry.face_id, entry.group, entry.tag,
            entry.feature_text ? std::string(entry.feature_text, entry.feature_text_length) : "", entry.update_time_ms});
    }
    return people;
}
}
std::string encodeFeature(const Feature& feature) {
    std::array<char, HIFACE_FEATURE_TEXT_BUFFER_SIZE> text{};
    check(hiface_feature_encode_text_v1(feature.data(), feature.size(), text.data(), text.size()), "encode HF1");
    return text.data();
}
Feature decodeFeature(const std::string& text) {
    Feature feature{};
    check(hiface_feature_decode_text_v1(text.data(), text.size(), feature.data(), feature.size()), "decode HF1");
    return feature;
}
float compareFeatureText(const std::string& left, const std::string& right) {
    const auto a = decodeFeature(left), b = decodeFeature(right); float score = 0;
    check(hiface_feature_compare_v1(a.data(), b.data(), a.size(), &score), "compare HF1 features"); return score;
}
Database::Database(const std::filesystem::path& path) {
    const auto text = path.u8string();
    if (text.find('\0') != std::string::npos) throw std::invalid_argument("Database path contains NUL");
    if (path.has_parent_path()) std::filesystem::create_directories(path.parent_path());
    check(hiface_search_open_v1(text.c_str(), &database_), "open gallery");
}
Database::~Database() { hiface_search_close_v1(database_); }
uint64_t Database::count(const std::string& group, const std::string& tag) const {
    validateText(group); validateText(tag);
    uint64_t value = 0; check(hiface_search_count_v1(database_, group.c_str(), tag.c_str(), &value), "count gallery"); return value;
}
std::vector<Person> Database::list(uint32_t offset, uint32_t limit, const std::string& group, const std::string& tag, bool features, bool recent) const {
    validateText(group); validateText(tag);
    HiFaceSearchResultsHandle raw = nullptr;
    auto call = features ? hiface_search_list_features_v1 : recent ? hiface_search_list_recent_v1 : hiface_search_list_v1;
    check(call(database_, group.c_str(), tag.c_str(), offset, limit, &raw), "list gallery"); return copyResults(raw);
}
Person Database::get(const std::string& id) const {
    validateText(id, true);
    HiFaceSearchResultsHandle raw = nullptr; check(hiface_search_get_v1(database_, id.c_str(), &raw), "get person"); return copyResults(raw).at(0);
}
void Database::save(const std::vector<Person>& people, bool overwrite) {
    if (people.empty() || people.size() > HIFACE_SEARCH_MAX_BATCH_ENTRIES)
        throw std::invalid_argument("Gallery batch must contain 1-1000 entries");
    std::vector<HiFaceSearchFeatureEntryV1> entries;
    std::vector<const HiFaceSearchFeatureEntryV1*> pointers;
    entries.reserve(people.size()); pointers.reserve(people.size());
    for (const auto& person : people) {
        validateText(person.id, true); validateText(person.group); validateText(person.tag);
        if (person.feature.size() != HIFACE_FEATURE_TEXT_LENGTH || person.updated < 0)
            throw std::invalid_argument("Expected a complete HF1 value and nonnegative update time");
        entries.push_back({sizeof(HiFaceSearchFeatureEntryV1), person.id.c_str(),
            person.tag.c_str(), person.group.c_str(), person.feature.c_str(), HIFACE_FEATURE_TEXT_LENGTH, person.updated, HIFACE_FEATURE_SPACE_ID});
    }
    for (const auto& entry : entries) pointers.push_back(&entry);
    check((overwrite ? hiface_search_upsert_v1 : hiface_search_insert_v1)(database_, pointers.data(), static_cast<uint32_t>(pointers.size())), "save gallery batch");
}
uint64_t Database::remove(const std::string& id) {
    validateText(id, true);
    uint64_t deleted = 0; check(hiface_search_delete_v1(database_, id.c_str(), &deleted), "delete person"); return deleted;
}
void Database::updateMetadata(const std::string& id, const std::string& group, const std::string& tag) {
    validateText(id, true); validateText(group); validateText(tag);
    check(hiface_search_update_metadata_v1(database_, id.c_str(), group.c_str(), tag.c_str(), 0), "update person metadata");
}
void Database::releaseMemory() { check(hiface_search_release_memory_v1(database_), "release gallery cache"); }
bool Database::contains(const std::string& id) const {
    validateText(id, true);
    uint32_t exists = 0; check(hiface_search_contains_v1(database_, id.c_str(), &exists), "contains person"); return exists != 0;
}
std::vector<SearchMatch> Database::search(const std::string& text, uint32_t top_k, float threshold,
    const std::string& group, const std::string& tag) const {
    validateText(group); validateText(tag);
    auto feature = decodeFeature(text);
    struct Clear { Feature& feature; ~Clear() { feature.fill(0); } } clear{feature};
    HiFaceSearchResultsHandle raw = nullptr;
    check(hiface_search_query_v1(database_, feature.data(), feature.size(), group.c_str(), tag.c_str(),
        top_k, threshold, &raw), "search HF1 feature");
    Results owner(raw, hiface_search_results_destroy_v1);
    std::vector<SearchMatch> matches;
    for (uint32_t i = 0; i < hiface_search_results_count_v1(raw); ++i) {
        HiFaceSearchEntryV1 entry{}; entry.struct_size = sizeof(entry);
        float score = 0;
        check(hiface_search_results_get_v1(raw, i, &entry, &score), "read search match");
        matches.push_back({{entry.face_id, entry.group, entry.tag, "", entry.update_time_ms}, score});
    }
    return matches;
}
}
