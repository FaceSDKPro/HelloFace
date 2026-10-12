package com.hiface.sdk.demo.verification;

import android.app.Dialog;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Bundle;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;

import com.hiface.sdk.capture.FaceCaptureListener;
import com.hiface.sdk.capture.FaceCaptureResult;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.camera.CameraFlowActivity;
import com.hiface.sdk.demo.ui.CaptureStatusUi;
import com.hiface.sdk.demo.ui.DemoErrorUi;
import com.hiface.sdk.flow.FaceFlowProgress;

/**
 * 人脸采集演示页：相机由 Demo 适配层管理，模型线程、采集状态机及退出竞态由 SDK 负责。
 */
public final class FaceEnrollmentActivity extends CameraFlowActivity {
    private FaceFeatureStore featureStore;

    @Nullable
    private Dialog confirmationDialog;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        featureStore = new FaceFeatureStore();
        initializeCameraSdk();
    }

    /** 开始一次 SDK 引导采集；请求完成后，重试时显式启动下一次。 */
    @Override
    protected void startCameraFlow() {
        if (!canStartCameraFlow() || confirmationDialog != null) return;
        startCameraFlowRequest(() -> hiFaceSdk.capture().startCameraCapture(new FaceCaptureListener() {
            @Override
            public void onProgress(@NonNull FaceFlowProgress progress) {
                if (isCameraFlowRunning()) CaptureStatusUi.apply(captureOverlay, progress.getStage());
            }

            @Override
            public void onResult(@NonNull FaceCaptureResult capture) {
                if (!finishCameraFlow()) return;
                handleFaceCaptured(capture);
            }

            /**
             * 传入参数错误，SDK底层异常导致无法完成这次请求，没有形成业务结论
             */
            @Override
            public void onError(@NonNull HiFaceError error) {
                if (!finishCameraFlow()) return;
                handleCaptureFailure(error);
            }
        }));
    }

    /** 退出确认态并恢复相机，同时开始下一次单次引导采集。 */
    private void resumeEnrollmentCapture() {
        dismissConfirmation();
        captureOverlay.setStatusText(R.string.capture_face_guide);
        startCameraFlow();
    }

    /** 从不可变抓拍样本创建确认预览，并切换到录入确认状态。 */
    private void handleFaceCaptured(@NonNull FaceCaptureResult capture) {
        Bitmap preview = capture.getAlignedFace();
        // CameraX 前摄 PreviewView 默认按自拍镜像显示；SDK 抓拍结果保持未镜像坐标。
        // 仅镜像确认页的显示，使其与实时预览一致，不修改 Bitmap 和人脸特征。
        boolean mirrorForDisplay = cameraPreview.isFrontCamera();
        showConfirmation(capture, preview, mirrorForDisplay);
    }

    /** 展示抓拍结果；确认后只在 Demo 的加密 MMKV 保存 Face ID 与特征字符串。 */
    private void showConfirmation(
            @NonNull FaceCaptureResult capture,
            @NonNull Bitmap preview,
            boolean mirrorForDisplay
    ) {
        dismissConfirmation();
        Dialog dialog = new Dialog(this);
        confirmationDialog = dialog;
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setContentView(R.layout.dialog_face_enrollment);
        dialog.setCancelable(false);
        ImageView imageView = dialog.findViewById(R.id.capturedFaceImage);
        EditText faceIdInput = dialog.findViewById(R.id.faceIdInput);
        imageView.setClipToOutline(true);
        imageView.setScaleX(mirrorForDisplay ? -1f : 1f);
        imageView.setImageBitmap(preview);
        dialog.setOnDismissListener(ignored -> {
            if (confirmationDialog == dialog) {
                confirmationDialog = null;
            }
            imageView.setImageDrawable(null);
            if (!preview.isRecycled()) {
                preview.recycle();
            }
        });

        dialog.findViewById(R.id.retryButton).setOnClickListener(v -> {
            dialog.dismiss();
            resumeEnrollmentCapture();
        });
        dialog.findViewById(R.id.confirmButton).setOnClickListener(v -> {
            String faceId = faceIdInput.getText().toString().trim();
            if (faceId.isEmpty()) {
                faceIdInput.setError(getString(R.string.enroll_face_id_required));
                return;
            }
            if (!featureStore.save(faceId, capture.getFeature())) {
                Toast.makeText(
                        getApplicationContext(),
                        R.string.enroll_save_failed,
                        Toast.LENGTH_SHORT).show();
                return;
            }
            Toast.makeText(
                    getApplicationContext(),
                    R.string.enroll_capture_complete,
                    Toast.LENGTH_SHORT).show();
            dialog.dismiss();
            setResult(RESULT_OK);
            finish();
        });

        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
            WindowManager.LayoutParams attributes = window.getAttributes();
            attributes.dimAmount = 0.62f;
            window.setAttributes(attributes);
        }
        dialog.show();
        if (window != null) {
            window.setLayout(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT);
        }
    }

    /** 直接创建的宿主 Dialog 不属于 SDK，由页面统一关闭并触发预览 Bitmap 回收。 */
    private void dismissConfirmation() {
        Dialog dialog = confirmationDialog;
        confirmationDialog = null;
        if (dialog != null && dialog.isShowing()) {
            dialog.dismiss();
        }
    }

    private void handleCaptureFailure(@NonNull HiFaceError error) {
        captureOverlay.setStatusText(R.string.enroll_capture_failed);
        AlertDialog.Builder builder = new AlertDialog.Builder(this)
                .setMessage(DemoErrorUi.messageFor(this, error))
                .setNegativeButton(R.string.verification_close, (dialog, which) -> finish())
                .setCancelable(false);
        if (DemoErrorUi.isRetryable(error)) {
            builder.setPositiveButton(R.string.verification_retry,
                    (dialog, which) -> resumeEnrollmentCapture());
        }
        confirmationDialog = builder.show();
    }

    @Override
    protected void onDestroy() {
        dismissConfirmation();
        super.onDestroy();
    }
}
