package com.hiface.sdk.demo.search.uvc;

import android.hardware.usb.UsbDevice;
import android.os.Bundle;
import android.view.View;
import android.widget.ArrayAdapter;
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
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/** 双目设备设置表单；只管理选择和校验，不持有相机或搜索会话。 */
final class UvcCameraSettings {
    private static final int MAX_PAIR_SKEW_MS = 50, MAX_FRAME_AGE_MS = 150;
    private static final String DEFAULT_IR_THRESHOLD = "0.50";

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
    private final List<UsbDevice> devices = new ArrayList<>();
    private final Spinner rgbDevice, irDevice, rgbRotation, irRotation;
    private final EditText threshold;
    private final CheckBox debug;
    private AlertDialog dialog;
    private int validationMessage;

    UvcCameraSettings(AppCompatActivity owner, Runnable refresh, Runnable debugChanged) {
        this.owner = owner;
        form = owner.getLayoutInflater().inflate(R.layout.view_uvc_search_settings, null, false);
        rgbDevice = form.findViewById(R.id.uvcRgbDevice);
        irDevice = form.findViewById(R.id.uvcIrDevice);
        rgbRotation = form.findViewById(R.id.uvcRgbRotation);
        irRotation = form.findViewById(R.id.uvcIrRotation);
        threshold = form.findViewById(R.id.uvcThreshold);
        debug = form.findViewById(R.id.uvcDebug);
        threshold.setText(DEFAULT_IR_THRESHOLD);
        for (Spinner spinner : new Spinner[]{rgbRotation, irRotation})
            choices(spinner, Arrays.asList("0°", "90°", "180°", "270°"), 0);
        form.findViewById(R.id.uvcRefresh).setOnClickListener(v -> refresh.run());
        debug.setOnCheckedChangeListener((button, checked) -> debugChanged.run());
    }

    UsbDevice selectedRgbDevice() {
        int index = rgbDevice.getSelectedItemPosition() - 1;
        return index >= 0 && index < devices.size() ? devices.get(index) : null;
    }

    int rgbRotationDegrees() { return Math.max(0, rgbRotation.getSelectedItemPosition()) * 90; }

    boolean debugEnabled() { return debug.isChecked(); }
    int validationMessage() { return validationMessage; }

    int refreshDevices() {
        devices.clear();
        try {
            devices.addAll(DualCameraSession.devices(owner));
            List<String> names = new ArrayList<>();
            names.add(owner.getString(R.string.uvc_search_select_camera));
            int rgb = 0, ir = 0;
            for (int i = 0; i < devices.size(); i++) {
                UsbDevice device = devices.get(i);
                String name = device.getProductName();
                names.add(String.format(Locale.ROOT, "%s (%04X:%04X)",
                        name == null ? device.getDeviceName() : name, device.getVendorId(), device.getProductId()));
                // 角色名称必须唯一；名称缺失或有歧义时由用户选择。
                String role = name == null ? "" : name.toUpperCase(Locale.ROOT);
                if (role.contains("RGB")) rgb = rgb == 0 ? i + 1 : -1;
                if (role.contains("NIR") || role.contains(" IR")) ir = ir == 0 ? i + 1 : -1;
            }
            choices(rgbDevice, names, Math.max(0, rgb));
            choices(irDevice, names, Math.max(0, ir));
            return setupHint();
        } catch (RuntimeException error) {
            // 枚举失败后同时清空标签与设备，避免旧下标指向另一台设备。
            devices.clear();
            List<String> empty = Collections.singletonList(owner.getString(R.string.uvc_search_select_camera));
            choices(rgbDevice, empty, 0);
            choices(irDevice, empty, 0);
            throw error;
        }
    }

    int setupHint() {
        if (devices.size() < 2) return R.string.uvc_search_connect_cameras;
        int rgb = rgbDevice.getSelectedItemPosition(), ir = irDevice.getSelectedItemPosition();
        if (rgb < 1 || ir < 1 || rgb > devices.size() || ir > devices.size())
            return R.string.uvc_search_choose_cameras;
        return rgb == ir ? R.string.uvc_search_choose_distinct : R.string.uvc_search_ready;
    }

    /** 校验失败保留表单并定位错误；成功后才允许 Activity 打开两路摄像头。 */
    Selection read() {
        validationMessage = setupHint();
        if (validationMessage != R.string.uvc_search_ready) return null;
        int rgb = rgbDevice.getSelectedItemPosition() - 1, ir = irDevice.getSelectedItemPosition() - 1;
        final InfraredSearchConfig infrared;
        try {
            // 仅为开发起点；部署时应使用目标模组标定后的映射、IoU 和 IR 阈值。
            infrared = new InfraredSearchConfig(Float.parseFloat(threshold.getText().toString()),
                    new float[]{1,0,0,0,1,0,0,0,1}, .25f, 80, MAX_PAIR_SKEW_MS, MAX_FRAME_AGE_MS);
        } catch (IllegalArgumentException error) {
            validationMessage = R.string.uvc_search_threshold_invalid;
            threshold.setError(owner.getString(validationMessage));
            return null;
        }
        threshold.setError(null);
        DualCameraConfig config = DualCameraConfig.defaults()
                .withPairingLimits(MAX_PAIR_SKEW_MS, MAX_FRAME_AGE_MS, 30)
                .withRotations(rgbRotation.getSelectedItemPosition() * 90, irRotation.getSelectedItemPosition() * 90);
        return new Selection(devices.get(rgb), devices.get(ir), config, infrared);
    }

    void show(Runnable done) {
        if (dialog == null) dialog = new MaterialAlertDialogBuilder(owner)
                .setTitle(R.string.uvc_search_settings).setView(form)
                .setPositiveButton(R.string.uvc_search_done, (d, w) -> done.run()).create();
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
        threshold.setText(saved.getString("irThreshold", DEFAULT_IR_THRESHOLD));
        debug.setChecked(saved.getBoolean("debug"));
    }

    void save(Bundle out) {
        // 不保存 USB 枚举下标；页面重建时重新枚举并确认角色。
        out.putInt("rgbRotation", rgbRotation.getSelectedItemPosition());
        out.putInt("irRotation", irRotation.getSelectedItemPosition());
        out.putString("irThreshold", threshold.getText().toString());
        out.putBoolean("debug", debug.isChecked());
    }

    private void choices(Spinner spinner, List<String> names, int selected) {
        spinner.setAdapter(new ArrayAdapter<>(owner, android.R.layout.simple_spinner_dropdown_item, names));
        spinner.setSelection(selected);
    }
}
