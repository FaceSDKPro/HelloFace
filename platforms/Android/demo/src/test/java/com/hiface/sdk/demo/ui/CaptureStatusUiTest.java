package com.hiface.sdk.demo.ui;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class CaptureStatusUiTest {
    @Test
    public void guidedCaptureCountdownMatchesSdkHoldWindow() {
        assertEquals(700L, CaptureStatusUi.CAPTURE_STABLE_COUNTDOWN_MILLIS);
    }
}
