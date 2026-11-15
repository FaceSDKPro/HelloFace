#include <hiface/hiface_c_api.h>
#include <array>
#include <iostream>
int main() {
    if (hiface_session_search_copy_jpeg_v1(nullptr, nullptr, nullptr, nullptr) != HIFACE_STATUS_INVALID_ARGUMENT) return 1;
    // C++ applications call the same stable C ABI; no C++ implementation source is needed.
    // C++ 应用调用同一套稳定 C ABI，无需 C++ 实现源码。
    std::array<float, HIFACE_FACE_FEATURE_DIMENSION> feature{}; feature[0] = 1;
    std::array<char, HIFACE_FEATURE_TEXT_LENGTH + 1> text{};
    const size_t length = HIFACE_FEATURE_TEXT_LENGTH;
    if (hiface_feature_encode_text_v1(feature.data(), feature.size(), text.data(), text.size()) != HIFACE_STATUS_OK)
        return 1;
    std::array<float, HIFACE_FACE_FEATURE_DIMENSION> decoded{};
    if (hiface_feature_decode_text_v1(text.data(), length, decoded.data(), decoded.size()) != HIFACE_STATUS_OK) return 1;
    float score = 0;
    if (hiface_feature_compare_v1(feature.data(), decoded.data(), feature.size(), &score) != HIFACE_STATUS_OK || score < .999f)
        return 1;
    std::cout << "C++ consumer: synthetic HF1 codec and self-comparison passed\n";
    return 0;
}
