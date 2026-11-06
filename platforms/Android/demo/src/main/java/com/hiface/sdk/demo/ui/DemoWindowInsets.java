package com.hiface.sdk.demo.ui;

import android.app.Activity;
import android.os.Build;
import android.view.View;

import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

/** Keeps Demo content clear of system UI when Android enforces edge-to-edge. */
public final class DemoWindowInsets {
    private DemoWindowInsets() {}

    public static void applyToContent(Activity activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            return;
        }

        View content = activity.findViewById(android.R.id.content);
        int left = content.getPaddingLeft();
        int top = content.getPaddingTop();
        int right = content.getPaddingRight();
        int bottom = content.getPaddingBottom();
        ViewCompat.setOnApplyWindowInsetsListener(content, (view, insets) -> {
            Insets safeArea = insets.getInsets(WindowInsetsCompat.Type.systemBars()
                    | WindowInsetsCompat.Type.displayCutout()
                    | WindowInsetsCompat.Type.ime());
            view.setPadding(left + safeArea.left, top + safeArea.top,
                    right + safeArea.right, bottom + safeArea.bottom);
            return insets;
        });
        ViewCompat.requestApplyInsets(content);
    }
}
