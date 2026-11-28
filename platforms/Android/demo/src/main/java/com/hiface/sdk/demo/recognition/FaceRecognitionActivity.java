package com.hiface.sdk.demo.recognition;

import android.app.Dialog;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.drawable.BitmapDrawable;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.widget.CheckBox;
import android.widget.ImageView;
import android.widget.ScrollView;
import android.widget.TextView;
import androidx.activity.result.ActivityResult;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.SwitchCompat;
import androidx.core.content.ContextCompat;
import androidx.core.view.OneShotPreDrawListener;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.ViewModel;
import androidx.lifecycle.ViewModelProvider;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.common.FaceRequest;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.comparison.FacePhotoPicker;
import com.hiface.sdk.demo.liveness.FaceLivenessActivity;
import com.hiface.sdk.demo.storage.FacePhotoStore;
import com.hiface.sdk.demo.ui.DemoErrorUi;
import com.hiface.sdk.demo.ui.DemoWindowInsets;
import com.hiface.sdk.demo.verification.FaceEnrollmentActivity;
import com.hiface.sdk.demo.verification.FaceFeatureStore;
import com.hiface.sdk.demo.verification.FaceVerificationActivity;
import com.hiface.sdk.demo.verification.ReferenceConfirmation;
import com.hiface.sdk.flow.FaceAction;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Configure the next camera request, choose a confirmed reference, and display returned results. */
public final class FaceRecognitionActivity extends AppCompatActivity {
    // Independent drafts for 1:1 verification and standalone liveness.
    private Options verification, liveness;
    private FacePhotoPicker picker;
    // Create the photo SDK on first selection and bind it to this Activity's lifecycle.
    private HiFaceSdk photoSdk;
    // Cancel a pending extraction when this screen stops.
    private FaceRequest photoRequest;
    // The shared confirmation holds the album sample until the user saves or dismisses it.
    private Dialog photoConfirmation;
    private RecyclerView references;
    private TextView referenceHint;
    private FaceReferenceAdapter referenceAdapter;
    private final FaceFeatureStore referenceStore = new FaceFeatureStore();
    private View resultCard;
    private ImageView resultFrame;
    // Keep the XML limits in physical pixels after the view is resized to fit the image.
    private int resultFrameMaxWidth, resultFrameMaxHeight;
    private ResultPreview resultPreview;
    private String resultMessage, resultStatus;
    private final ActivityResultLauncher<Intent> cameraFlow = registerForActivityResult(
            new ActivityResultContracts.StartActivityForResult(), this::onCameraResult);
    private final ActivityResultLauncher<Intent> enrollment = registerForActivityResult(
            new ActivityResultContracts.StartActivityForResult(), ignored -> refreshReferences(true));

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_face_recognition);
        DemoWindowInsets.applyToContent(this);
        findViewById(R.id.recognitionContent).requestFocus();
        findViewById(R.id.backButton).setOnClickListener(view -> finish());
        resultCard = findViewById(R.id.recognitionResult);
        resultFrame = findViewById(R.id.resultFrame);
        resultFrameMaxWidth = resultFrame.getLayoutParams().width;
        resultFrameMaxHeight = resultFrame.getLayoutParams().height;
        resultPreview = new ViewModelProvider(this).get(ResultPreview.class);
        verification = new Options(findViewById(R.id.verificationOptions), false, state, "verification.");
        liveness = new Options(findViewById(R.id.livenessOptions), true, state, "liveness.");
        picker = new FacePhotoPicker(this, FacePhotoPicker.IMAGE_SEARCH_MAX_DIMENSION_PX);
        findViewById(R.id.albumReference).setOnClickListener(view -> pickReference());
        references = findViewById(R.id.referenceList);
        referenceHint = findViewById(R.id.referenceHint);
        references.setLayoutManager(new LinearLayoutManager(this, RecyclerView.HORIZONTAL, false));
        referenceAdapter = new FaceReferenceAdapter(id -> launchCameraFlow(
                new Intent(this, FaceVerificationActivity.class).putExtra(RecognitionFlowContract.FACE_ID, id),
                verification), this::confirmDeleteReference);
        references.setAdapter(referenceAdapter);
        findViewById(R.id.addReference).setOnClickListener(
                view -> enrollment.launch(new Intent(this, FaceEnrollmentActivity.class)));
        findViewById(R.id.startLiveness).setOnClickListener(view -> launchCameraFlow(
                new Intent(this, FaceLivenessActivity.class), liveness));
        if (state != null) {
            resultMessage = state.getString("resultMessage");
            resultStatus = state.getString("resultStatus");
        }
        renderResult();
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshReferences(false);
    }

    // Allow thumbnail reload on confirmed writes, including updates that keep the same Face ID.
    private void refreshReferences(boolean reloadPhotos) {
        if (references == null || isDestroyed()) {
            return;
        }
        List<String> ids = referenceStore.getFaceIds();
        referenceAdapter.update(ids, reloadPhotos);
        references.setVisibility(ids.isEmpty() ? View.GONE : View.VISIBLE);
        referenceHint.setText(defaultReferenceHint());
    }

    private String defaultReferenceHint() {
        return getString(referenceAdapter.getItemCount() == 0
                ? R.string.recognition_no_reference : R.string.recognition_tap_reference);
    }

    // Disable repeat album selection until the picker or extraction resolves.
    private void pickReference() {
        findViewById(R.id.albumReference).setEnabled(false);
        picker.pick(new FacePhotoPicker.Callback() {
            @Override
            public void onPicked(Bitmap photo) {
                try {
                    if (getLifecycle().getCurrentState().isAtLeast(Lifecycle.State.STARTED)) {
                        extractReference(photo);
                    } else {
                        finishPhotoSelection(defaultReferenceHint());
                    }
                } finally {
                    photo.recycle(); // The SDK snapshots the pixels before returning the request.
                }
            }

            @Override
            public void onCanceled() {
                finishPhotoSelection(defaultReferenceHint());
            }

            @Override
            public void onError(Throwable error) {
                finishPhotoSelection(getString(R.string.face_compare_photo_failed));
            }
        });
    }

    /** Stage a single aligned face for confirmation. Saving stays in ReferenceConfirmation. */
    private void extractReference(Bitmap photo) {
        if (photoSdk == null) {
            photoSdk = HiFaceSdk.builder(this).lifecycleOwner(this).build();
        }
        referenceHint.setText(R.string.image_search_processing);
        photoRequest = photoSdk.capture().facesFromBitmap(photo, result -> {
            photoRequest = null;
            if (result.isFailure()) {
                finishPhotoSelection(DemoErrorUi.messageFor(this, result.requireError()));
                return;
            }
            var faces = result.requireValue();
            // Count all detections before inspecting their individual extraction results.
            if (faces.size() != 1) {
                finishPhotoSelection(getString(R.string.enroll_single_photo));
                return;
            }
            var captured = faces.get(0).getCapture();
            if (captured.isFailure()) {
                finishPhotoSelection(DemoErrorUi.messageFor(this, captured.requireError()));
                return;
            }
            finishPhotoSelection(defaultReferenceHint());
            photoConfirmation = ReferenceConfirmation.show(this, captured.requireValue(), false,
                    this::pickReference, () -> refreshReferences(true));
            photoConfirmation.setCancelable(true);
        });
    }

    private void finishPhotoSelection(String message) {
        findViewById(R.id.albumReference).setEnabled(true);
        referenceHint.setText(message);
    }

    @Override
    protected void onStop() {
        if (photoRequest != null) {
            photoRequest.cancel();
            photoRequest = null;
            finishPhotoSelection(defaultReferenceHint());
        }
        super.onStop();
    }

    // Clear the previous result only after the next run's options pass validation.
    private void launchCameraFlow(Intent intent, Options options) {
        List<FaceAction> actions = options.actionsForLaunch();
        if (actions == null) {
            return;
        }
        resultMessage = resultStatus = null;
        resultPreview.bitmap = null;
        renderResult();
        cameraFlow.launch(RecognitionFlowContract.configure(intent, actions, options.silentEnabled()));
    }

    private void onCameraResult(ActivityResult result) {
        Intent data = result.getData();
        if (result.getResultCode() == RESULT_OK && data != null) {
            resultMessage = data.getStringExtra(RecognitionFlowContract.MESSAGE);
            resultStatus = data.getStringExtra(RecognitionFlowContract.STATUS);
            resultPreview.bitmap = RecognitionFlowContract.readPreview(data, resultFrameMaxWidth, resultFrameMaxHeight);
        } else {
            resultMessage = getString(R.string.recognition_canceled);
            resultStatus = RecognitionFlowContract.CANCELED;
            resultPreview.bitmap = null;
        }
        renderResult();
        findViewById(R.id.recognitionContent).requestFocus();
        ScrollView scroll = findViewById(R.id.main);
        // Wait for the image layout and bring the result into view on short screens.
        OneShotPreDrawListener.add(scroll, () -> {
            if (resultCard.isShown()) {
                scroll.smoothScrollTo(0, resultCard.getTop());
            }
        });
    }

    private void confirmDeleteReference(String faceId) {
        new AlertDialog.Builder(this)
                .setTitle(R.string.search_ui_delete_title)
                .setMessage(getString(R.string.search_ui_delete_message, faceId))
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.search_ui_delete_confirm, (dialog, which) -> {
                    FacePhotoStore.execute(() -> {
                        referenceStore.remove(faceId);
                        FacePhotoStore.REFERENCE.remove(getApplicationContext(), faceId);
                        runOnUiThread(() -> refreshReferences(true));
                    });
                })
                .show();
    }

    private void renderResult() {
        Bitmap frame = resultMessage == null ? null : resultPreview.bitmap;
        if (frame != null) {
            // Size the view to the fitted photo so the card padding reaches the visible image edge.
            float scale = Math.min((float) resultFrameMaxWidth / frame.getWidth(),
                    (float) resultFrameMaxHeight / frame.getHeight());
            ViewGroup.LayoutParams size = resultFrame.getLayoutParams();
            size.width = Math.max(1, Math.round(frame.getWidth() * scale));
            size.height = Math.max(1, Math.round(frame.getHeight() * scale));
            resultFrame.setLayoutParams(size);
        }
        resultFrame.setImageDrawable(frame == null ? null : new BitmapDrawable(getResources(), frame));
        resultFrame.setVisibility(frame == null ? View.GONE : View.VISIBLE);
        resultCard.setVisibility(resultMessage == null ? View.GONE : View.VISIBLE);
        if (resultMessage == null) {
            return;
        }
        TextView summary = findViewById(R.id.resultSummary);
        boolean passed = RecognitionFlowContract.PASSED.equals(resultStatus);
        boolean canceled = RecognitionFlowContract.CANCELED.equals(resultStatus);
        summary.setTextColor(ContextCompat.getColor(this, passed ? R.color.content_accent
                : canceled ? R.color.content_text_secondary : R.color.content_error));
        summary.setText(resultMessage);
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        verification.save(state);
        liveness.save(state);
        state.putString("resultMessage", resultMessage);
        state.putString("resultStatus", resultStatus);
        super.onSaveInstanceState(state);
    }

    @Override
    protected void onDestroy() {
        picker.close();
        if (photoConfirmation != null) {
            photoConfirmation.dismiss();
        }
        if (referenceAdapter != null) {
            referenceAdapter.close();
        }
        super.onDestroy();
    }

    /** Hold the decoded preview in memory across Activity recreation. */
    public static final class ResultPreview extends ViewModel {
        private Bitmap bitmap;
    }

    private static final FaceAction[] ACTION_ORDER = {
            FaceAction.BLINK, FaceAction.MOUTH_OPEN, FaceAction.SHAKE_HEAD, FaceAction.NOD_HEAD
    };

    private final class Options {
        final SwitchCompat silent, enabled;
        final CheckBox[] choices;
        final View root;
        final boolean standalone;
        final String statePrefix;

        Options(View root, boolean standalone, Bundle state, String prefix) {
            this.root = root;
            this.standalone = standalone;
            statePrefix = prefix;
            silent = root.findViewById(R.id.silentSwitch);
            enabled = root.findViewById(R.id.actionsSwitch);
            choices = new CheckBox[]{root.findViewById(R.id.blinkChoice), root.findViewById(R.id.mouthChoice),
                    root.findViewById(R.id.shakeChoice), root.findViewById(R.id.nodChoice)};
            if (standalone) {
                silent.setVisibility(View.GONE);
                TextView description = root.findViewById(R.id.silentDescription);
                description.setText(R.string.recognition_standalone_silent_hint);
            }
            if (state != null) {
                silent.setChecked(state.getBoolean(prefix + "silent", true));
                enabled.setChecked(state.getBoolean(prefix + "enabled", enabled.isChecked()));
                for (int i = 0; i < choices.length; i++) {
                    choices[i].setChecked(state.getBoolean(prefix + i, i == 0 || i == 3));
                }
            }
            silent.setOnCheckedChangeListener((button, checked) -> render());
            enabled.setOnCheckedChangeListener((button, checked) -> render());
            for (CheckBox choice : choices) {
                choice.setOnCheckedChangeListener((button, checked) -> render());
            }
            render();
        }

        boolean silentEnabled() {
            return standalone || silent.isChecked();
        }

        // Snapshot the ordered challenge. An enabled but empty challenge blocks launch.
        @Nullable
        List<FaceAction> actionsForLaunch() {
            if (!enabled.isChecked()) {
                return Collections.emptyList();
            }
            List<FaceAction> selected = new ArrayList<>();
            for (int i = 0; i < choices.length; i++) {
                if (choices[i].isChecked()) {
                    selected.add(ACTION_ORDER[i]);
                }
            }
            if (!selected.isEmpty()) {
                return selected;
            }
            root.findViewById(R.id.actionValidation).requestFocus();
            return null;
        }

        void render() {
            boolean actionsEnabled = enabled.isChecked();
            boolean hasSelection = false;
            for (CheckBox choice : choices) {
                hasSelection |= choice.isChecked();
            }
            root.findViewById(R.id.actionChoices).setVisibility(actionsEnabled ? View.VISIBLE : View.GONE);
            root.findViewById(R.id.actionValidation)
                    .setVisibility(actionsEnabled && !hasSelection ? View.VISIBLE : View.GONE);
            TextView hint = root.findViewById(R.id.optionsHint);
            hint.setVisibility(actionsEnabled ? View.GONE : View.VISIBLE);
            if (!actionsEnabled) {
                hint.setText(silentEnabled() ? R.string.recognition_passive_hint : R.string.recognition_identity_hint);
            }
        }

        void save(Bundle state) {
            state.putBoolean(statePrefix + "silent", silent.isChecked());
            state.putBoolean(statePrefix + "enabled", enabled.isChecked());
            for (int i = 0; i < choices.length; i++) {
                state.putBoolean(statePrefix + i, choices[i].isChecked());
            }
        }
    }
}
