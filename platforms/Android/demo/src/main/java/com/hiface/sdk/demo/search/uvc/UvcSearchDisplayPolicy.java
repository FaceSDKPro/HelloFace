package com.hiface.sdk.demo.search.uvc;

import android.view.Window;
import android.view.WindowManager;

/** 主线程按分析状态调整当前窗口亮度，会话结束时还原。 */
final class UvcSearchDisplayPolicy {
    private final Window window;
    private boolean active;
    private float previous;

    UvcSearchDisplayPolicy(Window window) { this.window = window; }

    void start() {
        if (active) return;
        previous = window.getAttributes().screenBrightness;
        active = true;
        setIdle(false);
    }

    void setIdle(boolean idle) {
        if (active) brightness(idle ? .1f : .9f);
    }

    void stop() {
        if (!active) return;
        active = false;
        brightness(previous);
    }

    private void brightness(float value) {
        WindowManager.LayoutParams attributes = window.getAttributes();
        if (attributes.screenBrightness == value) return;
        attributes.screenBrightness = value;
        window.setAttributes(attributes);
    }
}
