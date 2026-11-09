package com.hiface.sdk.demo.search.uvc;

import androidx.lifecycle.ViewModel;
import com.hiface.sdk.capture.FaceCaptureResult;

/** Retains the pending sample/draft in memory across rotation. 中文：图像和特征不写入 Bundle 或日志。 */
public final class UvcEnrollmentState extends ViewModel {
    FaceCaptureResult pending;
    String faceId = "", group = "";
    String errorText;
    boolean initialized, requested = true, permissionPending, retryError;

    /** Read the initial search group once; recreation must preserve the edited draft. */
    void initialize(String initialGroup) {
        if (initialized) return;
        initialized = true;
        group = initialGroup == null ? "" : initialGroup;
    }

    @Override protected void onCleared() { pending = null; faceId = group = ""; }
}
