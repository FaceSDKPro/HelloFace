package com.hiface.sdk.demo.search.uvc;

import android.content.Context;
import android.content.res.ColorStateList;
import android.content.res.TypedArray;
import android.hardware.usb.UsbDevice;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ArrayAdapter;
import android.widget.Spinner;
import android.widget.TextView;
import com.facesdkpro.uvccamera.DualCameraSession;
import com.hiface.sdk.demo.R;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/** Shared device labels, selection and rotation controls. 中文：供搜索与录入页共用。 */
final class UvcCameraChoices {
    private final Context context;
    private List<UsbDevice> devices;
    private List<String> labels;
    private List<UvcDeviceChoicePolicy.Device> identities;

    UvcCameraChoices(Context context) {
        this.context = context;
        clear();
    }

    List<UsbDevice> refresh() {
        // Replace devices and labels together so failed enumeration cannot leave stale indices.
        clear();
        List<UsbDevice> found = DualCameraSession.devices(context);
        List<String> names = new ArrayList<>(labels);
        List<UvcDeviceChoicePolicy.Device> keys = new ArrayList<>();
        for (UsbDevice device : found) {
            String name = device.getProductName();
            names.add(String.format(Locale.ROOT, "%s (%04X:%04X)",
                    name == null ? device.getDeviceName() : name, device.getVendorId(), device.getProductId()));
            keys.add(new UvcDeviceChoicePolicy.Device(device.getDeviceName(),
                    device.getVendorId(), device.getProductId(), name));
        }
        devices = found;
        labels = names;
        identities = Collections.unmodifiableList(keys);
        return found;
    }

    void clear() {
        devices = Collections.emptyList();
        labels = Collections.singletonList(context.getString(R.string.uvc_search_select_camera));
        identities = Collections.emptyList();
    }

    int size() { return devices.size(); }

    int preferredPosition(UvcDeviceChoicePolicy.Device previous, DualCameraSession.Role role) {
        return UvcDeviceChoicePolicy.position(identities, previous, role == DualCameraSession.Role.RGB);
    }

    List<UvcDeviceChoicePolicy.Device> identities() { return identities; }

    UvcDeviceChoicePolicy.Device selectedIdentity(Spinner spinner) {
        int index = spinner.getSelectedItemPosition() - 1;
        return index >= 0 && index < identities.size() ? identities.get(index) : null;
    }

    UsbDevice selected(Spinner spinner) {
        int index = spinner.getSelectedItemPosition() - 1; // Index zero is the unselected placeholder.
        return index >= 0 && index < devices.size() ? devices.get(index) : null;
    }

    void bindDevices(Spinner spinner, int position) { bind(spinner, labels, position); }

    static void bindRotation(Spinner spinner, int degrees) {
        int position = degrees >= 0 && degrees <= 270 && degrees % 90 == 0 ? degrees / 90 : 0;
        bind(spinner, Arrays.asList("0°", "90°", "180°", "270°"), position);
    }

    static int rotationDegrees(Spinner spinner) { return Math.max(0, spinner.getSelectedItemPosition()) * 90; }

    private static void bind(Spinner spinner, List<String> values, int position) {
        // Use the page theme for both the dark search page and the light enrollment page.
        TypedArray theme = spinner.getContext().obtainStyledAttributes(new int[]{
                android.R.attr.textColorPrimary, com.google.android.material.R.attr.colorSurface});
        ColorStateList text = theme.getColorStateList(0);
        int surface = theme.getColor(1, android.graphics.Color.WHITE);
        theme.recycle();
        spinner.setAdapter(new ArrayAdapter<String>(spinner.getContext(), android.R.layout.simple_spinner_dropdown_item, values) {
            @Override public View getView(int index, View recycled, ViewGroup parent) {
                TextView view = (TextView) super.getView(index, recycled, parent);
                if (text != null) view.setTextColor(text);
                return view;
            }
            @Override public View getDropDownView(int index, View recycled, ViewGroup parent) {
                TextView view = (TextView) super.getDropDownView(index, recycled, parent);
                if (text != null) view.setTextColor(text);
                view.setBackgroundColor(surface);
                return view;
            }
        });
        spinner.setSelection(position);
    }
}
