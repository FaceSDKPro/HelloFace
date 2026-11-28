package com.hiface.sdk.demo.camera;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class CameraSettingsTest {
    @Test
    public void oldZoomValuesResolveToTheNearestPreset() {
        assertEquals(0, CameraSettings.nearestZoomPresetIndex(0.85f));
        assertEquals(1, CameraSettings.nearestZoomPresetIndex(1.4f));
        assertEquals(2, CameraSettings.nearestZoomPresetIndex(2.4f));
        assertEquals(3, CameraSettings.nearestZoomPresetIndex(4f));
    }

    @Test
    public void invalidZoomValuesUseOneTimes() {
        assertEquals(1, CameraSettings.nearestZoomPresetIndex(0f));
        assertEquals(1, CameraSettings.nearestZoomPresetIndex(Float.NaN));
        assertEquals(1, CameraSettings.nearestZoomPresetIndex(Float.POSITIVE_INFINITY));
    }
}
