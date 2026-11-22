package com.hiface.sdk.demo.liveness;

import android.os.Bundle;
import android.view.View;
import android.widget.Toast;
import androidx.annotation.NonNull;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.camera.CameraFlowActivity;
import com.hiface.sdk.demo.recognition.RecognitionFlowContract;
import com.hiface.sdk.demo.ui.DemoErrorUi;
import com.hiface.sdk.demo.ui.FaceFlowUi;
import com.hiface.sdk.flow.FaceFlowListener;
import com.hiface.sdk.flow.FaceFlowProgress;
import com.hiface.sdk.flow.FaceFlowResult;
import com.hiface.sdk.liveness.FaceLivenessConfig;

/** Independent passive liveness with the optional ordered challenges selected on the previous page. */
public final class FaceLivenessActivity extends CameraFlowActivity {
    private FaceLivenessConfig config;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        View switchCameraButton = findViewById(R.id.switchCameraButton);
        switchCameraButton.setVisibility(View.VISIBLE);
        switchCameraButton.setOnClickListener(view -> switchCamera());
        try {
            config = FaceLivenessConfig.builder().actions(RecognitionFlowContract.actions(getIntent()))
                    .allowMultipleFaces(true).build();
        } catch (IllegalArgumentException error) {
            complete(getString(R.string.recognition_invalid_options), RecognitionFlowContract.ERROR);
            return;
        }
        preparePromptSpeech();
        initializeCameraSdk();
        startCameraFlow();
    }

    @Override protected void startCameraFlow() {
        if (config == null) return;
        startCameraFlowRequest(() -> hiFaceSdk.liveness().startCameraLiveness(config, new FaceFlowListener() {
            @Override
            public void onProgress(@NonNull FaceFlowProgress progress) {
                renderVerificationProgress(progress, config.getActionTimeoutMillis());
            }
            @Override public void onResult(@NonNull FaceFlowResult result) {
                if (!finishCameraFlow(true)) return;
                String message = result.isPassed() ? getString(R.string.liveness_result_passed)
                        : FaceFlowUi.rejectionMessage(FaceLivenessActivity.this, result.getOutcome());
                if (result.getLivenessScore() != null) message = getString(R.string.liveness_score_format, message, result.getLivenessScore());
                complete(message, result.isPassed() ? RecognitionFlowContract.PASSED : RecognitionFlowContract.REJECTED);
            }
            @Override public void onError(@NonNull HiFaceError error) {
                if (finishCameraFlow()) complete(DemoErrorUi.messageFor(FaceLivenessActivity.this, error), RecognitionFlowContract.ERROR);
            }
        }));
    }

    private void complete(String message, String status) {
        setResult(RESULT_OK, RecognitionFlowContract.result(getString(R.string.recognition_liveness_title), message, status));
        finish();
    }

    private void switchCamera() {
        cameraPreview.pauseAnalysis();
        boolean switched = cameraPreview.switchCamera();
        if (isCameraFlowRunning()) cameraPreview.resumeAnalysis();
        if (!switched) Toast.makeText(getApplicationContext(), R.string.camera_switch_unavailable, Toast.LENGTH_SHORT).show();
    }
}
