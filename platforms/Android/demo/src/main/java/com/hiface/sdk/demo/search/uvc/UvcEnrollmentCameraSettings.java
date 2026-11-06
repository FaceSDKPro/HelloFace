package com.hiface.sdk.demo.search.uvc;

import android.hardware.usb.UsbDevice;
import android.os.Bundle;
import android.view.View;
import android.widget.ArrayAdapter;
import android.widget.Spinner;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import com.facesdkpro.uvccamera.DualCameraSession;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.hiface.sdk.demo.R;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

/** 录入只选 RGB UVC。跨页面/旋转以设备地址及 VID/PID 重新匹配，不保存枚举下标。 */
final class UvcEnrollmentCameraSettings {
    private static final String DEVICE = "enrollUvcDevice", VENDOR = "enrollUvcVendor", PRODUCT = "enrollUvcProduct", ROTATION = "enrollUvcRotation";
    private final AppCompatActivity owner;
    private final View form;
    private final Spinner device, rotation;
    private final List<UsbDevice> devices = new ArrayList<>();
    private final Bundle desired;
    private AlertDialog dialog;

    UvcEnrollmentCameraSettings(AppCompatActivity owner, Bundle saved, Bundle source) {
        this.owner = owner;
        desired = saved != null ? new Bundle(saved) : source == null ? new Bundle() : new Bundle(source);
        form = owner.getLayoutInflater().inflate(R.layout.view_uvc_enrollment_settings, null, false);
        device = form.findViewById(R.id.uvcEnrollDevice);
        rotation = form.findViewById(R.id.uvcEnrollRotation);
        rotation.setAdapter(new ArrayAdapter<>(owner, android.R.layout.simple_spinner_dropdown_item,
                Arrays.asList("0°", "90°", "180°", "270°")));
        int degrees = desired.getInt(ROTATION);
        rotation.setSelection(degrees >= 0 && degrees <= 270 && degrees % 90 == 0 ? degrees / 90 : 0);
        form.findViewById(R.id.uvcEnrollRefresh).setOnClickListener(v -> refresh());
    }

    static void putChoice(Bundle out, UsbDevice device, int rotation) {
        if (device != null) {
            out.putString(DEVICE, device.getDeviceName());
            out.putInt(VENDOR, device.getVendorId()); out.putInt(PRODUCT, device.getProductId());
        }
        out.putInt(ROTATION, rotation);
    }

    void refresh() {
        UsbDevice previous = selected();
        if (previous != null) putChoice(desired, previous, rotation());
        devices.clear();
        List<String> names = new ArrayList<>(); names.add(owner.getString(R.string.uvc_search_select_camera));
        int selection = 0, rgb = 0;
        try {
            devices.addAll(DualCameraSession.devices(owner));
            for (int i = 0; i < devices.size(); i++) {
                UsbDevice candidate = devices.get(i);
                String name = candidate.getProductName();
                names.add(String.format(Locale.ROOT, "%s (%04X:%04X)", name == null ? candidate.getDeviceName() : name,
                        candidate.getVendorId(), candidate.getProductId()));
                if (candidate.getDeviceName().equals(desired.getString(DEVICE))
                        && candidate.getVendorId() == desired.getInt(VENDOR)
                        && candidate.getProductId() == desired.getInt(PRODUCT)) selection = i + 1;
                if (name != null && name.toUpperCase(Locale.ROOT).contains("RGB")) rgb = rgb == 0 ? i + 1 : -1;
            }
            // 明确指定的设备消失时不改选另一台；没有来源选择时才预选名称唯一的 RGB。
            if (!desired.containsKey(DEVICE)) selection = Math.max(0, rgb);
        } catch (RuntimeException error) {
            devices.clear(); names.subList(1, names.size()).clear(); selection = 0;
        }
        device.setAdapter(new ArrayAdapter<>(owner, android.R.layout.simple_spinner_dropdown_item, names));
        device.setSelection(selection);
    }

    UsbDevice selected() {
        int index = device.getSelectedItemPosition() - 1;
        return index >= 0 && index < devices.size() ? devices.get(index) : null;
    }

    int rotation() { return Math.max(0, rotation.getSelectedItemPosition()) * 90; }

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
            out.putInt(VENDOR, desired.getInt(VENDOR)); out.putInt(PRODUCT, desired.getInt(PRODUCT));
        }
        out.putInt(ROTATION, rotation());
    }
}
