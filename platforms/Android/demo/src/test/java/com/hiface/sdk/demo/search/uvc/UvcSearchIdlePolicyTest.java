package com.hiface.sdk.demo.search.uvc;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class UvcSearchIdlePolicyTest {
    @Test public void idleStartsAfterTenSecondsOfSuccessfulEmptyDetections() {
        UvcSearchIdlePolicy policy = new UvcSearchIdlePolicy();
        observeEmptyScene(policy);
        assertTrue(policy.isIdle());
    }

    @Test public void emptyDetectionImmediatelySlowsAnalysisAndTheFirstFaceRestoresIt() {
        UvcSearchIdlePolicy policy = new UvcSearchIdlePolicy();
        assertTrue(policy.shouldAnalyze(0));
        policy.onDetection(0, false);
        assertFalse(policy.isIdle());
        assertFalse(policy.shouldAnalyze(197));
        assertTrue(policy.shouldAnalyze(198));
        assertTrue(policy.shouldAnalyze(230)); // The previous SDK call was skipped.
        policy.onDetection(230, false);
        assertFalse(policy.shouldAnalyze(263));
        assertTrue(policy.shouldAnalyze(430));

        policy.onDetection(430, true);
        assertFalse(policy.isIdle());
        assertTrue(policy.shouldAnalyze(463));
    }

    @Test public void pairLossRestartsTheObservationWindow() {
        UvcSearchIdlePolicy policy = new UvcSearchIdlePolicy();
        observeEmptyScene(policy);
        assertFalse(policy.shouldAnalyze(10_100));
        assertTrue(policy.shouldAnalyze(10_401));
        assertFalse(policy.isIdle());
        policy.onDetection(10_401, false);
        assertFalse(policy.shouldAnalyze(10_434));
        assertFalse(policy.isIdle());
    }

    @Test public void pairsWithoutSuccessfulDetectionsDoNotSustainIdle() {
        UvcSearchIdlePolicy policy = new UvcSearchIdlePolicy();
        observeEmptyScene(policy);
        for (long now = 10_100; now <= 13_000; now += 100) policy.shouldAnalyze(now);
        assertFalse(policy.isIdle());
    }

    private static void observeEmptyScene(UvcSearchIdlePolicy policy) {
        for (long now = 0; now <= 10_000; now += 200) {
            assertTrue(policy.shouldAnalyze(now));
            assertFalse(policy.isIdle());
            policy.onDetection(now, false);
        }
    }
}
