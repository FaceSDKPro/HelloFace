package com.hiface.sdk.demo.ui;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.StringRes;

import com.hiface.sdk.demo.R;
import com.hiface.sdk.flow.FaceFlowStage;

/** 录入与验证页共享的采集状态文案和稳定倒计时。 */
public final class CaptureStatusUi {
    static final long CAPTURE_STABLE_COUNTDOWN_MILLIS = 700L;

    private CaptureStatusUi() {
    }

    public static void apply(
            @NonNull FaceCaptureOverlayView overlay,
            @NonNull FaceFlowStage status) {
        apply(overlay, status, CAPTURE_STABLE_COUNTDOWN_MILLIS);
    }

    static void apply(
            @NonNull FaceCaptureOverlayView overlay,
            @NonNull FaceFlowStage status,
            long stableCountdownMillis) {
        Integer text = statusText(status);
        if (text == null) {
            // PERFORM_ACTION / FACE_FORWARD 属于活体与动态验证；引导采集不会走到，
            // 真出现时保持上一条提示，而不是显示一句语义不对的文案。
            return;
        }
        overlay.setStatusText(text);
        if (status == FaceFlowStage.HOLD_STILL) {
            overlay.startCountdown(stableCountdownMillis);
        } else {
            overlay.resetCountdown();
        }
    }

    @StringRes
    @Nullable
    private static Integer statusText(@NonNull FaceFlowStage status) {
        switch (status) {
            case WAITING_FOR_FACE:
                return R.string.capture_status_no_face;
            case MULTIPLE_FACES:
                return R.string.capture_status_multiple_faces;
            case FACE_TOO_SMALL:
                return R.string.capture_status_move_closer;
            case FACE_NOT_FRONTAL:
                return R.string.capture_status_not_frontal;
            case HOLD_STILL:
                return R.string.capture_status_hold_still;
            case FACE_UNSTABLE:
                return R.string.capture_status_hold_still;
            default:
                return null;
        }
    }
}
