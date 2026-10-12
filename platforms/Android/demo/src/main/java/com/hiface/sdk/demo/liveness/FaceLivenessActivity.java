package com.hiface.sdk.demo.liveness;

import android.os.Bundle;
import android.view.View;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;

import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.camera.CameraFlowActivity;
import com.hiface.sdk.demo.ui.DemoErrorUi;
import com.hiface.sdk.demo.ui.FaceFlowUi;
import com.hiface.sdk.flow.FaceFlowListener;
import com.hiface.sdk.flow.FaceFlowProgress;
import com.hiface.sdk.flow.FaceFlowResult;
import com.hiface.sdk.liveness.FaceLivenessConfig;

/** 动作活体与静默活体组合演示。 */
public final class FaceLivenessActivity extends CameraFlowActivity {
    private static final int ACTION_COUNT = 3;
    private AlertDialog dialog;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        View switchCameraButton = findViewById(R.id.switchCameraButton);
        switchCameraButton.setVisibility(View.VISIBLE);
        switchCameraButton.setOnClickListener(view -> switchCamera());

        initializeCameraSdk();
    }

    /** 每次启动创建一轮完整挑战；相机未就绪或已有请求时不重复启动。 */
    @Override
    protected void startCameraFlow() {
        if (!canStartCameraFlow()
                || (dialog != null && dialog.isShowing())) return;
        // 每次开始或重试随机选择三个不重复动作，完成并回正后执行双模型静默活体。
        FaceLivenessConfig config = FaceLivenessConfig.builder()
                .actions(FaceFlowUi.randomActions(ACTION_COUNT))
                .allowMultipleFaces(true) // 多人画面继续处理最大人脸
                .build();

        startCameraFlowRequest(() -> hiFaceSdk.liveness().startCameraLiveness(config, new FaceFlowListener() {
            @Override
            public void onProgress(@NonNull FaceFlowProgress progress) {
                if (isCameraFlowRunning()) {
                    FaceFlowUi.renderVerifyProgress(
                            captureOverlay,
                            progress,
                            config.getActionTimeoutMillis());
                }
            }

            @Override
            public void onResult(@NonNull FaceFlowResult result) {
                if (!finishCameraFlow()) return;
                // SDK 已校验纯活体终态：通过时必有有效分数。
                boolean passed = result.isPassed();
                captureOverlay.setStatusText(passed
                        ? R.string.liveness_result_passed : R.string.liveness_result_rejected);
                String message;
                if (passed) {
                    // 纯活体的 PASSED 必然已产生聚合分数；直接解包能暴露 SDK 契约违反。
                    float score = result.getLivenessScore();
                    message = getString(
                            R.string.liveness_score_format,
                            getString(R.string.liveness_result_passed),
                            score);
                } else {
                    String rejectionReason = FaceFlowUi.rejectionMessage(
                            FaceLivenessActivity.this, result.getOutcome());
                    // SPOOF_DETECTED 已产生分数；动作超时、丢脸等提前结束时只展示拒绝原因。
                    // null 表示未产生静默活体分数，不能当作 0 分展示。
                    Float livenessScore = result.getLivenessScore();
                    message = livenessScore == null
                            ? rejectionReason
                            : getString(R.string.liveness_score_format, rejectionReason, livenessScore);
                }
                // 业务结果均允许重试，与活体是否通过无关。
                showResultDialog(getString(R.string.liveness_result_title), message, true);
            }

            /**
             * 传入参数错误，SDK底层异常导致SDK 无法完成这次请求，没有形成业务结论
             */
            @Override
            public void onError(@NonNull HiFaceError error) {
                if (!finishCameraFlow()) return;
                captureOverlay.setStatusText(R.string.liveness_result_error);
                showResultDialog(
                        getString(R.string.liveness_error_title),
                        DemoErrorUi.messageFor(FaceLivenessActivity.this, error),
                        DemoErrorUi.isRetryable(error));
            }
        }));
    }

    private void switchCamera() {
        cameraPreview.pauseAnalysis();
        boolean switched = cameraPreview.switchCamera();
        // 仅用于测试镜头切换，保持当前活体请求继续处理新相机画面。
        if (isCameraFlowRunning()) cameraPreview.resumeAnalysis();
        if (!switched) {
            Toast.makeText(
                    getApplicationContext(),
                    R.string.camera_switch_unavailable,
                    Toast.LENGTH_SHORT).show();
        }
    }

    private void showResultDialog(String title, String message, boolean canRetry) {
        AlertDialog.Builder builder = new AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(message)
                .setNegativeButton(R.string.liveness_back, (ignored, which) -> finish())
                .setCancelable(false)
                .setOnCancelListener(ignored -> finish());
        if (canRetry) {
            builder.setPositiveButton(
                    R.string.liveness_retry,
                    (ignored, which) -> retry());
        }
        dialog = builder.show();
    }

    private void retry() {
        dialog = null;
        startCameraFlow();
    }

    @Override
    protected void onDestroy() {
        if (dialog != null) dialog.dismiss();
        super.onDestroy();
    }
}
