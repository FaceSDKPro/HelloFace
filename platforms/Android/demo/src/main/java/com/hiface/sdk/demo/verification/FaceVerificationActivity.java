package com.hiface.sdk.demo.verification;

import android.content.Intent;
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

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        faceId = getIntent().getStringExtra(RecognitionFlowContract.FACE_ID);
        String feature = faceId == null ? null : new FaceFeatureStore().getFeature(faceId);
        if (feature == null || feature.trim().isEmpty()) {
            completeError(getString(R.string.verification_feature_missing));
            return;
        }
        try {
            config = FaceVerificationConfig.builder().referenceFeature(feature)
                    .threshold(FaceVerificationConfig.DEFAULT_THRESHOLD)
                    .actions(RecognitionFlowContract.actions(getIntent()))
                    .enableSilentLiveness(getIntent().getBooleanExtra(RecognitionFlowContract.SILENT, true))
                    .allowMultipleFaces(true)
                    .build();
        } catch (IllegalArgumentException error) {
            completeError(getString(R.string.recognition_invalid_options));
            return;
        }
        preparePromptSpeech();
        initializeCameraSdk();
        startCameraFlow();
    }

    @Override
    protected void startCameraFlow() {
        if (config == null) {
            return;
        }
        startCameraFlowRequest(() -> hiFaceSdk.verification().startCameraVerification(config, new FaceFlowListener() {
            @Override
            public void onProgress(@NonNull FaceFlowProgress progress) {
                renderVerificationProgress(progress, config.getActionTimeoutMillis());
            }

            @Override
            public void onResult(@NonNull FaceFlowResult result) {
                if (!finishCameraFlow(true)) {
                    return;
                }
                complete(RecognitionFlowContract.result(formatResult(result), result));
            }

            @Override
            public void onError(@NonNull HiFaceError error) {
                if (finishCameraFlow()) {
                    completeError(DemoErrorUi.messageFor(FaceVerificationActivity.this, error));
                }
            }
        }));
    }

    // Only a completed comparison has an identity outcome and may have a similarity score.
    private String formatResult(FaceFlowResult result) {
        String message;
        switch (result.getOutcome()) {
            case PASSED:
            case NOT_MATCHED:
                Float similarity = result.getSimilarity();
                String score = similarity == null ? "—" : String.format(Locale.getDefault(), "%.2f%%",
                        similarity * 100f);
                message = getString(result.isPassed() ? R.string.verification_match : R.string.verification_mismatch,
                        faceId, score);
                break;
            default:
                message = faceId + "\n" + FaceFlowUi.rejectionMessage(this, result.getOutcome());
                break;
        }
        Float livenessScore = result.getLivenessScore();
        return livenessScore == null ? message : getString(R.string.liveness_score_format, message, livenessScore);
    }

    private void completeError(String message) {
        complete(RecognitionFlowContract.result(message, RecognitionFlowContract.ERROR));
    }

    private void complete(Intent data) {
        setResult(RESULT_OK, data);
        finish();
    }
}
