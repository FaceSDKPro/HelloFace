package com.hiface.sdk.demo.search.uvc;

import java.util.Arrays;
import java.util.Collections;
import org.junit.Test;
import static org.junit.Assert.*;

public final class UvcDeviceChoicePolicyTest {
    private UvcDeviceChoicePolicy.Device device(String address, int productId, String name) {
        return new UvcDeviceChoicePolicy.Device(address, 123, productId, name);
    }

    @Test public void reconnectUsesNewAddressOfTheSameUniqueCamera() {
        UvcDeviceChoicePolicy.Device old = device("/old", 2, "User selected camera");
        UvcDeviceChoicePolicy.Device replacement = device("/new", 2, "User selected camera");
        assertEquals(2, UvcDeviceChoicePolicy.retainedPosition(Arrays.asList(
                device("/other", 3, "Other camera"), replacement), old));
    }

    @Test public void connectedManualChoiceSurvivesListReordering() {
        UvcDeviceChoicePolicy.Device selected = device("/chosen", 1, "Camera");
        assertEquals(2, UvcDeviceChoicePolicy.retainedPosition(Arrays.asList(
                device("/other", 1, "Camera"), selected), selected));
    }

    @Test public void identicalReconnectedDevicesRequireUserConfirmation() {
        assertEquals(0, UvcDeviceChoicePolicy.retainedPosition(Arrays.asList(
                device("/new-a", 1, "Camera"), device("/new-b", 1, "Camera")),
                device("/old", 1, "Camera")));
    }

    @Test public void reusedUsbAddressDoesNotProveTheOldCameraIsStillPresent() {
        assertEquals(0, UvcDeviceChoicePolicy.retainedPosition(Collections.singletonList(
                device("/same-address", 2, "Different camera")),
                device("/same-address", 1, "Old camera")));
    }

    @Test public void missingManualChoiceDoesNotSubstituteAnotherRgbCamera() {
        assertEquals(0, UvcDeviceChoicePolicy.retainedPosition(Collections.singletonList(
                device("/another", 3, "RGB camera")), device("/missing", 2, "RGB camera")));
        assertEquals(0, UvcDeviceChoicePolicy.retainedPosition(Collections.emptyList(), null));
    }
}
