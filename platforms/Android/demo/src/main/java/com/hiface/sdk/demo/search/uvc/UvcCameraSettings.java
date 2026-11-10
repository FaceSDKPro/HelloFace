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
import com.facesdkpro.uvccamera.CameraSelection;
import com.facesdkpro.uvccamera.DualCameraSession;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.search.InfraredSearchConfig;
import java.util.List;

/** Main-thread device selection and validation; owns no capture session. 中文：仅管理双目设置表单。 */
final class UvcCameraSettings {
    private static final int MAX_PAIR_SKEW_MS = 50, MAX_FRAME_AGE_MS = 150;
    private static final String DEFAULT_IR_THRESHOLD = "0.70";

    /** Validated settings for one start; USB roles never come from enumeration order or stale indices. */
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
    private final UvcStreamSettings rgbStream, irStream;
    private AlertDialog dialog;
    private int validationMessage;
    private UvcDeviceChoicePolicy.Device rememberedRgb, rememberedIr;

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
        rgbStream = new UvcStreamSettings(form.findViewById(R.id.uvcRgbStream), "rgbStream", false);
        irStream = new UvcStreamSettings(form.findViewById(R.id.uvcIrStream), "irStream", false);
        threshold.setText(DEFAULT_IR_THRESHOLD);
        UvcCameraChoices.bindRotation(rgbRotation, 0);
        UvcCameraChoices.bindRotation(irRotation, 0);
        form.findViewById(R.id.uvcRefresh).setOnClickListener(v -> refresh.run());
        debug.setOnCheckedChangeListener((button, checked) -> debugChanged.run());
    }

    UsbDevice selectedRgbDevice() { return cameras.selected(rgbDevice); }
    int rgbRotationDegrees() { return UvcCameraChoices.rotationDegrees(rgbRotation); }

    Bundle enrollmentChoice() {
        Bundle choice = new Bundle();
        UvcEnrollmentCameraSettings.putChoice(choice, selectedRgbDevice(), rgbRotationDegrees());
        rgbStream.save(choice, UvcEnrollmentCameraSettings.STREAM_KEY);
        return choice;
    }

    boolean debugEnabled() { return debug.isChecked(); }
    int validationMessage() { return validationMessage; }
    int deviceCount() { return cameras.size(); }

    boolean usesDevice(UsbDevice device) {
        return device.equals(selectedRgbDevice()) || device.equals(cameras.selected(irDevice));
    }

    /** Rebind current USB handles and report inventory changes; remember choices across disconnection. */
    boolean refreshDevices() {
        UvcDeviceChoicePolicy.Device rgb = cameras.selectedIdentity(rgbDevice);
        UvcDeviceChoicePolicy.Device ir = cameras.selectedIdentity(irDevice);
        if (rgb != null) rememberedRgb = rgb;
        if (ir != null) rememberedIr = ir;
        List<UvcDeviceChoicePolicy.Device> previous = cameras.identities();
        try {
            cameras.refresh();
            cameras.bindDevices(rgbDevice, cameras.preferredPosition(rememberedRgb, DualCameraSession.Role.RGB));
            cameras.bindDevices(irDevice, cameras.preferredPosition(rememberedIr, DualCameraSession.Role.IR));
            return !previous.equals(cameras.identities());
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
        return CameraSelection.isPair(rgb, ir) ? R.string.uvc_search_ready : R.string.uvc_search_choose_distinct;
    }

    /** Keep invalid input editable; return capture settings only after device and threshold validation. */
    Selection read() {
        validationMessage = setupHint();
        if (validationMessage != R.string.uvc_search_ready) return null;
        Float value = validateThreshold();
        if (value == null) {
            validationMessage = R.string.uvc_search_threshold_invalid;
            return null;
        }
        // Pairing and SDK checks share 50/150 ms limits; calibrate mapping and IoU for the target module.
        InfraredSearchConfig infrared = new InfraredSearchConfig(value,
                new float[]{1,0,0,0,1,0,0,0,1}, .25f, 80, MAX_PAIR_SKEW_MS, MAX_FRAME_AGE_MS);
        DualCameraConfig config = DualCameraConfig.forStreams(rgbStream.read(DualCameraSession.Role.RGB),
                irStream.read(DualCameraSession.Role.IR))
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

    void show(boolean discovered, Runnable done) {
        if (dialog == null) {
            dialog = new MaterialAlertDialogBuilder(owner).setView(form)
                    .setPositiveButton(R.string.uvc_search_done, null).create();
        }
        dialog.setTitle(discovered ? R.string.uvc_search_devices_found : R.string.uvc_search_settings);
        // Bind the current callback on each show; Done cannot dismiss an invalid threshold.
        dialog.setOnShowListener(ignored -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(view -> {
            if (validateThreshold() == null) return;
            dialog.dismiss();
            done.run();
        }));
        dialog.show();
    }

    void dismiss() { if (dialog != null) dialog.dismiss(); }

    void setEditable(boolean editable) {
        form.findViewById(R.id.uvcRefresh).setEnabled(editable);
        debug.setEnabled(editable);
    }

    void restore(Bundle saved) {
        if (saved == null) return;
        rgbStream.restore(saved);
        irStream.restore(saved);
        rgbRotation.setSelection(saved.getInt("rgbRotation"));
        irRotation.setSelection(saved.getInt("irRotation"));
        String restored = saved.getString("irThreshold", DEFAULT_IR_THRESHOLD);
        threshold.setText(parseThreshold(restored) == null ? DEFAULT_IR_THRESHOLD : restored);
        debug.setChecked(saved.getBoolean("debug"));
    }

    void save(Bundle out) {
        rgbStream.save(out);
        irStream.save(out);
        // Never persist enumeration indices; rebuild device choices from current attachments.
        out.putInt("rgbRotation", rgbRotation.getSelectedItemPosition());
        out.putInt("irRotation", irRotation.getSelectedItemPosition());
        out.putString("irThreshold", threshold.getText().toString());
        out.putBoolean("debug", debug.isChecked());
    }
}
