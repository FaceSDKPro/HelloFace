package com.hiface.sdk.demo.search.uvc;

import android.hardware.usb.UsbDevice;
import android.os.Bundle;
import android.view.View;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.Spinner;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import com.facesdkpro.uvccamera.DualCameraConfig;
import com.facesdkpro.uvccamera.DualCameraSession;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.search.InfraredSearchConfig;

/** 双目设备设置表单；只管理选择和校验，不持有相机或搜索会话。 */
final class UvcCameraSettings {
    private static final int MAX_PAIR_SKEW_MS = 50, MAX_FRAME_AGE_MS = 150;
    private static final String DEFAULT_IR_THRESHOLD = "0.70";

    /** 一次启动使用同一份已校验参数，USB 角色不能从枚举次序或旧下标推断。 */
    static final class Selection {
        final UsbDevice rgb, ir;
        final DualCameraConfig config;
        final InfraredSearchConfig infrared;

        Selection(UsbDevice rgb, UsbDevice ir, DualCameraConfig config, InfraredSearchConfig infrared) {
            this.rgb = rgb;
            this.ir = ir;
            this.config = config;
            this.infrared = infrared;
        }
    }

    private final AppCompatActivity owner;
    private final View form;
    private final UvcCameraChoices cameras;
    private final Spinner rgbDevice, irDevice, rgbRotation, irRotation;
    private final EditText threshold;
    private final CheckBox debug;
    private AlertDialog dialog;
    private int validationMessage;

    UvcCameraSettings(AppCompatActivity owner, Runnable refresh, Runnable debugChanged) {
        this.owner = owner;
        cameras = new UvcCameraChoices(owner);
        form = owner.getLayoutInflater().inflate(R.layout.view_uvc_search_settings, null, false);
        rgbDevice = form.findViewById(R.id.uvcRgbDevice);
        irDevice = form.findViewById(R.id.uvcIrDevice);
        rgbRotation = form.findViewById(R.id.uvcRgbRotation);
        irRotation = form.findViewById(R.id.uvcIrRotation);
        threshold = form.findViewById(R.id.uvcThreshold);
        debug = form.findViewById(R.id.uvcDebug);
        threshold.setText(DEFAULT_IR_THRESHOLD);
        UvcCameraChoices.bindRotation(rgbRotation, 0);
        UvcCameraChoices.bindRotation(irRotation, 0);
        form.findViewById(R.id.uvcRefresh).setOnClickListener(v -> refresh.run());
        debug.setOnCheckedChangeListener((button, checked) -> debugChanged.run());
    }

    UsbDevice selectedRgbDevice() { return cameras.selected(rgbDevice); }
    int rgbRotationDegrees() { return UvcCameraChoices.rotationDegrees(rgbRotation); }

    boolean debugEnabled() { return debug.isChecked(); }
    int validationMessage() { return validationMessage; }

    int refreshDevices() {
        try {
            cameras.refresh();
            cameras.bindDevices(rgbDevice, cameras.suggestedPosition(DualCameraSession.Role.RGB));
            cameras.bindDevices(irDevice, cameras.suggestedPosition(DualCameraSession.Role.IR));
            return setupHint();
        } catch (RuntimeException error) {
            cameras.clear();
            cameras.bindDevices(rgbDevice, 0);
            cameras.bindDevices(irDevice, 0);
            throw error;
        }
    }

    int setupHint() {
        if (cameras.size() < 2) return R.string.uvc_search_connect_cameras;
        UsbDevice rgb = selectedRgbDevice(), ir = cameras.selected(irDevice);
        if (rgb == null || ir == null) return R.string.uvc_search_choose_cameras;
        return rgb.equals(ir) ? R.string.uvc_search_choose_distinct : R.string.uvc_search_ready;
    }

    /** 校验失败保留表单并定位错误；成功后才允许 Activity 打开两路摄像头。 */
    Selection read() {
        validationMessage = setupHint();
        if (validationMessage != R.string.uvc_search_ready) return null;
        Float value = validateThreshold();
        if (value == null) {
            validationMessage = R.string.uvc_search_threshold_invalid;
            return null;
        }
        // UVC 配帧和 SDK 复核共用 50/150 ms 门槛；映射与 IoU 需按目标模组标定。
        InfraredSearchConfig infrared = new InfraredSearchConfig(value,
                new float[]{1,0,0,0,1,0,0,0,1}, .25f, 80, MAX_PAIR_SKEW_MS, MAX_FRAME_AGE_MS);
        DualCameraConfig config = DualCameraConfig.defaults()
                .withPairingLimits(MAX_PAIR_SKEW_MS, MAX_FRAME_AGE_MS, 30)
                .withRotations(rgbRotationDegrees(), UvcCameraChoices.rotationDegrees(irRotation));
        return new Selection(selectedRgbDevice(), cameras.selected(irDevice), config, infrared);
    }

    private static Float parseThreshold(String text) {
        try {
            double value = Double.parseDouble(text);
            if (value >= .60 && value <= .80) return (float) value;
        } catch (NumberFormatException ignored) { /* Keep the draft open for correction. */ }
        return null;
    }

    private Float validateThreshold() {
        Float value = parseThreshold(threshold.getText().toString());
        threshold.setError(value == null ? owner.getString(R.string.uvc_search_threshold_invalid) : null);
        return value;
    }

    void show(Runnable done) {
        if (dialog == null) {
            dialog = new MaterialAlertDialogBuilder(owner).setTitle(R.string.uvc_search_settings).setView(form)
                    .setPositiveButton(R.string.uvc_search_done, null).create();
            dialog.setOnShowListener(ignored -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(view -> {
                if (validateThreshold() == null) return;
                dialog.dismiss();
                done.run();
            }));
        }
        dialog.show();
    }

    void dismiss() { if (dialog != null) dialog.dismiss(); }

    void setEditable(boolean editable) {
        form.findViewById(R.id.uvcRefresh).setEnabled(editable);
        debug.setEnabled(editable);
    }

    void restore(Bundle saved) {
        if (saved == null) return;
        rgbRotation.setSelection(saved.getInt("rgbRotation"));
        irRotation.setSelection(saved.getInt("irRotation"));
        String restored = saved.getString("irThreshold", DEFAULT_IR_THRESHOLD);
        threshold.setText(parseThreshold(restored) == null ? DEFAULT_IR_THRESHOLD : restored);
        debug.setChecked(saved.getBoolean("debug"));
    }

    void save(Bundle out) {
        // 不保存 USB 枚举下标；页面重建时重新枚举并确认角色。
        out.putInt("rgbRotation", rgbRotation.getSelectedItemPosition());
        out.putInt("irRotation", irRotation.getSelectedItemPosition());
        out.putString("irThreshold", threshold.getText().toString());
        out.putBoolean("debug", debug.isChecked());
    }

}
