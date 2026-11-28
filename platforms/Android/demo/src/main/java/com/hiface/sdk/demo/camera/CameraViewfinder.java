package com.hiface.sdk.demo.camera;

import android.content.Context;
import android.util.AttributeSet;
import android.widget.FrameLayout;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

public final class CameraViewfinder extends FrameLayout {
    public CameraViewfinder(@NonNull Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
        // The XML attribute requires API 31. The native clip works on older devices too.
        setClipToOutline(true);
    }
}
