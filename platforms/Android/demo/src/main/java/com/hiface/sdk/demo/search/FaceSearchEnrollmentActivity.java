package com.hiface.sdk.demo.search;

import android.content.Context;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.inputmethod.EditorInfo;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.Toast;

import androidx.appcompat.app.AlertDialog;
import androidx.lifecycle.Lifecycle;

import com.hiface.sdk.capture.FaceCaptureListener;
import com.hiface.sdk.capture.FaceCaptureResult;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.camera.CameraFlowActivity;
import com.hiface.sdk.demo.ui.CaptureStatusUi;
import com.hiface.sdk.demo.ui.DemoErrorUi;
import com.hiface.sdk.flow.FaceFlowProgress;

/** 录入接入示例：稳定采集 → 预览与填写 ID/分组 → 保存特征。 */
public final class FaceSearchEnrollmentActivity extends CameraFlowActivity {
    private FaceSearchStore store;
    private FaceSearchStore.Request<?> saveRequest;
    private AlertDialog captureError;
    private AlertDialog confirmation;
    private AlertDialog overwriteDialog;
    private FaceCaptureResult pending;
    private boolean saving;

    /** 创建页面级采集 SDK 与人脸库入口，相机帧仍通过统一 processFrame 入口送入。 */
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        initializeCameraSdk();
    }

    /** 页面可见时启动一轮稳定采集；成功后暂停分析，等待用户确认入库。 */
    @Override
    protected void startCameraFlow() {
        if (!canStartCameraFlow() || pending != null || captureError != null) {
            return;
        }
        startCameraFlowRequest(() -> hiFaceSdk.capture().startCameraCapture(new FaceCaptureListener() {
            @Override
            public void onProgress(FaceFlowProgress progress) {
                if (isCameraFlowRunning()) CaptureStatusUi.apply(captureOverlay, progress.getStage());
            }

            @Override
            public void onResult(FaceCaptureResult result) {
                if (!finishCameraFlow()) return;
                pending = result;
                showConfirmation(result);
            }

            @Override
            public void onError(HiFaceError error) {
                if (!finishCameraFlow()) return;
                AlertDialog.Builder builder = SearchUi.dialog(FaceSearchEnrollmentActivity.this)
                        .setMessage(SearchUi.errorText(error))
                        .setNegativeButton(R.string.verification_close, (d, which) -> finish())
                        .setCancelable(false);
                if (DemoErrorUi.isRetryable(error)) {
                    builder.setPositiveButton(R.string.verification_retry, (d, which) -> {
                        captureError = null;
                        startCameraFlow();
                    });
                }
                captureError = builder.show();
            }
        }));
    }

    /** 展示本次采集预览并收集 ID、分组；重拍丢弃待保存结果，保存前校验非空 ID。 */
    private void showConfirmation(FaceCaptureResult capture) {
        Context themed = SearchUi.theme(this);
        LinearLayout form = SearchUi.form(themed);
        form.addView(SearchUi.text(themed, R.string.search_ui_confirm_hint, 12, false));
        Bitmap bitmap = capture.getAlignedFace();
        ImageView image = addPreview(form, bitmap);
        SearchUi.Input id = SearchUi.field(form, R.string.search_ui_id_label, "",
                R.string.search_ui_id_help, InputType.TYPE_CLASS_TEXT);
        SearchUi.section(form, R.string.search_ui_scope_section);
        form.addView(SearchUi.text(themed, R.string.search_ui_enroll_scope_help, 12, false));
        SearchUi.Input group = SearchUi.field(form, R.string.search_ui_group_label, "",
                0, InputType.TYPE_CLASS_TEXT);
        id.edit.setNextFocusForwardId(group.edit.getId());
        group.edit.setImeOptions(EditorInfo.IME_ACTION_DONE);
        SearchUi.FormScrollView scroll = SearchUi.scroll(form);

        AlertDialog dialog = SearchUi.formDialog(this)
                .setTitle(R.string.search_ui_confirm_title)
                .setView(scroll)
                .setCancelable(false)
                .setNegativeButton(R.string.search_recapture, (d, which) -> {
                    pending = null;
                    startCameraFlow();
                })
                .setPositiveButton(R.string.search_save, null)
                .create();
        confirmation = dialog;
        dialog.setOnDismissListener(d -> {
            // getAlignedFace() 返回本次预览独占的 Bitmap，关闭弹窗时释放。
            image.setImageDrawable(null);
            bitmap.recycle();
            if (confirmation == dialog) {
                confirmation = null;
            }
        });
        dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener(v -> {
                    String faceId = id.value();
                    if (faceId.isEmpty()) {
                        id.error(R.string.enroll_face_id_required);
                        return;
                    }
                    id.set(faceId);
                    group.set(group.value());
                    save(dialog, capture, faceId, group.value(), false);
                }));
        SearchUi.showFormDialog(dialog, scroll);
    }

    /** 添加对齐人脸预览；前摄仅在 ImageView 上镜像，不修改 SDK 返回的特征或位图像素。 */
    private ImageView addPreview(LinearLayout form, Bitmap bitmap) {
        ImageView image = new ImageView(form.getContext());
        image.setImageBitmap(bitmap);
        image.setScaleType(ImageView.ScaleType.CENTER_CROP);
        image.setBackgroundResource(R.drawable.bg_search_camera);
        image.setClipToOutline(true);
        image.setContentDescription(getString(R.string.search_ui_capture_preview));
        image.setScaleX(cameraPreview.isFrontCamera() ? -1 : 1);
        LinearLayout.LayoutParams photo = new LinearLayout.LayoutParams(
                SearchUi.dp(this, 144), SearchUi.dp(this, 144));
        photo.gravity = Gravity.CENTER_HORIZONTAL;
        photo.topMargin = SearchUi.dp(this, 16);
        photo.bottomMargin = SearchUi.dp(this, 8);
        form.addView(image, photo);
        return image;
    }

    /** 异步保存采集特征并防止重复提交；重复 ID 转入覆盖确认，成功后关闭录入页。 */
    private void save(AlertDialog dialog, FaceCaptureResult capture,
            String faceId, String group, boolean overwriteConfirmed) {
        if (saving) {
            return;
        }
        saving = true;
        setConfirmationEnabled(dialog, false);
        saveRequest = store.save(faceId, capture.getFeature(), group, overwriteConfirmed, saved -> {
            saveRequest = null;
            saving = false;
            if (!getLifecycle().getCurrentState().isAtLeast(Lifecycle.State.STARTED)
                    || !dialog.isShowing()) {
                return;
            }
            setConfirmationEnabled(dialog, true);
            if (saved.isSuccess()) {
                pending = null;
                dialog.dismiss();
                Toast.makeText(this, R.string.search_saved, Toast.LENGTH_SHORT).show();
                setResult(RESULT_OK);
                finish();
            } else if (saved.requireError().getCode() == HiFaceErrorCode.ALREADY_EXISTS) {
                showOverwriteConfirmation(dialog, capture, faceId, group);
            } else {
                showError(saved.requireError());
            }
        });
    }

    /** 重复 ID 必须再次确认，确认后才调用统一的 saveFeature 覆盖已有记录。 */
    private void showOverwriteConfirmation(AlertDialog dialog, FaceCaptureResult capture,
            String faceId, String group) {
        if (overwriteDialog != null) {
            overwriteDialog.dismiss();
        }
        overwriteDialog = SearchUi.dialog(this)
                .setTitle(R.string.search_exists)
                .setMessage(getString(R.string.search_overwrite_message, faceId))
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.search_overwrite,
                        (d, which) -> save(dialog, capture, faceId, group, true))
                .show();
    }

    /** 保存期间禁用弹窗的保存与重拍按钮，防止重复操作。 */
    private void setConfirmationEnabled(AlertDialog dialog, boolean enabled) {
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(enabled);
        dialog.getButton(AlertDialog.BUTTON_NEGATIVE).setEnabled(enabled);
    }

    /** 把 SDK 技术错误映射成面向用户的提示，保留当前页面供用户处理。 */
    private void showError(HiFaceError error) {
        Toast.makeText(this, SearchUi.errorText(error), Toast.LENGTH_LONG).show();
    }

    /** 返回页面时重新打开人脸库，采集由相机首帧通知启动。 */
    @Override
    protected void onStart() {
        super.onStart();
        if (store == null) store = new FaceSearchStore(this);
    }

    /** 页面不可见时停止分析并取消当前采集请求，待确认结果继续保留。 */
    @Override
    protected void onStop() {
        super.onStop();
        if (saveRequest != null) {
            saveRequest.cancel();
            saveRequest = null;
            saving = false;
            if (confirmation != null) setConfirmationEnabled(confirmation, true);
        }
        // 已提交的 SQL 自然结束；后台关闭本页连接，恢复后再按需开库。
        if (store != null) {
            store.close();
            store = null;
        }
    }

    /** 关闭页面弹窗及其预览位图；请求和人脸库已在 onStop 清理，SDK 自动释放。 */
    @Override
    protected void onDestroy() {
        if (captureError != null) captureError.dismiss();
        if (overwriteDialog != null) {
            overwriteDialog.dismiss();
        }
        if (confirmation != null) {
            confirmation.dismiss();
        }
        pending = null;
        super.onDestroy();
    }
}
