package com.hiface.sdk.demo.camera;

import org.junit.Test;
import static org.junit.Assert.*;

public final class CameraFrameRatePolicyTest {
    @Test public void idlePrefersRealFiveFpsAndActiveRestoresFifteen() {
        int[][] ranges = {{5, 30}, {15, 30}, {5, 5}, {15, 15}};
        assertEquals(2, CameraFrameRatePolicy.selectIndex(5, ranges));
        assertEquals(3, CameraFrameRatePolicy.selectIndex(15, ranges));
    }
    @Test public void unsupportedFiveFpsStillLowersCaptureToTenInsteadOfKeepingThirty() {
        int[][] ranges = {{30, 30}, {10, 10}, {15, 15}};
        assertEquals(1, CameraFrameRatePolicy.selectIndex(5, ranges));
        assertEquals(2, CameraFrameRatePolicy.selectIndex(15, ranges));
    }
    @Test public void fallbackNeverSetsAnUnreportedFiveFpsRange() {
        int[][] ranges = {{15, 30}, {30, 30}, {15, 15}};
        assertEquals(2, CameraFrameRatePolicy.selectIndex(5, ranges));
        assertEquals(2, CameraFrameRatePolicy.selectIndex(15, ranges));
    }
    @Test public void supportedVariableRangeRemainsPreferredOverAnUnsupportedTarget() {
        int[][] ranges = {{5, 30}, {10, 10}, {5, 10}};
        assertEquals(2, CameraFrameRatePolicy.selectIndex(5, ranges));
        assertEquals(0, CameraFrameRatePolicy.selectIndex(15, ranges));
    }
    @Test public void equalUpperLimitPrefersNarrowerRangeRegardlessOfOrder() {
        assertEquals(1, CameraFrameRatePolicy.selectIndex(15, new int[][]{{5, 15}, {15, 15}}));
        assertEquals(0, CameraFrameRatePolicy.selectIndex(15, new int[][]{{15, 15}, {5, 15}}));
    }
    @Test public void activeFallbackAvoidsSlowerThanRequestedRangeWhenPossible() {
        assertEquals(1, CameraFrameRatePolicy.selectIndex(15, new int[][]{{10, 10}, {30, 30}}));
        assertEquals(1, CameraFrameRatePolicy.selectIndex(15, new int[][]{{5, 5}, {10, 10}}));
    }
    @Test public void missingOrMalformedCapabilitiesLeaveHardwareUnchanged() {
        assertEquals(-1, CameraFrameRatePolicy.selectIndex(5, new int[0][]));
        assertEquals(-1, CameraFrameRatePolicy.selectIndex(5, new int[][]{{0, 0}, {30, 15}}));
        assertEquals(1, CameraFrameRatePolicy.selectIndex(5, new int[][]{{0, 0}, {10, 10}}));
    }
    @Test public void invalidTargetIsRejected() {
        for (int target : new int[]{0, -5}) {
            try {
                CameraFrameRatePolicy.selectIndex(target, new int[][]{{15, 15}});
                fail("Invalid target accepted");
            } catch (IllegalArgumentException expected) {}
        }
    }
}
