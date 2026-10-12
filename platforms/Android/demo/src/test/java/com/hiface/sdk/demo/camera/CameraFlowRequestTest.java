package com.hiface.sdk.demo.camera;

import org.junit.Test;

import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.Assert.*;

public final class CameraFlowRequestTest {
    @Test public void idleDoesNotForwardFramesOrFinish() {
        CameraFlowRequest flow = new CameraFlowRequest();
        assertFalse(flow.isActive());
        assertFalse(flow.finish());
        flow.cancel();
        assertFalse(flow.isActive());
    }

    @Test public void startEnablesFrameDeliveryBeforeCreatingRequest() {
        CameraFlowRequest flow = new CameraFlowRequest();
        assertTrue(flow.start(() -> {
            assertTrue(flow.isActive());
            return () -> {};
        }));
        assertTrue(flow.isActive());
    }

    @Test public void duplicateStartDoesNotReplaceOrCreateRequest() {
        CameraFlowRequest flow = new CameraFlowRequest();
        AtomicInteger cancellations = new AtomicInteger();
        flow.start(() -> cancellations::incrementAndGet);
        assertFalse(flow.start(() -> {
            fail("A second request must not be created");
            return () -> {};
        }));
        flow.cancel();
        assertEquals(1, cancellations.get());
    }

    @Test public void completionRunsOnlyOnceAndReleasesTerminalRequest() {
        CameraFlowRequest flow = new CameraFlowRequest();
        AtomicInteger cancellations = new AtomicInteger();
        flow.start(() -> cancellations::incrementAndGet);
        assertTrue(flow.finish());
        assertFalse(flow.finish());
        assertFalse(flow.isActive());
        flow.cancel();
        assertEquals(0, cancellations.get());
    }

    @Test public void backgroundCancellationClosesFrameGateBeforeCancellingSdk() {
        CameraFlowRequest flow = new CameraFlowRequest();
        AtomicInteger cancellations = new AtomicInteger();
        flow.start(() -> () -> {
            assertFalse(flow.isActive());
            assertFalse(flow.finish());
            cancellations.incrementAndGet();
        });
        flow.cancel();
        flow.cancel();
        assertEquals(1, cancellations.get());
    }

    @Test public void cancellationAndCompletionBothAllowAnotherChallenge() {
        CameraFlowRequest flow = new CameraFlowRequest();
        AtomicInteger first = new AtomicInteger();
        AtomicInteger second = new AtomicInteger();
        flow.start(() -> first::incrementAndGet);
        flow.cancel();
        assertTrue(flow.start(() -> second::incrementAndGet));
        assertTrue(flow.finish());
        assertTrue(flow.start(() -> second::incrementAndGet));
        flow.cancel();
        assertEquals(1, first.get());
        assertEquals(1, second.get());
    }

    @Test public void synchronousCompletionCannotRetainReturnedHandle() {
        assertSynchronousEndReleasesHandle(true);
    }

    @Test public void synchronousCancellationCannotRetainReturnedHandle() {
        assertSynchronousEndReleasesHandle(false);
    }

    private static void assertSynchronousEndReleasesHandle(boolean complete) {
        CameraFlowRequest flow = new CameraFlowRequest();
        AtomicInteger cancellations = new AtomicInteger();
        flow.start(() -> {
            if (complete) assertTrue(flow.finish());
            else flow.cancel();
            return cancellations::incrementAndGet;
        });
        assertFalse(flow.isActive());
        flow.cancel();
        assertEquals(1, cancellations.get());
    }

    @Test public void failedStartRollsBackAndAllowsRetry() {
        CameraFlowRequest flow = new CameraFlowRequest();
        RuntimeException failure = new IllegalStateException("failed");
        try {
            flow.start(() -> { throw failure; });
            fail("Expected startup failure");
        } catch (RuntimeException error) {
            assertSame(failure, error);
        }
        assertFalse(flow.isActive());
        assertTrue(flow.start(() -> () -> {}));
    }

    @Test public void missingHandleRollsBackInsteadOfLeavingFrameGateOpen() {
        CameraFlowRequest flow = new CameraFlowRequest();
        try {
            flow.start(() -> null);
            fail("Expected missing request");
        } catch (NullPointerException expected) {
            assertEquals("request", expected.getMessage());
        }
        assertFalse(flow.isActive());
        assertTrue(flow.start(() -> () -> {}));
    }
}
