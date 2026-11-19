package com.hiface.sdk.demo.camera;

import android.os.Bundle;

import androidx.annotation.Nullable;
import androidx.lifecycle.Lifecycle;

import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.ui.DemoWindowInsets;
import com.hiface.sdk.demo.ui.FaceCaptureOverlayView;

/** Share camera request ownership across capture, liveness, and verification screens. */
public abstract class CameraFlowActivity extends CameraBrightnessActivity {
    protected CameraPreviewFragment cameraPreview;
    protected FaceCaptureOverlayView captureOverlay;
    protected HiFaceSdk hiFaceSdk;
    // Owns the one-shot request and exposes its active flag to the camera analysis thread.
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

    /** Bind the SDK to this screen once the flow inputs are ready. */
    protected final void initializeCameraSdk() {
        if (hiFaceSdk != null) return;
        hiFaceSdk = HiFaceSdk.builder(this).lifecycleOwner(this).build();
        cameraPreview.setFrameListener(frame -> {
            if (flow.isActive()) hiFaceSdk.processFrame(frame);
        });
    }

    /** Called when the camera is ready or the user retries. */
    protected abstract void startCameraFlow();

    /** Run the screen’s SDK start call only when the camera and lifecycle are ready. */
    protected final void startCameraFlowRequest(CameraFlowRequest.Starter starter) {
        if (hiFaceSdk == null || flow.isActive() || isFinishing() || !cameraPreview.isCameraReady()
                || !getLifecycle().getCurrentState().isAtLeast(Lifecycle.State.STARTED)) return;
        try {
            flow.start(() -> {
                cameraPreview.resumeAnalysis();
                captureOverlay.resetCountdown();
                return starter.start();
            });
        } catch (RuntimeException | Error error) {
            if (!flow.isActive()) stopCameraFlow();
            throw error;
        }
    }

    protected final boolean isCameraFlowRunning() {
        return flow.isActive();
    }

    /** Ignore duplicate callbacks and pause frames before showing the result. */
    protected final boolean finishCameraFlow() {
        if (!flow.finish()) return false;
        cameraPreview.pauseAnalysis();
        captureOverlay.finishCountdown();
        return true;
    }

    // Clear request ownership before pausing frames so a late terminal callback cannot finish twice.
    private void stopCameraFlow() {
        flow.cancel();
        cameraPreview.pauseAnalysis();
        captureOverlay.resetCountdown();
    }

    /** Cancel background requests while preserving the current confirmation or result. */
    @Override
    protected void onStop() {
        stopCameraFlow();
        super.onStop();
    }
}
