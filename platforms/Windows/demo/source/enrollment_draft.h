#pragma once
#include "types.h"
namespace hiface_demo {
// A successful capture is only a draft. Explicit confirmation owns persistence.
// The HF1 stays on the worker and is never published to the UI or diagnostic log.
// 采集成功仅形成草稿，必须明确确认后才持久化；HF1 留在工作线程，不交给 UI 或诊断日志。
class EnrollmentDraft {
public:
    static void requireSingleFace(size_t count) {
        if (!count) throw SdkError(HIFACE_STATUS_IMAGE_NO_FACE, u8"图片中未检测到人脸，请选择清晰的单人正脸照片");
        if (count != 1) throw std::runtime_error(u8"图片中有多张人脸，请裁剪为单人照片后重新选择，避免录错人员");
    }
    static void validateMetadata(const std::string& id, const std::string& group, const std::string& tag) {
        if (id.find_first_not_of(" \t\r\n") == std::string::npos)
            throw std::runtime_error(u8"请填写人员 ID，不能只输入空格；当前预览会保留");
        if (id.size() > HIFACE_SEARCH_MAX_TEXT_BYTES || group.size() > HIFACE_SEARCH_MAX_TEXT_BYTES
            || tag.size() > HIFACE_SEARCH_MAX_TEXT_BYTES || id.find('\0') != std::string::npos
            || group.find('\0') != std::string::npos || tag.find('\0') != std::string::npos)
            throw std::runtime_error(u8"人员 ID、分组和标签各不能超过 1024 个 UTF-8 字节，且不能包含空字符");
    }
    bool pending() const { return !feature_.empty(); }
    void clear() { feature_.clear(); }
    void stage(const FlowResult& result) {
        clear();
        if (result.metadata.outcome != HIFACE_FLOW_OUTCOME_PASSED || result.feature.empty() || result.preview.rgba.empty())
            throw std::runtime_error("Enrollment requires a successful capture and aligned preview");
        decodeFeature(result.feature); feature_ = result.feature;
    }
    void stage(const CaptureResult& result) {
        clear();
        if (result.preview.rgba.empty()) throw std::runtime_error("Enrollment requires an aligned preview");
        decodeFeature(result.text); feature_ = result.text;
    }
    void save(Gallery& gallery, const std::string& id, const std::string& group, const std::string& tag) {
        if (!pending()) throw std::runtime_error(u8"请先采集人脸并核对预览，再确认保存");
        validateMetadata(id, group, tag);
        if (gallery.contains(id)) throw SdkError(HIFACE_STATUS_ALREADY_EXISTS, u8"此人员 ID 已存在，请修改 ID 后重试；当前预览已保留，已有人员不会被覆盖");
        gallery.save({{id, group, tag, feature_, 0}}, false);
        clear();
    }
private:
    std::string feature_;
};
}
