#pragma once
#include <algorithm>
#include <cstdint>

namespace hiface_demo {
// Device-pixel geometry shared by drawing, pointer hit testing and scrolling.
// Keeping this independent of HWND also allows layout regressions to run on the host.
// 绘制、指针命中测试和滚动共用设备像素几何；独立于 HWND，便于在宿主执行布局回归。
struct UiRect {
    int left = 0, top = 0, right = 0, bottom = 0;
    int width() const { return std::max(0, right - left); }
    int height() const { return std::max(0, bottom - top); }
    bool contains(int x, int y) const { return x >= left && x < right && y >= top && y < bottom; }
};
struct ImageFit {
    int x = 0, y = 0, width = 0, height = 0;
    double scale = 0;
};
struct ComparisonLayout {
    UiRect slots[2], errors[2];
    ComparisonLayout(const UiRect& area, int dpi = 96) {
        const int gap = 16 * dpi / 96, caption = 52 * dpi / 96;
        const int side = std::max(1,std::min((area.width()-gap)/2,area.height()-caption));
        const int left = area.left + std::max(0,(area.width()-side*2-gap)/2);
        const int top = area.top + std::max(0,(area.height()-side-caption)/2);
        for(int i=0;i<2;++i){
            slots[i]={left+i*(side+gap),top,left+i*(side+gap)+side,top+side};
            errors[i]={slots[i].left,slots[i].bottom+4*dpi/96,slots[i].right,slots[i].bottom+caption};
        }
    }
    int slotAt(int x,int y) const { for(int i=0;i<2;++i)if(slots[i].contains(x,y))return i;return -1; }
};
inline ImageFit fitImage(int width, int height, const UiRect& area) {
    ImageFit fit;
    if (width < 1 || height < 1 || !area.width() || !area.height()) return fit;
    fit.scale = std::min(double(area.width()) / width, double(area.height()) / height);
    fit.width = static_cast<int>(width * fit.scale); fit.height = static_cast<int>(height * fit.scale);
    fit.x = area.left + (area.width() - fit.width) / 2; fit.y = area.top + (area.height() - fit.height) / 2;
    return fit;
}
struct PhotoLayout {
    UiRect client, photo, details, strip;
    int dpi = 96;
    bool sidebar = false;
    PhotoLayout(int width, int height, int count, bool notice, int scale = 96,bool prefer_sidebar=false) : client{0,0,width,height}, dpi(scale) {
        sidebar=prefer_sidebar||(width>=px(700)&&height>=px(340));
        if(sidebar){
            const int panel=(count||notice)?std::min(px(280),width/3):0;
            const int right=width-px(12),left=right-panel;
            photo={px(12),px(64),panel?left-px(12):right,height-px(12)};
            details={left,px(64),right,panel?std::min(height-px(12),px(176)):px(64)};
            strip={left,details.bottom+px(8),right,count?height-px(12):details.bottom+px(8)};
        }else{
            const int strip_height=count?px(height>=px(460)?140:height>=px(340)?116:96):0;
            const int detail_height=count?px(height>=px(400)?82:64):notice?px(64):0;
            strip={0,height-strip_height,width,height};
            details={px(12),strip.top-detail_height,std::max(px(12),width-px(12)),strip.top-px(8)};
            const int top=px(height>=px(280)?64:48);
            photo={px(12),top,std::max(px(12),width-px(12)),std::max(top,strip.top-detail_height-px(12))};
        }
    }
    int px(int value) const { return static_cast<int>((int64_t(value)*dpi+48)/96); }
    int viewport() const { return std::max(1,sidebar?strip.height()-px(12):client.width()-px(24)); }
    int content(int count) const { return count?(count-1)*px(sidebar?96:146)+px(sidebar?88:138):0; }
    int clampScroll(int position,int count) const { return std::clamp(position,0,std::max(0,content(count)-viewport())); }
    UiRect tile(int index,int scroll) const {
        if(sidebar){const int top=strip.top+px(6)+index*px(96)-scroll;return {strip.left+px(8),top,strip.right-px(8),top+px(88)};}
        const int left=px(12)+index*px(146)-scroll;return {left,strip.top+px(6),left+px(138),strip.bottom-px(6)};
    }
    int tileAt(int x,int y,int count,int scroll) const {
        if(!client.contains(x,y)||!strip.contains(x,y))return -1;
        for(int i=0;i<count;++i)if(tile(i,scroll).contains(x,y))return i;
        return -1;
    }
    int reveal(int index,int scroll,int count) const {
        const auto area=tile(index,0);
        const int first=sidebar?area.top-strip.top-px(6):area.left-px(12);
        const int last=sidebar?area.bottom-strip.top-px(6):area.right-px(12);
        if(first<scroll)scroll=first;else if(last>scroll+viewport())scroll=last-viewport();
        return clampScroll(scroll,count);
    }
};
struct HomeLayout {
    UiRect viewport;
    int count,columns,rows,card_height,step;
    HomeLayout(int width,int height,int entries) : viewport{32,112,width-32,std::max(112,height-88)},count(entries),columns(width>=1080?4:2),rows((entries+columns-1)/columns) {
        card_height=std::clamp((viewport.height()-16*(rows-1))/std::max(1,rows),84,148);step=card_height+16;
    }
    int content()const{return rows?rows*step-16:0;}
    int clampScroll(int scroll)const{return std::clamp(scroll,0,std::max(0,content()-viewport.height()));}
    UiRect card(int index,int scroll)const{
        const int width=(viewport.width()-16*(columns-1))/columns;
        const int left=viewport.left+(index%columns)*(width+16);
        const int top=viewport.top+std::max(0,(viewport.height()-content())/2)+(index/columns)*step-clampScroll(scroll);
        return {left,top,left+width,top+card_height};
    }
    UiRect visible(int index,int scroll)const{auto r=card(index,scroll);r.top=std::max(r.top,viewport.top);r.bottom=std::max(r.top,std::min(r.bottom,viewport.bottom));return r;}
    int reveal(int index,int scroll)const{const auto r=card(index,0);if(r.top-scroll<viewport.top)scroll=r.top-viewport.top;else if(r.bottom-scroll>viewport.bottom)scroll=r.bottom-viewport.bottom;return clampScroll(scroll);}
};
struct LandscapeSize{int width,height;};
inline LandscapeSize landscapeSize(int width,int height,int available_width,int available_height){
    const int max_width=std::max(1,available_width),max_height=std::max(1,available_height);
    const int minimum_width=std::min(960,max_width),minimum_height=std::min({600,max_height,std::max(1,max_width*2/3)});
    width=std::clamp(width,minimum_width,max_width);
    height=std::clamp(height,std::min(minimum_height,std::max(1,width*2/3)),std::min(max_height,std::max(1,width*2/3)));
    return {width,height};
}
// Toolbar controls wrap as a unit; native combobox popup height is independent.
// 工具栏控件整体换行；原生组合框弹出列表的高度独立处理。
struct ToolbarLayout {
    int left, right, x, y;
    ToolbarLayout(int start, int end, int top) : left(start), right(end), x(start), y(top) {}
    UiRect place(int width) {
        if (x > left && x + width > right) { x = left; y += 42; }
        UiRect area{x, y, std::min(right, x + width), y + 34}; x += width + 8; return area;
    }
};
}
