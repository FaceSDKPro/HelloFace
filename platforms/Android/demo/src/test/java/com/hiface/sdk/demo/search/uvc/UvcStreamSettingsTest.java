package com.hiface.sdk.demo.search.uvc;

import com.facesdkpro.uvccamera.CameraFailure;
import com.facesdkpro.uvccamera.DualCameraSession;
import com.facesdkpro.uvccamera.StreamConfig;
import com.hiface.sdk.demo.R;
import org.junit.Test;
import static org.junit.Assert.*;

public final class UvcStreamSettingsTest {
    @Test public void preferencesPreserveRolePixelsAndAllowIndependentResolutionAndFps() {
        StreamConfig rgb = UvcStreamSettings.config(DualCameraSession.Role.RGB, 1, 0);
        StreamConfig ir = UvcStreamSettings.config(DualCameraSession.Role.IR, 0, 1);
        assertEquals(1280, rgb.width);
        assertEquals(720, rgb.height);
        assertEquals(15, rgb.fps);
        assertEquals(640, ir.width);
        assertEquals(480, ir.height);
        assertEquals(30, ir.fps);
        assertNotEquals(rgb.pixelFormat, ir.pixelFormat);
        assertEquals(rgb.frameType, ir.frameType);
        assertTrue(rgb.closestSupportedMode);
        assertTrue(ir.closestSupportedMode);
    }

    @Test public void invalidSavedIndicesUseConservativeDefaults() {
        StreamConfig config = UvcStreamSettings.config(DualCameraSession.Role.RGB, -1, 90);
        assertEquals(640, config.width);
        assertEquals(480, config.height);
        assertEquals(15, config.fps);
    }

    @Test public void nativeStartupFailuresGiveSpecificRecoveryHints() {
        assertEquals(R.string.uvc_camera_unsupported_mode, UvcCameraFailureUi.message(CameraFailure.Code.UNSUPPORTED_MODE));
        assertEquals(R.string.uvc_camera_busy, UvcCameraFailureUi.message(CameraFailure.Code.DEVICE_BUSY));
        assertEquals(R.string.uvc_camera_open_timeout, UvcCameraFailureUi.message(CameraFailure.Code.OPEN_TIMEOUT));
        assertEquals(R.string.uvc_search_usb_permission, UvcCameraFailureUi.message(CameraFailure.Code.USB_PERMISSION_DENIED));
    }
}
