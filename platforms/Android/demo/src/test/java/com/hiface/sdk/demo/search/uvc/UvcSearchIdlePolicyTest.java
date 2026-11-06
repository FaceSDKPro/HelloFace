package com.hiface.sdk.demo.search.uvc;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class UvcSearchIdlePolicyTest {
    @Test public void idleStartsAfterTenSecondsOfSuccessfulEmptyDetections() {
        UvcSearchIdlePolicy policy = new UvcSearchIdlePolicy();
        for (long now = 0; now <= 10_000; now += 100) {
            assertTrue(policy.shouldAnalyze(now));
            assertFalse(policy.isIdle());
        }
        observeEmptyScene(policy, 10_100);
        assertTrue(policy.isIdle());
    }

    @Test public void idleKeepsProbingAndResumesAfterTheFirstDetectedFace() {
        UvcSearchIdlePolicy policy = new UvcSearchIdlePolicy();
        observeEmptyScene(policy, 0);

        assertFalse(policy.shouldAnalyze(10_197));
        assertTrue(policy.shouldAnalyze(10_198));
        assertTrue(policy.shouldAnalyze(10_230)); // The previous SDK call was skipped.
        policy.onDetection(10_230, false);
        assertFalse(policy.shouldAnalyze(10_263));
        assertTrue(policy.shouldAnalyze(10_430));

        policy.onDetection(10_430, true);
        assertFalse(policy.isIdle());
        assertTrue(policy.shouldAnalyze(10_463));
    }

    @Test public void pairLossRestartsTheObservationWindow() {
        UvcSearchIdlePolicy policy = new UvcSearchIdlePolicy();
        observeEmptyScene(policy, 0);
        assertFalse(policy.shouldAnalyze(10_100));
        assertTrue(policy.shouldAnalyze(10_401));
        assertFalse(policy.isIdle());
        policy.onDetection(10_401, false);
        assertTrue(policy.shouldAnalyze(10_434));
        assertFalse(policy.isIdle());
    }

    private static void observeEmptyScene(UvcSearchIdlePolicy policy, long start) {
        for (long now = start; now <= start + 10_000; now += 100) {
            assertTrue(policy.shouldAnalyze(now));
            assertFalse(policy.isIdle());
            policy.onDetection(now, false);
        }
    }
}
