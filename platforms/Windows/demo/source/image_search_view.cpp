#include "image_search_view.h"
#include "win_util.h"
#include <algorithm>
#include <iomanip>
#include <sstream>
#include <windowsx.h>

namespace hiface_demo {
namespace {
RECT native(const UiRect& area) { return {area.left, area.top, area.right, area.bottom}; }
void drawImage(HDC dc, const Image& image, const UiRect& area) {
    if (image.rgba.empty() || !area.width() || !area.height()) return;
    const auto fit = fitImage(image.width, image.height, area);
    BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER); info.bmiHeader.biWidth = image.width;
    info.bmiHeader.biHeight = -image.height; info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
    SetStretchBltMode(dc, HALFTONE); SetBrushOrgEx(dc, 0, 0, nullptr);
    StretchDIBits(dc, fit.x, fit.y, fit.width, fit.height, 0, 0, image.width, image.height, image.rgba.data(), &info, DIB_RGB_COLORS, SRCCOPY);
}
}
void ImageSearchView::create(HWND parent, Theme& theme) {
    theme_ = &theme;
    WNDCLASSW type{}; type.lpfnWndProc = procedure; type.hInstance = GetModuleHandleW(nullptr);
    type.lpszClassName = L"HiFaceImageSearchView"; type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    RegisterClassW(&type);
    window_ = CreateWindowExW(WS_EX_CONTROLPARENT, type.lpszClassName, L"图片人脸搜索结果：方向键选择人脸", WS_CHILD | WS_TABSTOP | WS_CLIPCHILDREN,
        0, 0, 10, 10, parent, nullptr, type.hInstance, this);
    if (!window_) throw std::runtime_error("Cannot create image search view");
    details_ = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_TABSTOP | WS_VSCROLL | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL,
        0, 0, 10, 10, window_, nullptr, type.hInstance, nullptr);
    if (!details_) throw std::runtime_error("Cannot create image search details");
    theme.style(details_);
}
PhotoLayout ImageSearchView::geometry() const {
    RECT client{},outer{}; GetClientRect(window_, &client);GetWindowRect(window_,&outer);
    return {static_cast<int>(client.right), static_cast<int>(client.bottom), result_ ? static_cast<int>(result_->faces.size()) : 0,
        busy_ || error_ || bool(result_) || bool(photo_), static_cast<int>(theme_->dpi),outer.right-outer.left>=theme_->px(700)&&outer.bottom-outer.top>=theme_->px(340)};
}
void ImageSearchView::layout(const RECT& rectangle, bool visible) {
    if (!window_) return;
    MoveWindow(window_, rectangle.left, rectangle.top, rectangle.right - rectangle.left, rectangle.bottom - rectangle.top, TRUE);
    ShowWindow(window_, visible ? SW_SHOW : SW_HIDE); scroll(scroll_); updateDetails();
}
void ImageSearchView::setState(bool busy, bool error, const std::wstring& message, const std::wstring& filename) {
    if (busy_ == busy && error_ == error && message_ == message && filename_ == filename) return;
    busy_ = busy; error_ = error; message_ = message; filename_ = filename;
    updateDetails(); InvalidateRect(window_, nullptr, FALSE);
}
void ImageSearchView::updateDetails() {
    const auto layout = geometry();
    MoveWindow(details_, layout.details.left, layout.details.top, layout.details.width(), layout.details.height(), TRUE);
    const bool visible = !busy_ && result_ && selected_ >= 0 && static_cast<size_t>(selected_) < result_->faces.size();
    ShowWindow(details_, visible ? SW_SHOW : SW_HIDE);
    if (!visible) return;
    const auto& face = result_->faces[static_cast<size_t>(selected_)];
    std::wostringstream text;
    text << L"人脸 " << selected_ + 1 << L" / " << result_->faces.size() << L"   ";
    if (face.match) {
        text << L"已匹配 · 相似度 " << std::fixed << std::setprecision(4) << face.match->score
             << L"\r\n人员 ID：" << widen(face.match->entry.id)
             << L"\r\n分组：" << (face.match->entry.group.empty() ? L"—" : widen(face.match->entry.group))
             << L"   标签：" << (face.match->entry.tag.empty() ? L"—" : widen(face.match->entry.tag));
    } else {
        text << widen(face.label) << L"\r\n" << (result_->empty_library ? L"人脸库为空，请先录入人员后重新搜索。"
            : face.status == HIFACE_STATUS_OK ? L"没有达到 0.80 的匹配，请确认该人员已录入人脸库。" : L"请换用清晰、正面且人脸更大的照片。")
             << L"\r\n点击人脸框或缩略图，也可用方向键切换。";
    }
    const auto value = text.str();
    const int length = GetWindowTextLengthW(details_); std::wstring previous(static_cast<size_t>(length) + 1, L'\0');
    GetWindowTextW(details_, previous.data(), length + 1); previous.resize(length);
    if (previous != value) SetWindowTextW(details_, value.c_str());
    const auto accessible = L"图片搜索结果 · " + std::to_wstring(selected_ + 1) + L" / " + std::to_wstring(result_->faces.size()) + L" · " + widen(face.label);
    SetWindowTextW(window_, accessible.c_str());
}
void ImageSearchView::setContent(std::shared_ptr<const Image> photo, std::shared_ptr<const ImageSearchResult> result) {
    if (photo_ == photo && result_ == result) return;
    photo_ = std::move(photo); result_ = std::move(result); thumbnails_.clear(); scroll_ = 0; selected_ = -1;
    if (result_) {
        for (const auto& face : result_->faces) {
            auto preview = face.preview;
            for (size_t i = 0; i + 3 < preview.rgba.size(); i += 4) std::swap(preview.rgba[i], preview.rgba[i + 2]);
            thumbnails_.push_back(std::move(preview));
        }
        if (!result_->faces.empty()) selected_ = 0;
    }
    scroll(0); updateDetails(); InvalidateRect(window_, nullptr, FALSE);
}
void ImageSearchView::scroll(int position) {
    const int count = result_ ? static_cast<int>(result_->faces.size()) : 0;
    const auto layout = geometry();
    const int content = layout.content(count);
    scroll_ = layout.clampScroll(position, count);
    SCROLLINFO info{sizeof(info), SIF_RANGE | SIF_PAGE | SIF_POS, 0, std::max(0, content - 1), static_cast<UINT>(layout.viewport()), scroll_, 0};
    ShowScrollBar(window_,layout.sidebar?SB_HORZ:SB_VERT,FALSE);
    ShowScrollBar(window_,layout.sidebar?SB_VERT:SB_HORZ,content>layout.viewport());
    SetScrollInfo(window_,layout.sidebar?SB_VERT:SB_HORZ,&info,TRUE); InvalidateRect(window_, nullptr, FALSE);
}
void ImageSearchView::select(int index) {
    if (!result_ || result_->faces.empty()) return;
    selected_ = std::clamp(index, 0, static_cast<int>(result_->faces.size()) - 1);
    scroll(geometry().reveal(selected_, scroll_, static_cast<int>(result_->faces.size())));
    updateDetails(); InvalidateRect(window_, nullptr, FALSE);
}
void ImageSearchView::paint() {
    PAINTSTRUCT paint{}; auto target = BeginPaint(window_, &paint); RECT client{}; GetClientRect(window_, &client);
    const auto dc = CreateCompatibleDC(target); const auto buffer = CreateCompatibleBitmap(target, std::max(1L, client.right), std::max(1L, client.bottom));
    const auto previous = SelectObject(dc, buffer);
    auto px = [&](int value) { return theme_->px(value); };
    fill(dc, client, colors::canvas);
    const auto layout = geometry();
    RECT title{px(14), px(6), client.right - px(14), px(30)};
    const auto hint = busy_ ? L"正在搜索…  可取消，或直接选择其他图片" : result_ && !result_->faces.empty()
        ? L"点击人脸或结果 · 方向键切换 · 滚轮浏览 · 文字可复制" : L"Ctrl+O 选择图片 · F5 重新搜索 · Esc 返回";
    label(dc, hint, title, theme_->small, RGB(180, 195, 216), DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    std::wstring source = filename_.empty() ? L"JPEG / PNG / BMP / TIFF · 最多 10 张脸" : filename_;
    if (photo_) source += L"  ·  " + std::to_wstring(photo_->width) + L" × " + std::to_wstring(photo_->height);
    title.top = px(30); title.bottom = std::min(px(54), static_cast<int>(layout.photo.top));
    label(dc, source.c_str(), title, theme_->small, RGB(167, 186, 214), DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_PATH_ELLIPSIS);
    const auto area = layout.photo;
    if (photo_) {
        drawImage(dc, *photo_, area);
        if (result_) {
            const auto fit = fitImage(photo_->width, photo_->height, area);
            const int saved = SaveDC(dc); IntersectClipRect(dc, area.left, area.top, area.right, area.bottom);
            const auto old_brush = SelectObject(dc, GetStockObject(NULL_BRUSH));
            for (size_t i = 0; i < result_->faces.size(); ++i) {
                const auto& face = result_->faces[i];
                const COLORREF color = face.match ? RGB(40, 220, 90) : RGB(255, 190, 40);
                const auto pen = CreatePen(PS_SOLID, px(static_cast<int>(i) == selected_ ? 4 : 2), color);
                const auto old_pen = SelectObject(dc, pen);
                RECT box{fit.x + static_cast<int>(face.face.x * fit.scale), fit.y + static_cast<int>(face.face.y * fit.scale),
                    fit.x + static_cast<int>((face.face.x + face.face.width) * fit.scale), fit.y + static_cast<int>((face.face.y + face.face.height) * fit.scale)};
                Rectangle(dc, box.left, box.top, box.right, box.bottom);
                const int label_width = std::max(px(90), std::min(px(260), static_cast<int>(area.right - area.left)));
                const int x = std::clamp(static_cast<int>(box.left), static_cast<int>(area.left), std::max(static_cast<int>(area.left), static_cast<int>(area.right) - label_width));
                const int y = std::clamp(static_cast<int>(box.top) - px(24), static_cast<int>(area.top), std::max(static_cast<int>(area.top), static_cast<int>(area.bottom) - px(24)));
                RECT banner{x, y, x + label_width, y + px(24)}; fill(dc, banner, colors::canvas); banner.left += px(4);
                const auto text = std::to_wstring(i + 1) + L"  " + widen(face.label);
                label(dc, text.c_str(), banner, theme_->small, color, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
                SelectObject(dc, old_pen); DeleteObject(pen);
            }
            SelectObject(dc, old_brush); RestoreDC(dc, saved);
        }
    } else {
        auto empty = native(area);
        label(dc, busy_ ? L"正在读取图片并检测人脸…" : error_ ? L"图片搜索未完成，请查看结果提示" : L"选择图片，查看每张人脸的匹配结果\n支持多人合照，无需打开摄像头",
            empty, theme_->body, RGB(167, 186, 214), DT_CENTER | DT_VCENTER | DT_WORDBREAK);
    }
    if (busy_ || error_ || result_ || photo_) {
        auto details = native(layout.details); fill(dc, details, colors::surface);
        if (busy_ || !result_ || result_->faces.empty()) {
            details.left += px(10); details.right -= px(10);
            auto notice = message_;
            if (!busy_ && result_ && result_->faces.empty()) notice = L"未检测到人脸\n请换用清晰的正面人像或合照，再次搜索。";
            label(dc, notice.c_str(), details, theme_->small, error_ ? colors::error : busy_ ? colors::primary : colors::ink, DT_LEFT | DT_VCENTER | DT_WORDBREAK | DT_END_ELLIPSIS);
        }
    }
    if (result_ && !result_->faces.empty()) {
        const auto strip_area = native(layout.strip); fill(dc, strip_area, colors::surface);
        const int saved = SaveDC(dc);
        IntersectClipRect(dc, strip_area.left+px(layout.sidebar?8:12), strip_area.top, strip_area.right-px(layout.sidebar?8:12), strip_area.bottom);
        for (size_t i = 0; i < result_->faces.size(); ++i) {
            auto tile = native(layout.tile(static_cast<int>(i), scroll_)); const int left = tile.left;
            if(tile.bottom<strip_area.top||tile.top>strip_area.bottom||tile.right<strip_area.left||tile.left>strip_area.right)continue;
            card(dc, tile, static_cast<int>(i) == selected_ ? colors::selected : colors::surface, colors::line, px(10));
            const int side=layout.sidebar?px(64):std::clamp(layout.strip.height()-px(60),px(32),px(80));
            const int image_left=layout.sidebar?left+px(8):left+px(69)-side/2;
            UiRect image{image_left,static_cast<int>(tile.top)+px(8),image_left+side,static_cast<int>(tile.top)+px(8)+side};
            if (!thumbnails_[i].rgba.empty()) drawImage(dc, thumbnails_[i], image);
            else label(dc, L"无法提取", native(image), theme_->small, colors::muted, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            RECT caption=layout.sidebar?RECT{left+side+px(18),tile.top+px(8),tile.right-px(8),tile.bottom-px(8)}:RECT{left+px(6),tile.top+side+px(8),tile.right-px(6),tile.bottom-px(4)};
            const auto text = std::to_wstring(i + 1) + L"  " + widen(result_->faces[i].label);
            label(dc, text.c_str(), caption, theme_->small, result_->faces[i].match ? colors::success : colors::ink,(layout.sidebar?DT_LEFT:DT_CENTER)|DT_VCENTER|DT_WORDBREAK|DT_END_ELLIPSIS);
            if (GetFocus() == window_ && static_cast<int>(i) == selected_) { InflateRect(&tile, -px(3), -px(3)); DrawFocusRect(dc, &tile); }
        }
        RestoreDC(dc, saved);
    }
    BitBlt(target, 0, 0, client.right, client.bottom, dc, 0, 0, SRCCOPY);
    SelectObject(dc, previous); DeleteObject(buffer); DeleteDC(dc); EndPaint(window_, &paint);
}
LRESULT CALLBACK ImageSearchView::procedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* view = reinterpret_cast<ImageSearchView*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        view = static_cast<ImageSearchView*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(view)); view->window_ = window;
    }
    if (!view) return DefWindowProcW(window, message, wparam, lparam);
    try {
        switch (message) {
            case WM_ERASEBKGND: return 1;
            case WM_PAINT: view->paint(); return 0;
            case WM_SIZE:
                view->scroll(view->selected_ < 0 ? view->scroll_ : view->geometry().reveal(view->selected_, view->scroll_, static_cast<int>(view->result_->faces.size())));
                view->updateDetails(); return 0;
            case WM_CTLCOLORSTATIC: case WM_CTLCOLOREDIT:
                SetTextColor(reinterpret_cast<HDC>(wparam), colors::ink); SetBkColor(reinterpret_cast<HDC>(wparam), colors::surface);
                return reinterpret_cast<LRESULT>(view->theme_->surface);
            case WM_SETFOCUS: case WM_KILLFOCUS: InvalidateRect(window, nullptr, FALSE); return 0;
            case WM_GETDLGCODE: return DLGC_WANTARROWS;
            case WM_KEYDOWN:
                if (wparam == VK_LEFT || wparam == VK_UP) view->select(view->selected_ - 1);
                else if (wparam == VK_RIGHT || wparam == VK_DOWN) view->select(view->selected_ + 1);
                else if (wparam == VK_HOME) view->select(0);
                else if (wparam == VK_END && view->result_) view->select(static_cast<int>(view->result_->faces.size()) - 1);
                return 0;
            case WM_MOUSEWHEEL: view->scroll(view->scroll_ - GET_WHEEL_DELTA_WPARAM(wparam) / WHEEL_DELTA * view->theme_->px(100)); return 0;
            case WM_VSCROLL: case WM_HSCROLL: {
                SCROLLINFO info{}; info.cbSize = sizeof(info); info.fMask = SIF_TRACKPOS; GetScrollInfo(window,view->geometry().sidebar?SB_VERT:SB_HORZ,&info);
                int next = view->scroll_;
                switch (LOWORD(wparam)) {
                    case SB_LINELEFT: next -= view->theme_->px(48); break; case SB_LINERIGHT: next += view->theme_->px(48); break;
                    case SB_PAGELEFT: next -= view->geometry().viewport(); break; case SB_PAGERIGHT: next += view->geometry().viewport(); break;
                    case SB_THUMBTRACK: case SB_THUMBPOSITION: next = info.nTrackPos; break;
                }
                view->scroll(next); return 0;
            }
            case WM_LBUTTONDOWN: {
                SetFocus(window);
                if (!view->result_ || !view->photo_) return 0;
                const auto layout = view->geometry(); const int x_pixel = GET_X_LPARAM(lparam), y_pixel = GET_Y_LPARAM(lparam);
                if (const int index = layout.tileAt(x_pixel, y_pixel, static_cast<int>(view->result_->faces.size()), view->scroll_); index >= 0) view->select(index);
                else if (layout.photo.contains(x_pixel, y_pixel)) {
                    const auto fit = fitImage(view->photo_->width, view->photo_->height, layout.photo);
                    if (fit.scale <= 0) return 0;
                    const double x = (GET_X_LPARAM(lparam) - fit.x) / fit.scale, y = (GET_Y_LPARAM(lparam) - fit.y) / fit.scale;
                    for (int i = static_cast<int>(view->result_->faces.size()) - 1; i >= 0; --i) {
                        const auto& box = view->result_->faces[static_cast<size_t>(i)].face;
                        if (x >= box.x && x <= box.x + box.width && y >= box.y && y <= box.y + box.height) { view->select(i); break; }
                    }
                }
                return 0;
            }
        }
    } catch (const std::exception& error) { writeLog(error.what()); }
    return DefWindowProcW(window, message, wparam, lparam);
}
}
