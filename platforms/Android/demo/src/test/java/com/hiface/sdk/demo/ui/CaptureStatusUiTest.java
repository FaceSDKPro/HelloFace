package com.hiface.sdk.demo.ui;

import org.junit.Test;
import static org.junit.Assert.assertEquals;

public final class CaptureStatusUiTest {
    @Test
    public void guidedCaptureCountdownMatchesSdkHoldWindow() {
        assertEquals(700L, CaptureStatusUi.CAPTURE_STABLE_COUNTDOWN_MILLIS);
    }
}
