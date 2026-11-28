#include "theme.h"
#include <commctrl.h>
#include <uxtheme.h>
#include <string>
namespace hiface_demo {
namespace {
constexpr UINT_PTR kButtonTheme = 1, kFocusTheme = 2;
LRESULT CALLBACK focusProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam, UINT_PTR, DWORD_PTR) {
    if (message == WM_SETFOCUS) SendMessageW(GetParent(window), kRevealFocusedControl, 0, reinterpret_cast<LPARAM>(window));
    if (message == WM_KEYDOWN && wparam == 'A' && GetKeyState(VK_CONTROL) < 0) {
        wchar_t type[32]{}; GetClassNameW(window, type, 32);
        if (std::wstring(type) == L"Edit") { SendMessageW(window, EM_SETSEL, 0, -1); return 0; }
    }
    if (message == WM_CHAR && wparam == 1 && GetKeyState(VK_CONTROL) < 0) return 0;
    if (message == WM_NCDESTROY) RemoveWindowSubclass(window, focusProcedure, kFocusTheme);
    return DefSubclassProc(window, message, wparam, lparam);
}
LRESULT CALLBACK buttonProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam, UINT_PTR, DWORD_PTR) {
    if (message == WM_MOUSEMOVE && !GetPropW(window, L"HiFaceHover")) {
        SetPropW(window, L"HiFaceHover", reinterpret_cast<HANDLE>(1));
        TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0}; TrackMouseEvent(&track); InvalidateRect(window, nullptr, FALSE);
    } else if (message == WM_MOUSELEAVE) { RemovePropW(window, L"HiFaceHover"); InvalidateRect(window, nullptr, FALSE); }
    else if (message == WM_NCDESTROY) { RemovePropW(window, L"HiFaceHover"); RemoveWindowSubclass(window, buttonProcedure, kButtonTheme); }
    return DefSubclassProc(window, message, wparam, lparam);
}
}
void fill(HDC dc, RECT rectangle, COLORREF color) { const auto brush = CreateSolidBrush(color); FillRect(dc, &rectangle, brush); DeleteObject(brush); }
void card(HDC dc, RECT rectangle, COLORREF color, COLORREF border, int radius) {
    const auto pen = CreatePen(PS_SOLID, 1, border); const auto brush = CreateSolidBrush(color);
    const auto old_pen = SelectObject(dc, pen), old_brush = SelectObject(dc, brush);
    RoundRect(dc, rectangle.left, rectangle.top, rectangle.right, rectangle.bottom, radius, radius);
    SelectObject(dc, old_pen); SelectObject(dc, old_brush); DeleteObject(pen); DeleteObject(brush);
}
void label(HDC dc, const wchar_t* value, RECT rectangle, HFONT font, COLORREF color, UINT format) {
    const auto old = SelectObject(dc, font); SetBkMode(dc, TRANSPARENT); SetTextColor(dc, color);
    DrawTextW(dc, value, -1, &rectangle, format | DT_NOPREFIX); SelectObject(dc, old);
}
Theme::Theme() { background = CreateSolidBrush(colors::background); surface = CreateSolidBrush(colors::surface); home_background = CreateSolidBrush(home_colors::background); setDpi(96); }
Theme::~Theme() {
    for (auto font : {body, title, small, result, parameter_title, recognition, enrollment}) DeleteObject(font);
    DeleteObject(background); DeleteObject(surface); DeleteObject(home_background);
}
int Theme::px(int value) const { return MulDiv(value, static_cast<int>(dpi), 96); }
void Theme::setDpi(UINT value) {
    dpi = value;
    for (auto font : {body, title, small, result, parameter_title, recognition, enrollment}) DeleteObject(font);
    auto font = [&](int size, int weight) { return CreateFontW(-px(size), 0, 0, 0, weight, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei UI"); };
    body = font(14, FW_NORMAL); title = font(23, FW_SEMIBOLD); small = font(12, FW_NORMAL);
    result = font(18, FW_MEDIUM);
    parameter_title = font(15, FW_BOLD);
    recognition = font(17, FW_NORMAL);
    enrollment = font(17, FW_BOLD);
}
void Theme::style(HWND control) {
    SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(body), TRUE);
    SetWindowTheme(control, L"Explorer", nullptr);
    if (GetWindowLongPtrW(control, GWL_STYLE) & WS_TABSTOP) SetWindowSubclass(control, focusProcedure, kFocusTheme, 0);
    wchar_t type[32]{}; GetClassNameW(control, type, 32);
    if (std::wstring(type) == L"Button" && (GetWindowLongPtrW(control, GWL_STYLE) & BS_TYPEMASK) == BS_OWNERDRAW)
        SetWindowSubclass(control, buttonProcedure, kButtonTheme, 0);
    if (std::wstring(type) == L"Edit") SendMessageW(control, EM_SETMARGINS, EC_LEFTMARGIN | EC_RIGHTMARGIN, MAKELPARAM(px(8), px(8)));
}
void Theme::button(const DRAWITEMSTRUCT& item, ButtonStyle style) const {
    const bool enabled = !(item.itemState & ODS_DISABLED), pressed = item.itemState & ODS_SELECTED;
    const bool hover = GetPropW(item.hwndItem, L"HiFaceHover") != nullptr;
    RECT area = item.rcItem; fill(item.hDC, area, colors::surface);
    InflateRect(&area, -1, -1);
    COLORREF background_color = colors::surface, text_color = colors::ink, border = colors::line;
    if (style == ButtonStyle::Enrollment) {
        text_color = (pressed || hover) ? home_colors::surface : home_colors::background;
    } else if (style == ButtonStyle::Primary) { background_color = enabled ? pressed ? RGB(30, 73, 174) : hover ? RGB(33, 83, 201) : colors::primary : RGB(220, 228, 242); border = background_color; text_color = colors::text_on_dark; }
    else if (hover || pressed) background_color = colors::selected;
    if (!enabled) text_color = colors::muted;
    if (style != ButtonStyle::Enrollment) card(item.hDC, area, background_color, border, px(10));
    wchar_t text[256]{}; GetWindowTextW(item.hwndItem, text, 256);
    const auto font = reinterpret_cast<HFONT>(SendMessageW(item.hwndItem, WM_GETFONT, 0, 0));
    label(item.hDC, text, area, font ? font : body, text_color, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    if (item.itemState & ODS_FOCUS) { InflateRect(&area, -px(4), -px(4)); DrawFocusRect(item.hDC, &area); }
}
void Theme::homeButton(const DRAWITEMSTRUCT& item, bool secondary) const {
    const bool enabled = !(item.itemState & ODS_DISABLED);
    const bool active = enabled && ((item.itemState & ODS_SELECTED) || GetPropW(item.hwndItem, L"HiFaceHover"));
    RECT area = item.rcItem; fill(item.hDC, area, home_colors::background);
    InflateRect(&area, -1, -1);
    card(item.hDC, area, active ? home_colors::hover : home_colors::surface,
         active ? home_colors::hover_line : home_colors::line, px(10));
    wchar_t text[256]{}; GetWindowTextW(item.hwndItem, text, 256);
    label(item.hDC, text, area, body, secondary || !enabled ? home_colors::surface_secondary : home_colors::text,
          DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    if (item.itemState & ODS_FOCUS) { InflateRect(&area, -px(4), -px(4)); DrawFocusRect(item.hDC, &area); }
}
}
