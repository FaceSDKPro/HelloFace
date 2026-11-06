package com.hiface.sdk.demo.search.uvc;

import android.graphics.Bitmap;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;
import android.widget.EditText;
import android.widget.ImageView;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.hiface.sdk.demo.R;

/** 一次采样的确认表单；仅预览分配 Bitmap，关闭时释放，保存仍交给页面及共用存储。 */
final class UvcEnrollmentConfirmation {
    interface Listener {
        void save(String faceId, String group);
        void retake();
        void cancel();
    }

    private final AlertDialog dialog;
    private final EditText id, group;

    UvcEnrollmentConfirmation(AppCompatActivity owner, UvcEnrollmentState state, Listener listener) {
        View form = owner.getLayoutInflater().inflate(R.layout.view_uvc_enrollment_confirmation, null, false);
        ImageView photo = form.findViewById(R.id.uvcEnrollPhoto);
        Bitmap bitmap = state.pending.getAlignedFace();
        photo.setImageBitmap(bitmap); // UVC 图像不做前置相机镜像，也不保存图片文件。
        id = form.findViewById(R.id.uvcEnrollId);
        group = form.findViewById(R.id.uvcEnrollGroup);
        id.setText(state.faceId); group.setText(state.group);
        id.setNextFocusForwardId(group.getId());
        TextWatcher draft = new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                state.faceId = id.getText().toString(); state.group = group.getText().toString();
            }
            @Override public void afterTextChanged(Editable s) {}
        };
        id.addTextChangedListener(draft); group.addTextChangedListener(draft);
        dialog = new MaterialAlertDialogBuilder(owner).setTitle(R.string.search_ui_confirm_title).setView(form)
                .setCancelable(false).setNeutralButton(android.R.string.cancel, (d, w) -> listener.cancel())
                .setNegativeButton(R.string.search_recapture, (d, w) -> listener.retake())
                .setPositiveButton(R.string.search_save, null).create();
        dialog.setOnDismissListener(d -> {
            photo.setImageDrawable(null);
            bitmap.recycle();
        });
        dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String value = id.getText().toString().trim();
            if (value.isEmpty()) { id.setError(owner.getString(R.string.enroll_face_id_required)); return; }
            id.setError(null);
            id.setText(value); group.setText(group.getText().toString().trim());
            listener.save(value, group.getText().toString());
        }));
    }

    void show() { dialog.show(); }
    void dismiss() { dialog.dismiss(); }
    boolean isShowing() { return dialog.isShowing(); }

    void setSaving(boolean saving) {
        id.setEnabled(!saving); group.setEnabled(!saving);
        for (int button : new int[]{AlertDialog.BUTTON_POSITIVE, AlertDialog.BUTTON_NEGATIVE, AlertDialog.BUTTON_NEUTRAL})
            dialog.getButton(button).setEnabled(!saving);
    }
}
