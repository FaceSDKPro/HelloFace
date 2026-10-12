package com.hiface.sdk.demo.ui;

import android.content.Context;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.StringRes;

import com.hiface.sdk.demo.R;
import com.hiface.sdk.flow.FaceAction;
import com.hiface.sdk.flow.FaceFlowOutcome;
import com.hiface.sdk.flow.FaceFlowProgress;
import com.hiface.sdk.flow.FaceFlowStage;

import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/** Demo 中人脸流程进度、动作和业务失败的统一展示映射。 */
public final class FaceFlowUi {
    private static final SecureRandom RANDOM = new SecureRandom();
    private FaceFlowUi() {}

    /** 每轮生成不重复的动作；业务可替换为自己的挑战策略。 */
    @NonNull
    public static List<FaceAction> randomActions(int count) {
        ArrayList<FaceAction> actions = new ArrayList<>(Arrays.asList(FaceAction.values()));
        if (count < 0 || count > actions.size()) {
            throw new IllegalArgumentException("Action count is outside [0," + actions.size() + "]");
        }
        Collections.shuffle(actions, RANDOM);
        return new ArrayList<>(actions.subList(0, count));
    }

    /** 活体与动态 1:1 的动作进度映射；引导采集单独使用 CaptureStatusUi。 */
    private static void renderFlowProgress(
            @NonNull FaceCaptureOverlayView overlay,
            @NonNull FaceFlowProgress progress,
            long actionTimeoutMillis
    ) {
        switch (progress.getStage()) {
            case WAITING_FOR_FACE:
                showWaitingStatus(
                        overlay,
                        R.string.capture_status_no_face,
                        progress.getAction() != null);
                return;
            case MULTIPLE_FACES:
                showWaitingStatus(
                        overlay,
                        R.string.capture_status_multiple_faces,
                        progress.getAction() != null);
                return;
            case FACE_TOO_SMALL:
                showWaitingStatus(
                        overlay,
                        R.string.capture_status_move_closer,
                        progress.getAction() != null);
                return;
            case PERFORM_ACTION:
                showActionInstruction(overlay, progress);
                overlay.startCountdownIfIdle(
                        actionTimeoutMillis * progress.getStepCount());
                return;
            case FACE_NOT_FRONTAL:
            case FACE_FORWARD:
                // 两个阶段都表示尚未取得合格正脸，统一文案避免连续闪过两种同义提示。
                overlay.setStatusText(R.string.liveness_face_forward);
                overlay.resetCountdown();
                return;
            case HOLD_STILL:
            case FACE_UNSTABLE:
                CaptureStatusUi.apply(overlay, progress.getStage());
                return;
        }
    }

    /**
     * 活体页与动态 1:1 复合认证页共用：稳定阶段在后台计时，界面保持正对提示且不播放
     * 圆环倒计时动画。SDK 完整交付 Core 阶段，FACE_FORWARD、FACE_NOT_FRONTAL 与 HOLD_STILL
     * 的同义提示只在本展示层合并，不屏蔽 SDK 进度事件。
     */
    public static void renderVerifyProgress(
            @NonNull FaceCaptureOverlayView overlay,
            @NonNull FaceFlowProgress progress,
            long actionTimeoutMillis
    ) {
        if (progress.getStage() == FaceFlowStage.HOLD_STILL) {
            overlay.setStatusText(R.string.liveness_face_forward);
            overlay.resetCountdown();
            return;
        }
        renderFlowProgress(overlay, progress, actionTimeoutMillis);
    }

    /** 未通过的业务终态 -> Demo 文案。PASSED 由各页面自己出成功文案，不走这里。 */
    @NonNull
    public static String rejectionMessage(
            @NonNull Context context,
            @NonNull FaceFlowOutcome outcome
    ) {
        return context.getString(rejectionMessageResource(outcome));
    }

    private static void showWaitingStatus(
            @NonNull FaceCaptureOverlayView overlay,
            @StringRes int message,
            boolean actionPending
    ) {
        overlay.setStatusText(message);
        if (actionPending) {
            // 动作总时限不会因短暂丢脸、多人或距离变化而暂停，圆环也保持同一倒计时。
            overlay.resetCountdownIfIdle();
        } else {
            // 最终正脸保持被打断后，下一次 HOLD_STILL 必须重新从完整圆环开始。
            overlay.resetCountdown();
        }
    }

    private static void showActionInstruction(
            @NonNull FaceCaptureOverlayView overlay,
            @NonNull FaceFlowProgress progress
    ) {
        overlay.setStatusText(overlay.getContext().getString(
                R.string.liveness_perform_action,
                actionName(overlay.getContext(), progress.getAction()),
                progress.getStepNumber(),
                progress.getStepCount()));
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
