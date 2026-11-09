package com.hiface.sdk.demo.search.uvc;

/** Per-session admission policy, confined to UVC-pairs and a monotonic clock. 中文：无人脸待机节流。 */
final class UvcSearchIdlePolicy {
    // Share the preview watchdog gap; restart observation after a stream interruption.
    static final long PAIR_GAP_MS = 300;
    private static final long NO_FACE_IDLE_MS = 10_000;
    private static final long DETECTION_GAP_MS = 3_000;
    // Align with the SDK 200 ms probe interval; allow 2 ms slack between the two throttles.
    private static final long IDLE_PROBE_MIN_MS = 198;

    private long lastPairAt = -1;
    private long noFaceSince = -1;
    private long lastDetectionAt = -1;

    /** Exclude stream gaps from no-face time; keep probing while idle so new faces can wake capture. */
    boolean shouldAnalyze(long now) {
        if ((lastPairAt >= 0 && now - lastPairAt > PAIR_GAP_MS)
                || (lastDetectionAt >= 0 && now - lastDetectionAt >= DETECTION_GAP_MS)) reset();
        lastPairAt = now;
        return noFaceSince < 0 || now - lastDetectionAt >= IDLE_PROBE_MIN_MS;
    }

    /** Record successful RGB detections only; SDK throttling leaves the next pair eligible. */
    void onDetection(long now, boolean hasFace) {
        if (hasFace) {
            reset();
            return;
        }
        if (noFaceSince < 0) noFaceSince = now;
        lastDetectionAt = now;
    }

    boolean isIdle() { return noFaceSince >= 0 && lastDetectionAt - noFaceSince >= NO_FACE_IDLE_MS; }

    private void reset() {
        noFaceSince = -1;
        lastDetectionAt = -1;
    }
}
