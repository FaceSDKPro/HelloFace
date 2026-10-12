package com.hiface.sdk.demo.ui;

import android.content.Context;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.StringRes;

import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.demo.R;

/** 将 SDK 稳定错误码映射为 Demo 的本地化文案和恢复策略。 */
public final class DemoErrorUi {
    private static final String TAG = "HiFaceDemo";

    private DemoErrorUi() {}

    @NonNull
    public static String messageFor(@NonNull Context context, @NonNull HiFaceError error) {
        log(error);
        return context.getString(messageResource(error.getCode()));
    }

    /** 配置、能力和模型错误需要先修复原因，不向用户提供无效重试。 */
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
        switch (code) {
            case NOT_READY:
                return R.string.sdk_error_not_ready;
            case CLOSED:
                return R.string.sdk_error_closed;
            case INVALID_ARGUMENT:
                return R.string.sdk_error_invalid_argument;
            case UNSUPPORTED_FORMAT:
                return R.string.sdk_error_unsupported_format;
            case MODEL_LOAD_FAILED:
                return R.string.sdk_error_model_load_failed;
            case IMAGE_NO_FACE:
                return R.string.sdk_error_no_face;
            case IMAGE_FACE_TOO_SMALL:
                return R.string.sdk_error_face_too_small;
            case BUSY:
                return R.string.sdk_error_busy;
            case PROCESSING_FAILED:
                return R.string.sdk_error_processing_failed;
            case INTERNAL_ERROR:
            default:
                return R.string.sdk_error_internal;
        }
    }
}
