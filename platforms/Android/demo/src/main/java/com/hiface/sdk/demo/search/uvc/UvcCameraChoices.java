package com.hiface.sdk.demo.search.uvc;

import android.content.Context;
import android.hardware.usb.UsbDevice;
import android.widget.ArrayAdapter;
import android.widget.Spinner;
import com.facesdkpro.uvccamera.DualCameraSession;
import com.hiface.sdk.demo.R;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/** 搜索和录入共用设备列表的显示、选择与旋转规则。 */
final class UvcCameraChoices {
    private final Context context;
    private List<UsbDevice> devices;
    private List<String> labels;

    UvcCameraChoices(Context context) {
        this.context = context;
        clear();
    }

    List<UsbDevice> refresh() {
        // 设备列表和标签一起替换，枚举失败时旧下标不会指向另一台设备。
        clear();
        List<UsbDevice> found = DualCameraSession.devices(context);
        List<String> names = new ArrayList<>(labels);
        for (UsbDevice device : found) {
            String name = device.getProductName();
            names.add(String.format(Locale.ROOT, "%s (%04X:%04X)",
                    name == null ? device.getDeviceName() : name, device.getVendorId(), device.getProductId()));
        }
        devices = found;
        labels = names;
        return found;
    }

    void clear() {
        devices = Collections.emptyList();
        labels = Collections.singletonList(context.getString(R.string.uvc_search_select_camera));
    }

    int size() { return devices.size(); }

    int suggestedPosition(DualCameraSession.Role role) {
        int position = 0;
        for (int i = 0; i < devices.size(); i++) {
            String product = devices.get(i).getProductName();
            if (product == null) continue;
            String name = product.toUpperCase(Locale.ROOT);
            boolean matches = role == DualCameraSession.Role.RGB ? name.contains("RGB")
                    : name.contains("NIR") || name.contains(" IR");
            if (!matches) continue;
            if (position != 0) return 0; // 名称有歧义时由用户选择。
            position = i + 1;
        }
        return position;
    }

    UsbDevice selected(Spinner spinner) {
        int index = spinner.getSelectedItemPosition() - 1; // 第一项是未选择占位。
        return index >= 0 && index < devices.size() ? devices.get(index) : null;
    }

    void bindDevices(Spinner spinner, int position) { bind(spinner, labels, position); }

    static void bindRotation(Spinner spinner, int degrees) {
        int position = degrees >= 0 && degrees <= 270 && degrees % 90 == 0 ? degrees / 90 : 0;
        bind(spinner, Arrays.asList("0°", "90°", "180°", "270°"), position);
    }

    static int rotationDegrees(Spinner spinner) { return Math.max(0, spinner.getSelectedItemPosition()) * 90; }

    private static void bind(Spinner spinner, List<String> values, int position) {
        spinner.setAdapter(new ArrayAdapter<>(spinner.getContext(), android.R.layout.simple_spinner_dropdown_item, values));
        spinner.setSelection(position);
    }
}
