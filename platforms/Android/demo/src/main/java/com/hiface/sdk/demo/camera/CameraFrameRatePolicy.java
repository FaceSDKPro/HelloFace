package com.hiface.sdk.demo.camera;

/** Choose a HAL-advertised AE range for the requested capture rate. */
final class CameraFrameRatePolicy {
    private CameraFrameRatePolicy() {
    }

    /** Prefer the lowest ceiling that can reach the target, or the fastest available slower range. */
    static int selectIndex(int target, int[][] ranges) {
        if (target <= 0) {
            throw new IllegalArgumentException("Frame rate must be positive");
        }
        int best = -1;
        for (int i = 0; i < ranges.length; i++) {
            int lower = ranges[i][0], upper = ranges[i][1];
            if (lower <= 0 || upper < lower) {
                continue;
            }
            if (best < 0 || preferred(ranges[i], ranges[best], target)) {
                best = i;
            }
        }
        return best;
    }

    private static boolean preferred(int[] candidate, int[] current, int target) {
        int upper = candidate[1], bestUpper = current[1];
        if (upper != bestUpper) {
            if (upper < target || bestUpper < target) {
                return upper > bestUpper;
            }
            return upper < bestUpper;
        }
        // With the same ceiling, prefer a floor at or just below target, then the closest higher floor.
        int lower = candidate[0], bestLower = current[0];
        if (lower > target || bestLower > target) {
            return lower < bestLower;
        }
        return lower > bestLower;
    }
}
