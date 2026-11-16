package com.hiface.sdk.demo.ui;

import android.content.Context;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.StringRes;

import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.common.HiFaceErrorUi;
import com.hiface.sdk.demo.R;

/**
 * Map SDK status to user guidance; keep original errors in logs and control retries in the Demo.
 *
 * 将 SDK 状态转成用户提示；原始错误写入日志，重试策略由 Demo 决定。
 */
public final class DemoErrorUi {
    private static final String TAG = "HiFaceDemo";

    private DemoErrorUi() {}

    @NonNull
    public static String messageFor(@NonNull Context context, @NonNull HiFaceError error) {
        log(error);
        return context.getString(messageResource(error.getCode()));
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
    public static boolean isLicenseError(@NonNull HiFaceError error) {
        return licenseMessage(error.getCode()) != 0;
    }

    /**
     * Use a generic unavailable message; diagnostics retain the original SDK error code.
     *
     * 界面统一提示功能不可用，诊断日志保留原始错误码。
     */
    @StringRes
    public static int licenseMessage(@NonNull HiFaceErrorCode code) {
        return HiFaceErrorUi.isLicenseError(code) ? R.string.access_unavailable : 0;
    }

    private static void log(@NonNull HiFaceError error) {
        Throwable cause = error.getCause();
        if (cause == null) {
            Log.e(TAG, error.toString());
        } else {
            Log.e(TAG, error.toString(), cause);
        }
    }

    @StringRes
    private static int messageResource(@NonNull HiFaceErrorCode code) {
        int accessMessage = licenseMessage(code);
        return accessMessage != 0 ? accessMessage : HiFaceErrorUi.messageResource(code);
    }
}
