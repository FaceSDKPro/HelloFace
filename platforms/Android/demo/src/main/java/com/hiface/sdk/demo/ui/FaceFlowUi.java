package com.hiface.sdk.demo.ui;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.StringRes;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.flow.FaceAction;
import com.hiface.sdk.flow.FaceFlowOutcome;
import com.hiface.sdk.flow.FaceFlowProgress;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Shared presentation mapping for face-flow progress, actions, and business rejections in the Demo.
 *
 * Demo 中人脸流程进度、动作和业务失败的统一展示映射。
 */
public final class FaceFlowUi {
    private static final SecureRandom RANDOM = new SecureRandom();

    private FaceFlowUi() {
    }

    /**
     * Generate distinct actions for each round; applications may supply their own challenge policy.
     *
     * 每轮生成不重复的动作；业务可替换为自己的挑战策略。
     */
    @NonNull
    public static List<FaceAction> randomActions(int count) {
        ArrayList<FaceAction> actions = new ArrayList<>(Arrays.asList(FaceAction.values()));
        if (count < 0 || count > actions.size()) {
            throw new IllegalArgumentException("Action count is outside [0," + actions.size() + "]");
        }
        Collections.shuffle(actions, RANDOM);
        return new ArrayList<>(actions.subList(0, count));
    }

    /** Render live verification guidance and return the short prompt to speak, if any. */
    @Nullable
    public static String renderVerifyProgress(
            @NonNull FaceCaptureOverlayView overlay,
            @NonNull FaceFlowProgress progress,
            long actionTimeoutMillis
    ) {
        Context context = overlay.getContext();
        FaceAction action = progress.getAction();
        switch (progress.getStage()) {
            case WAITING_FOR_FACE:
                return showWaitingStatus(overlay, R.string.capture_status_no_face, action != null);
            case MULTIPLE_FACES:
                return showWaitingStatus(overlay, R.string.capture_status_multiple_faces, action != null);
            case FACE_TOO_SMALL:
                return showWaitingStatus(overlay, R.string.capture_status_move_closer, action != null);
            case PERFORM_ACTION:
                String actionText = actionName(context, action);
                overlay.setStatusText(context.getString(R.string.liveness_perform_action,
                        actionText, progress.getStepNumber(), progress.getStepCount()));
                overlay.startCountdownIfIdle(actionTimeoutMillis * progress.getStepCount());
                return action == null ? null : actionText;
            case FACE_NOT_FRONTAL:
            case FACE_FORWARD:
            case HOLD_STILL:
                String frontalPrompt = context.getString(R.string.liveness_face_forward);
                overlay.setStatusText(frontalPrompt);
                overlay.resetCountdown();
                return frontalPrompt;
            case FACE_UNSTABLE:
                CaptureStatusUi.apply(overlay, progress.getStage());
                break;
        }
        return null;
    }

    /**
     * Map rejected business outcomes to Demo text. Screens handle PASSED messages themselves.
     *
     * 未通过的业务终态 -> Demo 文案。PASSED 由各页面自己出成功文案，不走这里。
     */
    @NonNull
    public static String rejectionMessage(
            @NonNull Context context,
            @NonNull FaceFlowOutcome outcome
    ) {
        return context.getString(rejectionMessageResource(outcome));
    }

    private static String showWaitingStatus(
            @NonNull FaceCaptureOverlayView overlay,
            @StringRes int message,
            boolean actionPending
    ) {
        String prompt = overlay.getContext().getString(message);
        overlay.setStatusText(prompt);
        if (actionPending) {
            // The total action deadline does not pause for brief face loss, multiple faces, or distance changes;
            // retain the same ring countdown.
            // 动作总时限不会因短暂丢脸、多人或距离变化而暂停，圆环也保持同一倒计时。
            overlay.resetCountdownIfIdle();
        } else {
            // After the final frontal hold is interrupted, the next HOLD_STILL must restart from a full ring.
            // 最终正脸保持被打断后，下一次 HOLD_STILL 必须重新从完整圆环开始。
            overlay.resetCountdown();
        }
        return prompt;
    }

    @StringRes
    private static int rejectionMessageResource(@NonNull FaceFlowOutcome outcome) {
        switch (outcome) {
            case NO_FACE_TIMEOUT:
                return R.string.liveness_failed_no_face;
            case FACE_LOST:
                return R.string.liveness_failed_face_lost;
            case MULTIPLE_FACES:
                return R.string.liveness_failed_multiple_faces;
            case ACTION_TIMEOUT:
                return R.string.liveness_failed_action_timeout;
            case FINAL_CAPTURE_TIMEOUT:
                return R.string.liveness_failed_final_capture;
            case SPOOF_DETECTED:
                return R.string.liveness_failed_spoof;
            case NOT_MATCHED:
                return R.string.verification_failed_not_matched;
            case PASSED:
            default:
                // Use fallback text for new SDK outcomes rather than crashing the Demo.
                // SDK 追加新的终态时走到这里；显示一句兜底，而不是崩在 Demo 里。
                return R.string.liveness_result_rejected;
        }
    }

    @NonNull
    private static String actionName(
            @NonNull Context context,
            @Nullable FaceAction action
    ) {
        if (action == null) {
            return context.getString(R.string.liveness_action_face);
        }
        switch (action) {
            case SHAKE_HEAD:
                return context.getString(R.string.liveness_action_shake_head);
            case NOD_HEAD:
                return context.getString(R.string.liveness_action_nod_head);
            case BLINK:
                return context.getString(R.string.liveness_action_blink);
            case MOUTH_OPEN:
            default:
                return context.getString(R.string.liveness_action_mouth_open);
        }
    }
}
