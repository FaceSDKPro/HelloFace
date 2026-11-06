package com.hiface.sdk.demo.camera;

import android.os.Bundle;

import androidx.annotation.Nullable;
import androidx.lifecycle.Lifecycle;

import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.ui.DemoWindowInsets;
import com.hiface.sdk.demo.ui.FaceCaptureOverlayView;

/**
 * Shared camera and request cleanup for capture, liveness, and dynamic verification; each screen
 * retains its configuration, results, and dialogs.
 *
 * 采集、活体与动态验证页共用的相机/请求收尾；业务配置、结果和弹窗仍留在各页面。
 */
public abstract class CameraFlowActivity extends CameraBrightnessActivity {
    protected CameraPreviewFragment cameraPreview;
    protected FaceCaptureOverlayView captureOverlay;
    protected HiFaceSdk hiFaceSdk;
    private final CameraFlowRequest flow = new CameraFlowRequest();

    @Override
    protected void onCreate(@Nullable Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_face_capture);
        DemoWindowInsets.applyToContent(this);
        findViewById(R.id.backButton).setOnClickListener(v -> finish());
        cameraPreview = CameraPreviewFragment.require(getSupportFragmentManager(), R.id.cameraPreview);
        captureOverlay = findViewById(R.id.captureOverlay);
        cameraPreview.setCameraReadyListener(this::startCameraFlow);
    }

    /**
     * Dynamic verification can initialize after a reference is selected; exiting with an empty store
     * creates neither SDK nor camera resources.
     *
     * 动态验证可在选好参考特征后才初始化，空库退出时不创建 SDK 或启动相机。
     */
    protected final void initializeCameraSdk() {
        if (hiFaceSdk != null) return;
        // Bind this screen's SDK to its lifecycle; destruction closes requests and native resources.
        // 页面直接创建 SDK 并绑定生命周期；页面销毁时自动关闭请求和 Native 资源。
        hiFaceSdk = HiFaceSdk.builder(this).lifecycleOwner(this).build();
        cameraPreview.setFrameListener(frame -> {
            if (flow.isActive()) hiFaceSdk.processFrame(frame);
        });
    }

    /**
     * Use the same entry point for the first frame and retries; each screen also checks its confirmation
     * and result dialogs.
     *
     * 首帧和重试共用入口；页面额外检查自己的确认/结果弹窗。
     */
    protected abstract void startCameraFlow();

    protected final boolean canStartCameraFlow() {
        return hiFaceSdk != null && !flow.isActive() && !isFinishing()
                && getLifecycle().getCurrentState().isAtLeast(Lifecycle.State.STARTED)
                && cameraPreview.isCameraReady();
    }

    /**
     * Keep SDK start calls explicit in each screen; the shared layer does not choose business APIs or
     * configurations.
     *
     * SDK 启动调用仍显式写在页面，不在公共层选择业务 API 或配置。
     */
    protected final void startCameraFlowRequest(CameraFlowRequest.Starter starter) {
        if (!canStartCameraFlow()) return;
        try {
            flow.start(() -> {
                cameraPreview.resumeAnalysis();
                captureOverlay.resetCountdown();
                return starter.start();
            });
        } catch (RuntimeException | Error error) {
            stopCameraFlow();
            throw error;
        }
    }

    protected final boolean isCameraFlowRunning() {
        return flow.isActive();
    }

    /**
     * Finish success or error exactly once; stop sending frames before showing the result.
     *
     * 成功和错误只收尾一次；停止送帧后再让页面展示结果。
     */
    protected final boolean finishCameraFlow() {
        if (!flow.finish()) return false;
        cameraPreview.pauseAnalysis();
        captureOverlay.finishCountdown();
        return true;
    }

    private void stopCameraFlow() {
        flow.cancel();
        cameraPreview.pauseAnalysis();
        captureOverlay.resetCountdown();
    }

    /**
     * Cancel unfinished challenges in the background while retaining confirmed photos, input, and result
     * dialogs.
     *
     * 后台取消未完成挑战，保留页面已有的确认照片、输入和结果弹窗。
     */
    @Override
    protected void onStop() {
        stopCameraFlow();
        super.onStop();
    }
}
