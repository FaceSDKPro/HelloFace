package com.hiface.sdk.demo.detection;

import android.os.Bundle;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.camera.view.PreviewView;

import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.common.HiFaceResult;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.camera.CameraBrightnessActivity;
import com.hiface.sdk.demo.camera.CameraPreviewFragment;
import com.hiface.sdk.detection.FaceDetectionConfig;
import com.hiface.sdk.detection.FaceDetectionResult;

/** 实时展示人脸框、五点、局部轮廓和头姿角度。 */
public final class FaceDetectionActivity extends CameraBrightnessActivity {
    private CameraPreviewFragment cameraPreview;
    private FaceDetectionOverlayView detectionOverlay;
    private final Object overlayUpdateLock = new Object();
    @Nullable
    private FaceDetectionResult pendingOverlayFrame;
    private boolean overlayUpdatePosted;
    private boolean overlayActive;
    private final Runnable overlayUpdater = this::applyLatestOverlayFrame;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_face_detection);

        cameraPreview = CameraPreviewFragment.require(
                getSupportFragmentManager(), R.id.cameraPreview);
        cameraPreview.configureOverlayPreview(PreviewView.ScaleType.FIT_CENTER);
        detectionOverlay = findViewById(R.id.detectionOverlay);
        findViewById(R.id.backButton).setOnClickListener(view -> finish());
        findViewById(R.id.switchCameraButton).setOnClickListener(view -> switchCamera());
        HiFaceSdk sdk = HiFaceSdk.builder(this)
                .lifecycleOwner(this) //自动管理生命周期，关闭资源
                .build();

        FaceDetectionConfig detectionConfig = FaceDetectionConfig.builder()
                .maxFaces(10) // 本页面需要展示多人；上限越高，低配设备开销越大
                .detailedLandmarks(true) // 本页面需要展示 468 点轮廓与头姿
                .build();

        //分析相机帧
        cameraPreview.setFrameListener(frame -> {
            HiFaceResult<FaceDetectionResult> result = sdk.processFrame(frame, detectionConfig);
            if (result.isFailure()) {
                return;
            }
            FaceDetectionResult frameResult = result.requireValue();
            queueOverlayUpdate(frameResult);
        });
    }



    /**
     * 主线程只保留尚未绘制的最新结果，并按下一次 vsync 更新，避免推理快于绘制时积压 Runnable。
     * {@link FaceDetectionResult} 是不可变快照；相机的 YUV Buffer 不会跨出分析回调。
     */
    private void queueOverlayUpdate(@NonNull FaceDetectionResult frameResult) {
        synchronized (overlayUpdateLock) {
            if (!overlayActive) return;
            pendingOverlayFrame = frameResult;
            if (!overlayUpdatePosted) {
                overlayUpdatePosted = true;
                // 投递和取消共用锁，不能在 onStop 清空后才补投旧 Activity 的刷新。
                detectionOverlay.postOnAnimation(overlayUpdater);
            }
        }
    }

    private void applyLatestOverlayFrame() {
        FaceDetectionResult frameResult;
        synchronized (overlayUpdateLock) {
            frameResult = overlayActive ? pendingOverlayFrame : null;
            pendingOverlayFrame = null;
            overlayUpdatePosted = false;
        }
        if (frameResult != null && !isFinishing() && !isDestroyed()) {
            detectionOverlay.updateFaces(frameResult,
                    cameraPreview.analysisToPreview(frameResult.getImageWidth(), frameResult.getImageHeight()));
        }
    }

    private void clearOverlayUpdates() {
        synchronized (overlayUpdateLock) {
            overlayActive = false;
            detectionOverlay.removeCallbacks(overlayUpdater);
            pendingOverlayFrame = null;
            overlayUpdatePosted = false;
        }
        detectionOverlay.clear();
    }

    @Override
    protected void onStart() {
        super.onStart();
        synchronized (overlayUpdateLock) { overlayActive = true; }
    }

    @Override
    protected void onStop() {
        clearOverlayUpdates();
        super.onStop();
    }

    @Override
    protected void onDestroy() {
        clearOverlayUpdates();
        super.onDestroy();
    }

    private void switchCamera() {
        if (!cameraPreview.switchCamera()) {
            Toast.makeText(
                    getApplicationContext(),
                    R.string.camera_switch_unavailable,
                    Toast.LENGTH_SHORT).show();
        }
    }
}
