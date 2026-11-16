package com.hiface.sdk.demo;

import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.widget.CheckBox;
import android.widget.ScrollView;
import android.widget.TextView;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.widget.SwitchCompat;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.hiface.sdk.demo.liveness.FaceLivenessActivity;
import com.hiface.sdk.demo.recognition.FaceReferenceAdapter;
import com.hiface.sdk.demo.recognition.RecognitionFlowContract;
import com.hiface.sdk.demo.storage.FacePhotoStore;
import com.hiface.sdk.demo.ui.DemoWindowInsets;
import com.hiface.sdk.demo.verification.FaceEnrollmentActivity;
import com.hiface.sdk.demo.verification.FaceFeatureStore;
import com.hiface.sdk.demo.verification.FaceVerificationActivity;
import com.hiface.sdk.flow.FaceAction;
import java.util.ArrayList;
import java.util.List;

/** Configure the next camera request, choose a confirmed reference, and display returned results. */
public final class FaceRecognitionActivity extends AppCompatActivity {
    private Options verification, liveness;
    private RecyclerView references;
    private FaceReferenceAdapter referenceAdapter;
    private String resultTitle, resultMessage, resultStatus, pendingTitle;
    private final ActivityResultLauncher<Intent> cameraFlow = registerForActivityResult(
            new ActivityResultContracts.StartActivityForResult(), result -> {
                Intent data = result.getData();
                if (result.getResultCode() == RESULT_OK && data != null) {
                    resultTitle = data.getStringExtra(RecognitionFlowContract.TITLE);
                    resultMessage = data.getStringExtra(RecognitionFlowContract.MESSAGE);
                    resultStatus = data.getStringExtra(RecognitionFlowContract.STATUS);
                } else {
                    resultTitle = pendingTitle;
                    resultMessage = getString(R.string.recognition_canceled);
                    resultStatus = RecognitionFlowContract.CANCELED;
                }
                renderResult();
                findViewById(R.id.recognitionContent).requestFocus();
                ScrollView scroll = findViewById(R.id.main);
                scroll.post(() -> scroll.fullScroll(View.FOCUS_DOWN));
            });
    private final ActivityResultLauncher<Intent> enrollment = registerForActivityResult(
            new ActivityResultContracts.StartActivityForResult(), ignored -> refreshReferences(true));

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_face_recognition);
        DemoWindowInsets.applyToContent(this);
        findViewById(R.id.recognitionContent).requestFocus();
        findViewById(R.id.backButton).setOnClickListener(view -> finish());
        verification = new Options(findViewById(R.id.verificationOptions), false, state, "verification.");
        liveness = new Options(findViewById(R.id.livenessOptions), true, state, "liveness.");
        references = findViewById(R.id.referenceList);
        references.setLayoutManager(new LinearLayoutManager(this, RecyclerView.HORIZONTAL, false));
        referenceAdapter = new FaceReferenceAdapter(id -> {
            if (!verification.validate()) return;
            pendingTitle = getString(R.string.recognition_verification_title);
            Intent intent = new Intent(this, FaceVerificationActivity.class).putExtra(RecognitionFlowContract.FACE_ID, id);
            launch(RecognitionFlowContract.configure(intent, verification.actions(), verification.silent.isChecked()));
        }, this::confirmDeleteReference);
        references.setAdapter(referenceAdapter);
        findViewById(R.id.addReference).setOnClickListener(view -> enrollment.launch(new Intent(this, FaceEnrollmentActivity.class)));
        findViewById(R.id.startLiveness).setOnClickListener(view -> {
            if (!liveness.validate()) return;
            pendingTitle = getString(R.string.recognition_liveness_title);
            launch(RecognitionFlowContract.configure(new Intent(this, FaceLivenessActivity.class), liveness.actions(), true));
        });
        if (state != null) {
            resultTitle = state.getString("resultTitle"); resultMessage = state.getString("resultMessage");
            resultStatus = state.getString("resultStatus"); pendingTitle = state.getString("pendingTitle");
        }
        renderResult();
    }

    @Override protected void onResume() { super.onResume(); refreshReferences(false); }

    private void refreshReferences(boolean reloadPhotos) {
        if (references == null || isDestroyed()) return;
        List<String> ids = new FaceFeatureStore().getFaceIds();
        referenceAdapter.update(ids, reloadPhotos);
        references.setVisibility(ids.isEmpty() ? View.GONE : View.VISIBLE);
        ((TextView) findViewById(R.id.referenceHint)).setText(ids.isEmpty()
                ? R.string.recognition_no_reference : R.string.recognition_tap_reference);
    }

    private void launch(Intent intent) {
        resultTitle = resultMessage = resultStatus = null;
        renderResult();
        cameraFlow.launch(intent);
    }

    private void confirmDeleteReference(String faceId) {
        new AlertDialog.Builder(this)
                .setTitle(R.string.search_ui_delete_title)
                .setMessage(getString(R.string.search_ui_delete_message, faceId))
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.search_ui_delete_confirm, (dialog, which) -> {
                    new FaceFeatureStore().remove(faceId);
                    FacePhotoStore.execute(() -> FacePhotoStore.REFERENCE.remove(getApplicationContext(), faceId));
                    refreshReferences(true);
                })
                .show();
    }

    private void renderResult() {
        View card = findViewById(R.id.recognitionResult);
        card.setVisibility(resultMessage == null ? View.GONE : View.VISIBLE);
        if (resultMessage == null) return;
        TextView status = findViewById(R.id.resultStatus);
        boolean passed = RecognitionFlowContract.PASSED.equals(resultStatus);
        boolean canceled = RecognitionFlowContract.CANCELED.equals(resultStatus);
        status.setText(passed ? R.string.recognition_passed : canceled ? R.string.recognition_canceled
                : RecognitionFlowContract.ERROR.equals(resultStatus) ? R.string.liveness_result_error : R.string.recognition_rejected);
        status.setTextColor(ContextCompat.getColor(this, passed ? R.color.content_accent
                : canceled ? R.color.content_text_secondary : R.color.content_error));
        ((TextView) findViewById(R.id.resultHeading)).setText(resultTitle);
        ((TextView) findViewById(R.id.resultSummary)).setText(resultMessage);
    }

    @Override protected void onSaveInstanceState(Bundle state) {
        verification.save(state, "verification."); liveness.save(state, "liveness.");
        state.putString("resultTitle", resultTitle); state.putString("resultMessage", resultMessage);
        state.putString("resultStatus", resultStatus); state.putString("pendingTitle", pendingTitle);
        super.onSaveInstanceState(state);
    }

    @Override protected void onDestroy() {
        if (referenceAdapter != null) referenceAdapter.close();
        super.onDestroy();
    }

    private final class Options {
        final SwitchCompat silent, enabled;
        final CheckBox[] choices;
        final View root;
        final boolean standalone;
        final FaceAction[] order = {FaceAction.BLINK, FaceAction.MOUTH_OPEN, FaceAction.SHAKE_HEAD, FaceAction.NOD_HEAD};
        Options(View root, boolean standalone, Bundle state, String prefix) {
            this.root = root; this.standalone = standalone;
            silent = root.findViewById(R.id.silentSwitch); enabled = root.findViewById(R.id.actionsSwitch);
            choices = new CheckBox[]{root.findViewById(R.id.blinkChoice), root.findViewById(R.id.mouthChoice),
                    root.findViewById(R.id.shakeChoice), root.findViewById(R.id.nodChoice)};
            root.findViewById(R.id.silentRow).setVisibility(standalone ? View.GONE : View.VISIBLE);
            if (state != null) {
                silent.setChecked(state.getBoolean(prefix + "silent", true));
                enabled.setChecked(state.getBoolean(prefix + "enabled", false));
                for (int i = 0; i < choices.length; i++) choices[i].setChecked(state.getBoolean(prefix + i, i == 0 || i == 3));
            }
            silent.setOnCheckedChangeListener((button, checked) -> render());
            enabled.setOnCheckedChangeListener((button, checked) -> render());
            for (CheckBox choice : choices) choice.setOnCheckedChangeListener((button, checked) -> render());
            render();
        }
        List<FaceAction> actions() {
            List<FaceAction> selected = new ArrayList<>();
            if (enabled.isChecked()) for (int i = 0; i < choices.length; i++) if (choices[i].isChecked()) selected.add(order[i]);
            return selected;
        }
        boolean validate() {
            if (!enabled.isChecked()) return true;
            for (CheckBox choice : choices) if (choice.isChecked()) return true;
            TextView validation = root.findViewById(R.id.actionValidation);
            validation.setText(R.string.recognition_choose_action);
            validation.setTextColor(ContextCompat.getColor(FaceRecognitionActivity.this, R.color.content_error));
            validation.requestFocus();
            return false;
        }
        void render() {
            root.findViewById(R.id.actionChoices).setVisibility(enabled.isChecked() ? View.VISIBLE : View.GONE);
            TextView validation = root.findViewById(R.id.actionValidation);
            validation.setText(R.string.recognition_action_order);
            validation.setTextColor(ContextCompat.getColor(FaceRecognitionActivity.this, R.color.content_text_secondary));
            ((TextView) root.findViewById(R.id.optionsHint)).setText(enabled.isChecked()
                    ? R.string.recognition_combined_hint : standalone || silent.isChecked()
                    ? R.string.recognition_passive_hint : R.string.recognition_identity_hint);
        }
        void save(Bundle state, String prefix) {
            state.putBoolean(prefix + "silent", silent.isChecked()); state.putBoolean(prefix + "enabled", enabled.isChecked());
            for (int i = 0; i < choices.length; i++) state.putBoolean(prefix + i, choices[i].isChecked());
        }
    }
}
