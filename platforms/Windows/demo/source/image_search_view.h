#pragma once
#include "image_search.h"
#include "theme.h"
#include "ui_geometry.h"
#include <memory>

namespace hiface_demo {
// Native Demo view. SDK data stays independent of HWND, GDI and selection state.
// 原生 Demo 视图；SDK 数据独立于 HWND、GDI 和选中状态。
class ImageSearchView {
public:
    void create(HWND parent, Theme& theme);
    void layout(const RECT& rectangle, bool visible);
    void setContent(std::shared_ptr<const Image> photo, std::shared_ptr<const ImageSearchResult> result);
    void setState(bool busy, bool error, const std::wstring& message, const std::wstring& filename);
    HWND window() const { return window_; }
private:
    HWND window_ = nullptr;
    HWND details_ = nullptr;
    Theme* theme_ = nullptr;
    std::shared_ptr<const Image> photo_;
    std::shared_ptr<const ImageSearchResult> result_;
    std::vector<Image> thumbnails_;
    // Pixel offset along the active strip orientation and selected face index; -1 means no selection.
    int scroll_ = 0, selected_ = -1;
    bool busy_ = false, error_ = false;
    std::wstring message_, filename_;
    PhotoLayout geometry() const;
    void updateDetails();
    void scroll(int position);
    void select(int index);
    void paint();
    static LRESULT CALLBACK procedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
};
}
