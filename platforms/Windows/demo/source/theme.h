#pragma once
#include <windows.h>
namespace hiface_demo {
constexpr UINT kRevealFocusedControl = WM_APP + 20;
namespace colors {
constexpr COLORREF background = RGB(243, 246, 251), surface = RGB(255, 255, 255);
constexpr COLORREF ink = RGB(28, 39, 60), muted = RGB(103, 117, 139), line = RGB(222, 229, 239);
constexpr COLORREF primary = RGB(42, 97, 222), selected = RGB(231, 239, 255);
constexpr COLORREF canvas = RGB(19, 29, 46), success = RGB(29, 139, 95), error = RGB(196, 55, 65);
}
namespace home_colors {
// GDI draws opaque RGB: composite Android's white overlays over the same teal.
constexpr COLORREF background = RGB(2, 63, 66), text = RGB(255, 255, 255);
constexpr COLORREF whiteOverlay(COLORREF base, unsigned alpha) {
    return RGB((255 * alpha + GetRValue(base) * (255 - alpha) + 127) / 255,
               (255 * alpha + GetGValue(base) * (255 - alpha) + 127) / 255,
               (255 * alpha + GetBValue(base) * (255 - alpha) + 127) / 255);
}
constexpr COLORREF secondary = whiteOverlay(background, 191), surface = whiteOverlay(background, 38);
constexpr COLORREF line = whiteOverlay(surface, 61), hover = whiteOverlay(surface, 38);
constexpr COLORREF surface_secondary = whiteOverlay(surface, 191), hover_line = whiteOverlay(hover, 61);
constexpr COLORREF error = RGB(255, 150, 150);
}
struct Theme {
    HFONT body = nullptr, title = nullptr, small = nullptr, result = nullptr, parameter_title = nullptr;
    HBRUSH background = nullptr, surface = nullptr, home_background = nullptr;
    UINT dpi = 96;
    Theme(); ~Theme();
    void setDpi(UINT value);
    int px(int value) const;
    void style(HWND control);
    void button(const DRAWITEMSTRUCT& item, bool primary, bool selected, bool navigation) const;
    void homeButton(const DRAWITEMSTRUCT& item, bool secondary = false) const;
};
void fill(HDC dc, RECT rectangle, COLORREF color);
void card(HDC dc, RECT rectangle, COLORREF color, COLORREF border, int radius);
void label(HDC dc, const wchar_t* value, RECT rectangle, HFONT font, COLORREF color, UINT format = DT_LEFT | DT_VCENTER | DT_SINGLELINE);
}
