package com.hiface.sdk.demo.camera;

/** 只选择 HAL 上报的 AE 档位；低帧率不支持时仍尽量降低采集上限，Analyzer 单独限流。 */
final class CameraFrameRatePolicy {
    private CameraFrameRatePolicy() {}

    /** ranges 每项为 [lower, upper]；优先兼容目标的窄范围，回退最低可用上限或全部较慢时的最快档。 */
    static int selectIndex(int target, int[][] ranges) {
        if (target <= 0) throw new IllegalArgumentException("Frame rate must be positive");
        int compatible = -1, above = -1, below = -1;
        for (int i = 0; i < ranges.length; i++) {
            int lower = ranges[i][0], upper = ranges[i][1];
            if (lower <= 0 || upper < lower) continue;
            if (lower <= target && upper >= target
                    && (compatible < 0 || narrower(ranges[i], ranges[compatible]))) compatible = i;
            if (upper >= target && (above < 0 || narrower(ranges[i], ranges[above]))) above = i;
            if (upper < target && (below < 0 || upper > ranges[below][1]
                    || (upper == ranges[below][1] && lower > ranges[below][0]))) below = i;
        }
        return compatible >= 0 ? compatible : above >= 0 ? above : below;
    }

    private static boolean narrower(int[] candidate, int[] current) {
        return candidate[1] < current[1]
                || (candidate[1] == current[1] && candidate[0] > current[0]);
    }
}
