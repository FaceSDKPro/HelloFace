package com.hiface.sdk.demo.recognition;

import android.view.MotionEvent;
import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public final class ReferenceGestureGateTest {
    @Test public void tapRemainsActiveWithinTouchSlop() {
        ReferenceGestureGate gate = new ReferenceGestureGate();
        gate.onTouch(MotionEvent.ACTION_DOWN, 10, 10, 12);
        gate.onTouch(MotionEvent.ACTION_MOVE, 18, 14, 12);
        assertTrue(gate.canActivate());
    }

    @Test public void swipeAndCancelCannotFallThroughAsTap() {
        ReferenceGestureGate gate = new ReferenceGestureGate();
        gate.onTouch(MotionEvent.ACTION_DOWN, 10, 10, 12);
        gate.onTouch(MotionEvent.ACTION_MOVE, 40, 10, 12);
        assertFalse(gate.canActivate());

        gate.onTouch(MotionEvent.ACTION_DOWN, 10, 10, 12);
        gate.onTouch(MotionEvent.ACTION_CANCEL, 10, 10, 12);
        assertFalse(gate.canActivate());
    }

    @Test public void consumedLongPressCannotAlsoOpenVerification() {
        ReferenceGestureGate gate = new ReferenceGestureGate();
        gate.onTouch(MotionEvent.ACTION_DOWN, 10, 10, 12);
        assertTrue(gate.canActivate());
        gate.consumeLongPress();
        assertFalse(gate.canActivate());
    }
}
