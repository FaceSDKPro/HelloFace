package com.hiface.sdk.demo.verification;

import android.os.Bundle;
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
import com.hiface.sdk.verification.FaceVerificationConfig;
import java.util.Locale;

/** Run the selected reference/options once, then return the result to the recognition page. */
public final class FaceVerificationActivity extends CameraFlowActivity {
    // Display identity loaded from the Demo's 1:1 store; the SDK receives its feature in config.
    private String faceId;
    // Snapshot the selected reference and options for this camera run.
    private FaceVerificationConfig config;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        faceId = getIntent().getStringExtra(RecognitionFlowContract.FACE_ID);
        String feature = faceId == null ? null : new FaceFeatureStore().getFeature(faceId);
        if (feature == null || feature.trim().isEmpty()) {
            complete(getString(R.string.verification_feature_missing), RecognitionFlowContract.ERROR);
            return;
        }
        try {
            config = FaceVerificationConfig.builder().referenceFeature(feature)
                    .threshold(FaceVerificationConfig.DEFAULT_THRESHOLD)
                    .actions(RecognitionFlowContract.actions(getIntent()))
                    .enableSilentLiveness(getIntent().getBooleanExtra(RecognitionFlowContract.SILENT, true))
                    .allowMultipleFaces(true).build();
        } catch (IllegalArgumentException error) {
            complete(getString(R.string.recognition_invalid_options), RecognitionFlowContract.ERROR);
            return;
        }
        initializeCameraSdk();
        startCameraFlow();
    }

    @Override protected void startCameraFlow() {
        if (config == null) return;
        startCameraFlowRequest(() -> hiFaceSdk.verification().startCameraVerification(config, new FaceFlowListener() {
            @Override public void onProgress(@NonNull FaceFlowProgress progress) {
                if (isCameraFlowRunning()) FaceFlowUi.renderVerifyProgress(captureOverlay, progress, config.getActionTimeoutMillis());
            }
            @Override public void onResult(@NonNull FaceFlowResult result) {
                if (!finishCameraFlow()) return;
                String message;
                switch (result.getOutcome()) {
                    case PASSED:
                    case NOT_MATCHED:
                        Float similarity = result.getSimilarity();
                        message = getString(result.isPassed() ? R.string.verification_match : R.string.verification_mismatch,
                                faceId, similarity == null ? "—" : String.format(Locale.getDefault(), "%.2f%%", similarity * 100f));
                        break;
                    default:
                        message = faceId + "\n" + FaceFlowUi.rejectionMessage(FaceVerificationActivity.this, result.getOutcome());
                        break;
                }
                if (result.getLivenessScore() != null) message = getString(R.string.liveness_score_format, message, result.getLivenessScore());
                complete(message, result.isPassed() ? RecognitionFlowContract.PASSED : RecognitionFlowContract.REJECTED);
            }
            @Override public void onError(@NonNull HiFaceError error) {
                if (finishCameraFlow()) complete(DemoErrorUi.messageFor(FaceVerificationActivity.this, error), RecognitionFlowContract.ERROR);
            }
        }));
    }

    // Return display text and outcome to the recognition page, which owns the result card.
    private void complete(String message, String status) {
        setResult(RESULT_OK, RecognitionFlowContract.result(getString(R.string.recognition_verification_title), message, status));
        finish();
    }
}
