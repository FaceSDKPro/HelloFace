package com.hiface.sdk.demo.search.uvc;

import android.hardware.usb.UsbDevice;
import android.os.Bundle;
import android.view.View;
import android.widget.Spinner;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import com.facesdkpro.uvccamera.DualCameraSession;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.hiface.sdk.demo.R;
import java.util.List;

/** 录入只选 RGB UVC。跨页面/旋转以设备地址及 VID/PID 重新匹配，不保存枚举下标。 */
final class UvcEnrollmentCameraSettings {
    private static final String DEVICE = "enrollUvcDevice", VENDOR = "enrollUvcVendor", PRODUCT = "enrollUvcProduct", ROTATION = "enrollUvcRotation";
    private final AppCompatActivity owner;
    private final View form;
    private final Spinner device, rotation;
    private final UvcCameraChoices cameras;
    private final Bundle desired;
    private AlertDialog dialog;

    UvcEnrollmentCameraSettings(AppCompatActivity owner, Bundle saved, Bundle source) {
        this.owner = owner;
        cameras = new UvcCameraChoices(owner);
        desired = saved != null ? new Bundle(saved) : source == null ? new Bundle() : new Bundle(source);
        form = owner.getLayoutInflater().inflate(R.layout.view_uvc_enrollment_settings, null, false);
        device = form.findViewById(R.id.uvcEnrollDevice);
        rotation = form.findViewById(R.id.uvcEnrollRotation);
        UvcCameraChoices.bindRotation(rotation, desired.getInt(ROTATION));
        form.findViewById(R.id.uvcEnrollRefresh).setOnClickListener(v -> refresh());
    }

    static void putChoice(Bundle out, UsbDevice device, int rotation) {
        if (device != null) {
            out.putString(DEVICE, device.getDeviceName());
            out.putInt(VENDOR, device.getVendorId());
            out.putInt(PRODUCT, device.getProductId());
        }
        out.putInt(ROTATION, rotation);
    }

    void refresh() {
        putChoice(desired, selected(), rotation());
        int selection;
        try {
            List<UsbDevice> devices = cameras.refresh();
            // 指定设备拔出时保留原身份，重新连接前显示为未选择。
            selection = desired.containsKey(DEVICE) ? desiredPosition(devices)
                    : cameras.suggestedPosition(DualCameraSession.Role.RGB);
        } catch (RuntimeException error) {
            cameras.clear();
            selection = 0;
        }
        cameras.bindDevices(device, selection);
    }

    private int desiredPosition(List<UsbDevice> devices) {
        for (int i = 0; i < devices.size(); i++) {
            UsbDevice candidate = devices.get(i);
            if (candidate.getDeviceName().equals(desired.getString(DEVICE))
                    && candidate.getVendorId() == desired.getInt(VENDOR)
                    && candidate.getProductId() == desired.getInt(PRODUCT)) return i + 1;
        }
        return 0;
    }

    UsbDevice selected() { return cameras.selected(device); }
    int rotation() { return UvcCameraChoices.rotationDegrees(rotation); }

    void show(Runnable dismissed) {
        if (dialog != null && dialog.isShowing()) return;
        if (dialog == null) dialog = new MaterialAlertDialogBuilder(owner).setTitle(R.string.uvc_enroll_camera_settings).setView(form)
                .setPositiveButton(R.string.uvc_search_done, null).create();
        dialog.setOnDismissListener(d -> dismissed.run());
        dialog.show();
    }

    void dismiss() { if (dialog != null) dialog.dismiss(); }
    boolean isShowing() { return dialog != null && dialog.isShowing(); }

    void save(Bundle out) {
        putChoice(desired, selected(), rotation());
        if (desired.containsKey(DEVICE)) {
            out.putString(DEVICE, desired.getString(DEVICE));
            out.putInt(VENDOR, desired.getInt(VENDOR));
            out.putInt(PRODUCT, desired.getInt(PRODUCT));
        }
        out.putInt(ROTATION, rotation());
    }
}
