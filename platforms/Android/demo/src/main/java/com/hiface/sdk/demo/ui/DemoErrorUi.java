package com.hiface.sdk.demo.ui;

import android.content.Context;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.StringRes;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.common.HiFaceErrorUi;
import java.util.EnumSet;

/**
 * Map SDK status to user guidance; keep original errors in logs and control retries in the Demo.
 *
 * 将 SDK 状态转成用户提示；原始错误写入日志，重试策略由 Demo 决定。
 */
public final class DemoErrorUi {
    private static final String TAG = "HiFaceDemo";
    // The published 0.8.15 AAR and the current SDK share these public codes.
    private static final EnumSet<HiFaceErrorCode> ACCESS_ERRORS = EnumSet.of(
            HiFaceErrorCode.LICENSE_MISSING, HiFaceErrorCode.LICENSE_INVALID,
            HiFaceErrorCode.LICENSE_NOT_YET_VALID, HiFaceErrorCode.LICENSE_EXPIRED,
            HiFaceErrorCode.LICENSE_FEATURE_DENIED, HiFaceErrorCode.LICENSE_CLOCK_INVALID);

    private DemoErrorUi() {
    }

    @NonNull
    public static String messageFor(@NonNull Context context, @NonNull HiFaceError error) {
        log(error);
        return HiFaceErrorUi.messageFor(context, error);
    }

    /**
     * Configuration, capability, and model errors require fixing the cause first; do not offer ineffective
     * retries.
     *
     * 配置、能力和模型错误需要先修复原因，不向用户提供无效重试。
     */
    public static boolean isRetryable(@NonNull HiFaceError error) {
        switch (error.getCode()) {
            case NOT_READY:
            case IMAGE_NO_FACE:
            case IMAGE_FACE_TOO_SMALL:
            case BUSY:
            case PROCESSING_FAILED:
                return true;
            default:
                return false;
        }
    }

    /**
     * Identify SDK status errors so the caller can stop analysis and avoid repeated prompts.
     *
     * 识别 SDK 状态错误，供调用页面停止分析并避免重复提示。
     */
    public static boolean isAccessError(@NonNull HiFaceError error) {
        return ACCESS_ERRORS.contains(error.getCode());
    }

    /**
     * Use a generic unavailable message; diagnostics retain the original SDK error code.
     *
     * 界面统一提示功能不可用，诊断日志保留原始错误码。
     */
    @StringRes
    public static int accessMessage(@NonNull HiFaceErrorCode code) {
        return ACCESS_ERRORS.contains(code) ? HiFaceErrorUi.messageResource(code) : 0;
    }

    private static void log(@NonNull HiFaceError error) {
        Throwable cause = error.getCause();
        if (cause == null) {
            Log.e(TAG, error.toString());
        } else {
            Log.e(TAG, error.toString(), cause);
        }
    }
}
