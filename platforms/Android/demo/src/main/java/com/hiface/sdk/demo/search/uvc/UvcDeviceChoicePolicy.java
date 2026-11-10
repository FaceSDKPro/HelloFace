package com.hiface.sdk.demo.search.uvc;

import java.util.List;
import java.util.Objects;

/** Pure matching of current attachments; avoids indices and permission-gated serials. 中文：设备角色匹配策略。 */
final class UvcDeviceChoicePolicy {
    private UvcDeviceChoicePolicy() {}

    /** Address identifies an attachment; VID/PID and product name can rematch a unique model. */
    static final class Device {
        final String address, productName;
        final int vendorId, productId;

        Device(String address, int vendorId, int productId, String productName) {
            this.address = address;
            this.vendorId = vendorId;
            this.productId = productId;
            this.productName = productName;
        }

        boolean sameModel(Device other) {
            return vendorId == other.vendorId && productId == other.productId
                    && Objects.equals(productName, other.productName);
        }

        @Override public boolean equals(Object other) {
            if (!(other instanceof Device)) return false;
            Device device = (Device) other;
            return Objects.equals(address, device.address) && sameModel(device);
        }

        @Override public int hashCode() { return Objects.hash(address, vendorId, productId, productName); }
    }

    /** Retain an explicit attachment or unique original model; never substitute a different camera. */
    static int retainedPosition(List<Device> devices, Device previous) {
        if (previous == null) return 0;
        for (int i = 0; i < devices.size(); i++)
            if (previous.equals(devices.get(i))) return i + 1;
        int match = 0;
        for (int i = 0; i < devices.size(); i++) {
            if (!previous.sameModel(devices.get(i))) continue;
            if (match != 0) return 0;
            match = i + 1;
        }
        return match;
    }
}
