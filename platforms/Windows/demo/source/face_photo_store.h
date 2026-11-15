#pragma once
#include "types.h"
#include <memory>
namespace hiface_demo {
// Demo-owned confirmed crops in LocalAppData, with a protected current-user/SYSTEM DACL.
// Ordinary desktop processes under the same account remain outside this isolation boundary.
class FacePhotoStore {
public:
    static bool save(const std::string& face_id, const Image* image) noexcept;
    static std::shared_ptr<const Image> load(const std::string& face_id) noexcept;
    static void remove(const std::string& face_id) noexcept;
};
}
