#pragma once
#include "scene.h"
#include <algorithm>
#include <cmath>

namespace hiface_linux_demo {
// Paint and hit-testing sample the same pixel centres, including fractional DPI scales.
// 绘制和命中测试使用相同像素中心，避免小数倍 DPI 下边界点击偏移。
struct ScaledDisplayTransform {
    DisplayTransform scene;
    double scale = 1;
    std::array<double,9> inverseMatrix() const {
        const auto source=scene.inverseMatrix();std::array<double,9> result{};
        for(int i=0;i<9;++i)result[i]=source[i]/(i%3<2?scale:1);
        return result;
    }
    std::pair<int,int> logicalPoint(int x,int y) const {
        const auto m=inverseMatrix();
        return {int(std::floor(m[0]*(x+.5)+m[1]*(y+.5)+m[2])),
                int(std::floor(m[3]*(x+.5)+m[4]*(y+.5)+m[5]))};
    }
};
struct DesktopSize { int width, height; };
inline DesktopSize landscapeSize(int width, int height, int available_width, int available_height, double scale = 1) {
    const int max_width = std::max(1, available_width), max_height = std::max(1, available_height);
    width = std::clamp(width, std::min(int(960 * scale), max_width), max_width);
    const int limit = std::min(max_height, std::max(1, width * 2 / 3));
    height = std::clamp(height, std::min(int(600 * scale), limit), limit);
    return {width, height};
}
struct HomeLayout {
    Rect viewport;
    int columns, rows, step, card_height, count;
    HomeLayout(int width, int height, int entries,bool embedded=false)
        : viewport{28,112,width-56,std::max(1,height-228)},
          columns(embedded?1:width>=1080?4:2), rows((entries+columns-1)/columns), count(entries) {
        card_height = embedded ? 76 : std::clamp((viewport.h-11*(rows-1))/rows, 76, 144);
        step = card_height + 11;
    }
    int maxScroll() const { return std::max(0, rows*step-11-viewport.h); }
    Rect card(int index, int scroll) const {
        const int width = (viewport.w-11*(columns-1))/columns;
        return {viewport.x+(index%columns)*(width+11), viewport.y+(columns==1?0:std::max(0,(viewport.h-(rows*step-11))/2))+(index/columns)*step-scroll,width,card_height};
    }
};
}
