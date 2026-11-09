package com.hiface.sdk.demo.search.uvc;

import java.util.Arrays;
import java.util.Collections;
import org.junit.Test;
import static org.junit.Assert.*;

public final class UvcDeviceChoicePolicyTest {
    private UvcDeviceChoicePolicy.Device device(String address, int productId, String name) {
        return new UvcDeviceChoicePolicy.Device(address, 123, productId, name);
    }

    @Test public void rolesComeFromUniqueNamesRatherThanEnumerationOrder() {
        UvcDeviceChoicePolicy.Device ir = device("/ir", 1, "RP26LD IR");
        UvcDeviceChoicePolicy.Device rgb = device("/rgb", 2, "RP26PWD RGB");
        assertEquals(2, UvcDeviceChoicePolicy.position(Arrays.asList(ir, rgb), null, true));
        assertEquals(1, UvcDeviceChoicePolicy.position(Arrays.asList(ir, rgb), null, false));
    }

    @Test public void reconnectUsesNewAddressOfTheSameUniqueCamera() {
        UvcDeviceChoicePolicy.Device old = device("/old", 2, "User selected camera");
        UvcDeviceChoicePolicy.Device replacement = device("/new", 2, "User selected camera");
        assertEquals(2, UvcDeviceChoicePolicy.position(Arrays.asList(
                device("/other", 3, "Other camera"), replacement), old, true));
    }

    @Test public void connectedManualChoiceSurvivesListReordering() {
        UvcDeviceChoicePolicy.Device selected = device("/chosen", 1, "Camera");
        assertEquals(2, UvcDeviceChoicePolicy.position(Arrays.asList(
                device("/other", 1, "Camera"), selected), selected, true));
    }

    @Test public void identicalReconnectedDevicesRequireUserConfirmation() {
        assertEquals(0, UvcDeviceChoicePolicy.position(Arrays.asList(
                device("/new-a", 1, "Camera"), device("/new-b", 1, "Camera")),
                device("/old", 1, "Camera"), true));
    }

    @Test public void reusedUsbAddressDoesNotProveTheOldCameraIsStillPresent() {
        assertEquals(0, UvcDeviceChoicePolicy.position(Collections.singletonList(
                device("/same-address", 2, "Different camera")),
                device("/same-address", 1, "Old camera"), true));
    }

    @Test public void ambiguousNamesDoNotAssignTheSameDeviceToBothRoles() {
        for (boolean rgb : new boolean[]{true, false}) {
            assertEquals(0, UvcDeviceChoicePolicy.position(Collections.singletonList(
                    device("/both", 1, "RGB IR camera")), null, rgb));
        }
        assertEquals(0, UvcDeviceChoicePolicy.position(Arrays.asList(
                device("/a", 1, "RGB A"), device("/b", 2, "RGB B")), null, true));
    }

    @Test public void irPrefixAndEmptyInventoryAreSupported() {
        assertEquals(1, UvcDeviceChoicePolicy.position(Collections.singletonList(
                device("/ir", 1, "IR camera")), null, false));
        assertEquals(0, UvcDeviceChoicePolicy.position(Collections.emptyList(), null, false));
    }
}
