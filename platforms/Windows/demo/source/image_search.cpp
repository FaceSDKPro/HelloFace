#include "image_search.h"
#include <iomanip>
#include <sstream>

namespace hiface_demo {
std::optional<ImageSearchResult> resolveImageFaces(const Gallery& database,
    std::vector<hiface::ImageFaceCapture> captures, const std::function<bool()>& current) {
    if (current && !current()) return std::nullopt;
    ImageSearchResult result;
    result.empty_library = database.count() == 0;
    for (auto& capture : captures) {
        if (current && !current()) return std::nullopt;
        ImageSearchFace face; face.face = capture.face; face.face.mesh = nullptr; face.status = capture.status;
        if (capture.status != HIFACE_STATUS_OK) {
            face.label = capture.status == HIFACE_STATUS_IMAGE_FACE_TOO_SMALL ? u8"人脸太小"
                : demoErrorMessage(SdkError(capture.status, "Capture face"));
        } else {
            if (!capture.capture) throw std::runtime_error("Successful image face has no feature");
            face.preview = std::move(capture.capture->preview);
            try {
                auto matches = database.search(capture.capture->text); // Android default config / 沿用 Android 默认配置。
                if (matches.empty()) face.label = u8"未匹配";
                else {
                    face.match = std::move(matches.front()); ++result.matched;
                    std::ostringstream label; label << face.match->entry.id << " | " << std::fixed << std::setprecision(2) << face.match->score;
                    face.label = label.str();
                }
            } catch (const SdkError& error) { face.status = error.status; face.label = demoErrorMessage(error); }
            capture.capture->feature.fill(0);
        }
        result.faces.push_back(std::move(face));
    }
    if (current && !current()) return std::nullopt;
    result.summary = result.faces.empty() ? u8"未检测到人脸，请更换清晰图片"
        : u8"检测到 " + std::to_string(result.faces.size()) + u8" 个人脸，搜索匹配成功 " + std::to_string(result.matched) + u8" 个";
    if (!result.faces.empty() && result.empty_library) result.summary += u8" | 人脸库为空，请先录入";
    return result;
}
std::optional<ImageSearchResult> searchPhoto(hiface::Client& client, const Gallery& database,
    const Image& image, const std::function<bool()>& current) {
    if (current && !current()) return std::nullopt;
    auto captures = client.captureFaces(image);
    return resolveImageFaces(database, std::move(captures), current);
}
}
