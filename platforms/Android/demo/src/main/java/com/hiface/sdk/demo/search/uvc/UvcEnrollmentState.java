package com.hiface.sdk.demo.search.uvc;

import androidx.lifecycle.ViewModel;
import com.hiface.sdk.capture.FaceCaptureResult;

/** 只在内存中跨旋转保留待确认采样和草稿；图像、特征不写入 Bundle 或日志。 */
public final class UvcEnrollmentState extends ViewModel {
    FaceCaptureResult pending;
    String faceId = "", group = "";
    String errorText;
    boolean initialized, requested = true, permissionPending, retryError;

    void initialize(String initialGroup) {
        if (initialized) return;
        initialized = true;
        group = initialGroup == null ? "" : initialGroup;
    }

    @Override protected void onCleared() { pending = null; faceId = group = ""; }
}
