#pragma once
#include "enrollment_draft.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <functional>
#include <optional>

namespace hiface_demo {
// Demo reference data is independent from the search library and SDK runtime state.
// No feature payload is returned by ids() or placed in the UI snapshot.
class CapturedReferences {
public:
    explicit CapturedReferences(const std::filesystem::path& path) : database_(path) {}
    std::vector<std::string> ids() const {
        std::vector<std::string> result;
        for (uint32_t offset = 0;;) {
            const auto page = database_.list(offset, 1000);
            for (const auto& person : page) result.push_back(person.id);
            if (page.size() < 1000) break;
            offset += static_cast<uint32_t>(page.size());
        }
        return result;
    }
    std::string feature(const std::string& id) const { return database_.get(normalizeMetadata(id)).feature; }
    void save(const std::string& raw_id, const std::string& feature) {
        const auto id = normalizeMetadata(raw_id);
        EnrollmentDraft::validateMetadata(id, "", ""); decodeFeature(feature);
        database_.save({{id, "", "", feature, 0}}, true);
    }
private:
    Gallery database_;
};
class ReferenceDraft {
public:
    bool pending() const { return !feature_.empty(); }
    void clear() { feature_.clear(); }
    void stage(const std::string& feature) { decodeFeature(feature); feature_ = feature; }
    void save(CapturedReferences& store, const std::string& id) {
        if (!pending()) throw std::runtime_error(u8"请先采集或导入基准，再确认保存");
        store.save(id, feature_); clear();
    }
private:
    std::string feature_;
};
class PhotoComparisonCache {
public:
    void clear() { features_ = {}; }
    bool ready(unsigned slot) const { return slot < 2 && !features_[slot].empty(); }
    bool ready() const { return ready(0) && ready(1); }
    // Commit only a current successful extraction; cancellation/failure retains the old slot.
    bool replace(unsigned slot, const std::function<CaptureResult()>& extract, const std::function<bool()>& current) {
        if (slot >= 2) throw std::invalid_argument("Invalid comparison slot");
        auto result = extract();
        if (current && !current()) return false;
        decodeFeature(result.text);
        features_[slot] = std::move(result.text); return true;
    }
    float compare() const {
        if (!ready()) throw std::runtime_error(u8"请先等待两张照片的特征提取完成");
        return compareFeatureText(features_[0], features_[1]);
    }
private:
    std::array<std::string, 2> features_;
};
struct ContourLine { HiFacePointV1 start, end; };
inline std::vector<ContourLine> detectionContours(const std::vector<HiFaceMeshPointV1>& mesh) {
    // The same lip/eye/face/nose edges as Android and Linux. Eyebrows are excluded.
    static const std::vector<std::vector<uint16_t>> groups = {
        {61,146,146,91,91,181,181,84,84,17,17,314,314,405,405,321,321,375,375,291,61,185,185,40,40,39,39,37,37,0,0,267,267,269,269,270,270,409,409,291,78,95,95,88,88,178,178,87,87,14,14,317,317,402,402,318,318,324,324,308,78,191,191,80,80,81,81,82,82,13,13,312,312,311,311,310,310,415,415,308},
        {263,249,249,390,390,373,373,374,374,380,380,381,381,382,382,362,263,466,466,388,388,387,387,386,386,385,385,384,384,398,398,362},
        {33,7,7,163,163,144,144,145,145,153,153,154,154,155,155,133,33,246,246,161,161,160,160,159,159,158,158,157,157,173,173,133},
        {10,338,338,297,297,332,332,284,284,251,251,389,389,356,356,454,454,323,323,361,361,288,288,397,397,365,365,379,379,378,378,400,400,377,377,152,152,148,148,176,176,149,149,150,150,136,136,172,172,58,58,132,132,93,93,234,234,127,127,162,162,21,21,54,54,103,103,67,67,109,109,10},
        {168,6,6,197,197,195,195,5,5,4,4,1,1,19,19,94,94,2,98,97,97,2,2,326,326,327}
    };
    std::vector<ContourLine> result;
    const auto finite = [](const auto& p) { return std::isfinite(p.x) && std::isfinite(p.y); };
    for (size_t group = 0; group < groups.size(); ++group) {
        const auto& indices = groups[group]; const bool eye = group == 1 || group == 2;
        float min_x = INFINITY, min_y = INFINITY, max_x = -INFINITY, max_y = -INFINITY;
        if (eye) for (const auto index : indices) if (index < mesh.size() && finite(mesh[index])) {
            min_x = std::min(min_x, mesh[index].x); min_y = std::min(min_y, mesh[index].y);
            max_x = std::max(max_x, mesh[index].x); max_y = std::max(max_y, mesh[index].y);
        }
        const float cx = (min_x + max_x) * .5f, cy = (min_y + max_y) * .5f;
        for (size_t i = 0; i + 1 < indices.size(); i += 2) {
            if (indices[i] >= mesh.size() || indices[i+1] >= mesh.size()) continue;
            const auto& a = mesh[indices[i]]; const auto& b = mesh[indices[i+1]];
            if (!finite(a) || !finite(b) || (eye && (!std::isfinite(cx) || !std::isfinite(cy)))) continue;
            result.push_back(eye ? ContourLine{{cx+(a.x-cx)*1.4f,cy+(a.y-cy)*1.4f},{cx+(b.x-cx)*1.4f,cy+(b.y-cy)*1.4f}}
                                 : ContourLine{{a.x,a.y},{b.x,b.y}});
        }
    }
    return result;
}
}
