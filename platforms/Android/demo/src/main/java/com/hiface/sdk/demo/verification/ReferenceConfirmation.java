package com.hiface.sdk.demo.verification;

import android.app.Dialog;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;

import com.hiface.sdk.capture.FaceCaptureResult;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.storage.FacePhotoStore;

/** Both enrollment sources save only the aligned crop and HF1 after explicit confirmation. */
public final class ReferenceConfirmation {
    private ReferenceConfirmation() {}

    /**
     * After confirmation, save the feature and one crop in App-private no-backup storage.
     *
     * 确认后保存特征和一张私有裁剪图，不保存完整相机画面。
     */
    public static Dialog show(
            AppCompatActivity host,
            @NonNull FaceCaptureResult capture,
            boolean mirrorForDisplay, Runnable retry, Runnable onSaved
    ) {
        // This dialog owns the display copy; FaceCaptureResult retains the data used by the save worker.
        Bitmap preview = capture.getAlignedFace();
        Dialog dialog = new Dialog(host);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setContentView(R.layout.dialog_face_enrollment);
        dialog.setCancelable(false);
        ImageView imageView = dialog.findViewById(R.id.capturedFaceImage);
        EditText faceIdInput = dialog.findViewById(R.id.faceIdInput);
        View retryButton = dialog.findViewById(R.id.retryButton);
        View confirmButton = dialog.findViewById(R.id.confirmButton);
        imageView.setClipToOutline(true);
        imageView.setScaleX(mirrorForDisplay ? -1f : 1f);
        imageView.setImageBitmap(preview);
        dialog.setOnDismissListener(ignored -> {
            retryButton.setOnClickListener(null);
            confirmButton.setOnClickListener(null);
            imageView.setImageDrawable(null);
            preview.recycle();
        });

        retryButton.setOnClickListener(v -> {
            dialog.dismiss();
            retry.run();
        });
        confirmButton.setOnClickListener(v -> {
            String faceId = faceIdInput.getText().toString().trim();
            if (faceId.isEmpty()) {
                faceIdInput.setError(host.getString(R.string.enroll_face_id_required));
                return;
            }
            confirmButton.setEnabled(false);
            retryButton.setEnabled(false);
            // Persist on the shared photo worker, then touch dialog/views only on the main thread.
            FacePhotoStore.execute(() -> {
                boolean saved = new FaceFeatureStore().save(faceId, capture.getFeature());
                // The feature is authoritative. A missing portrait still leaves a usable reference.
                if (saved) FacePhotoStore.REFERENCE.save(host.getApplicationContext(), faceId, capture);
                host.runOnUiThread(() -> {
                    if (host.isDestroyed()) return;
                    if (!saved) {
                        if (!dialog.isShowing()) return;
                        confirmButton.setEnabled(true);
                        retryButton.setEnabled(true);
                        Toast.makeText(host, R.string.enroll_save_failed, Toast.LENGTH_SHORT).show();
                        return;
                    }
                    Toast.makeText(host, R.string.enroll_capture_complete, Toast.LENGTH_SHORT).show();
                    dialog.dismiss();
                    onSaved.run();
                });
            });
        });

        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
            window.setDimAmount(0.62f);
        }
        dialog.show();
        if (window != null) {
            window.setLayout(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT);
        }
        return dialog;
    }
}
