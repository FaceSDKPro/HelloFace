package com.hiface.sdk.demo.search.uvc;

import org.junit.After;
import org.junit.Test;
import java.util.ArrayList;
import java.util.List;
import static org.junit.Assert.*;

public final class UvcCameraCloseBarrierTest {
    private final List<UvcCameraCloseBarrier> owners = new ArrayList<>();
    private UvcCameraCloseBarrier owner() {
        UvcCameraCloseBarrier barrier = new UvcCameraCloseBarrier(); owners.add(barrier); return barrier;
    }
    @After public void detach() {
        for (UvcCameraCloseBarrier barrier : owners) barrier.listen(null);
        while (!owners.isEmpty() && owners.get(0).isClosing())
            for (UvcCameraCloseBarrier barrier : owners) barrier.closed();
    }

    @Test public void recreatedOwnerWaitsForAllOldClosuresAndOldOwnerIsDetached() {
        UvcCameraCloseBarrier barrier = owner();
        int[] old = {0}, next = {0};
        barrier.listen(() -> old[0]++);
        barrier.closing(); barrier.closing();
        barrier.listen(null);
        barrier.listen(() -> next[0]++);
        barrier.closed();
        assertTrue(barrier.isClosing()); assertEquals(0, next[0]);
        barrier.closed();
        assertFalse(barrier.isClosing()); assertEquals(1, next[0]); assertEquals(0, old[0]);
        barrier.closed(); assertEquals(1, next[0]);
    }

    @Test public void backgroundCompletionDoesNotReopenCameraUntilForegroundRequestsIt() {
        UvcCameraCloseBarrier barrier = owner();
        int[] calls = {0};
        barrier.listen(() -> calls[0]++); barrier.closing(); barrier.listen(null);
        barrier.closed();
        assertEquals(0, calls[0]); assertFalse(barrier.isClosing());
        barrier.listen(() -> calls[0]++);
        assertEquals(0, calls[0]);
    }

    @Test public void searchAndEnrollmentWaitForEachOthersUsbShutdown() {
        UvcCameraCloseBarrier search = owner(), enrollment = owner();
        int[] resumed = {0};
        search.closing(); search.listen(null);
        enrollment.listen(() -> resumed[0]++);
        assertTrue(enrollment.isClosing());
        search.closed();
        assertEquals(1, resumed[0]); assertFalse(enrollment.isClosing());
        enrollment.closing(); enrollment.listen(null);
        search.listen(() -> resumed[0]++);
        assertTrue(search.isClosing());
        search.closed(); // Duplicate completion must not release enrollment's USB close.
        assertTrue(search.isClosing()); assertEquals(1, resumed[0]);
        enrollment.closed();
        assertEquals(2, resumed[0]); assertFalse(search.isClosing());
    }
}
