package com.hiface.sdk.demo.search.uvc;

import android.hardware.usb.UsbDevice;
import android.os.Bundle;
import android.view.View;
import android.widget.Spinner;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import com.facesdkpro.uvccamera.DualCameraSession;
import com.facesdkpro.uvccamera.StreamConfig;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.hiface.sdk.demo.R;
import java.util.List;

/** RGB-only enrollment settings; restore address/VID/PID rather than indices. 中文：录入不选择 IR 相机。 */
final class UvcEnrollmentCameraSettings {
    static final String STREAM_KEY = "enrollStream";
    private static final String DEVICE = "enrollUvcDevice", VENDOR = "enrollUvcVendor", PRODUCT = "enrollUvcProduct", ROTATION = "enrollUvcRotation";
    private final AppCompatActivity owner;
    private final View form;
    private final Spinner device, rotation;
    private final UvcCameraChoices cameras;
    private final Bundle desired;
    private final UvcStreamSettings stream;
    private AlertDialog dialog;

    UvcEnrollmentCameraSettings(AppCompatActivity owner, Bundle saved, Bundle source) {
        this.owner = owner;
        cameras = new UvcCameraChoices(owner);
        desired = saved != null ? new Bundle(saved) : source == null ? new Bundle() : new Bundle(source);
        form = owner.getLayoutInflater().inflate(R.layout.view_uvc_enrollment_settings, null, false);
        device = form.findViewById(R.id.uvcEnrollDevice);
        rotation = form.findViewById(R.id.uvcEnrollRotation);
        stream = new UvcStreamSettings(form.findViewById(R.id.uvcEnrollStream), STREAM_KEY, true);
        stream.restore(desired);
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
            // Keep the requested device identity while disconnected; display no selection until it returns.
            selection = desired.containsKey(DEVICE) ? desiredPosition(devices)
                    : cameras.preferredPosition(null, DualCameraSession.Role.RGB);
        } catch (RuntimeException error) {
            cameras.clear();
            selection = 0;
        }
        cameras.bindDevices(device, selection);
    }

    /** Keep the explicitly selected RGB device; do not substitute another camera while it is absent. */
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
    StreamConfig streamConfig() { return stream.read(DualCameraSession.Role.RGB); }

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
        stream.save(out);
        putChoice(desired, selected(), rotation());
        if (desired.containsKey(DEVICE)) {
            out.putString(DEVICE, desired.getString(DEVICE));
            out.putInt(VENDOR, desired.getInt(VENDOR));
            out.putInt(PRODUCT, desired.getInt(PRODUCT));
        }
        out.putInt(ROTATION, rotation());
    }
}
