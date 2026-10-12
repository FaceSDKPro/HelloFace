package com.hiface.sdk.demo.camera;

import android.view.Window;
import android.view.WindowManager;

import androidx.appcompat.app.AppCompatActivity;

/** 非搜索相机页的统一亮度策略：每次进入前台设为 90%，离开前台恢复原窗口值。 */
public abstract class CameraBrightnessActivity extends AppCompatActivity {
    private static final float CAMERA_BRIGHTNESS = .90f;

    private float previousWindowBrightness;
    private boolean brightnessApplied;

    @Override
    protected void onResume() {
        super.onResume();
        if (brightnessApplied) return;
        Window window = getWindow();
        WindowManager.LayoutParams attributes = window.getAttributes();
        previousWindowBrightness = attributes.screenBrightness;
        attributes.screenBrightness = CAMERA_BRIGHTNESS;
        window.setAttributes(attributes);
        brightnessApplied = true;
    }

    @Override
    protected void onPause() {
        restoreWindowBrightness();
        super.onPause();
    }

    /** -1 表示恢复为继续跟随系统亮度，不把页面的 90% 写进系统设置。 */
    private void restoreWindowBrightness() {
        if (!brightnessApplied) return;
        Window window = getWindow();
        WindowManager.LayoutParams attributes = window.getAttributes();
        attributes.screenBrightness = previousWindowBrightness;
        window.setAttributes(attributes);
        brightnessApplied = false;
    }
}
