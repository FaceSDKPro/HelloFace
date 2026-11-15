package com.hiface.sdk.demo.recognition;

import android.view.MotionEvent;

/** Keeps a horizontal swipe or consumed long press from falling through as a portrait tap. */
final class ReferenceGestureGate {
    private float downX;
    private float downY;
    private boolean blocked;

    void onTouch(int action, float x, float y, int touchSlop) {
        if (action == MotionEvent.ACTION_DOWN) {
            downX = x;
            downY = y;
            blocked = false;
            return;
        }
        if (action == MotionEvent.ACTION_CANCEL) {
            blocked = true;
            return;
        }
        if (action != MotionEvent.ACTION_MOVE || blocked) return;
        float dx = x - downX;
        float dy = y - downY;
        blocked = dx * dx + dy * dy > touchSlop * touchSlop;
    }

    boolean canActivate() { return !blocked; }

    void consumeLongPress() { blocked = true; }
}
