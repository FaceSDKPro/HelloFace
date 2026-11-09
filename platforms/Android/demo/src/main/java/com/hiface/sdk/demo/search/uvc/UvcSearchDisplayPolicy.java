package com.hiface.sdk.demo.search.uvc;

import android.view.Window;
import android.view.WindowManager;

/** Adjust this window's brightness on main and restore it when capture stops. 中文：仅影响当前窗口。 */
final class UvcSearchDisplayPolicy {
    private final Window window;
    private boolean active;
    private float previousBrightness;

    UvcSearchDisplayPolicy(Window window) { this.window = window; }

    void start() {
        if (active) return;
        previousBrightness = window.getAttributes().screenBrightness;
        active = true;
        setIdle(false);
    }

    void setIdle(boolean idle) {
        if (active) brightness(idle ? .1f : .9f);
    }

    void stop() {
        if (!active) return;
        active = false;
        brightness(previousBrightness);
    }

    private void brightness(float value) {
        WindowManager.LayoutParams attributes = window.getAttributes();
        if (attributes.screenBrightness == value) return;
        attributes.screenBrightness = value;
        window.setAttributes(attributes);
    }
}
