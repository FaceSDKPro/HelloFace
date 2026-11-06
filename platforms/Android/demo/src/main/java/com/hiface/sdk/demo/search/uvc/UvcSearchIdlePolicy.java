package com.hiface.sdk.demo.search.uvc;

/** 每次双目会话独立创建，仅在 UVC-pairs 线程使用，时间来自单调时钟。 */
final class UvcSearchIdlePolicy {
    // 与预览看门狗共用断流阈值，恢复配对时重新观察。
    static final long PAIR_GAP_MS = 300;
    private static final long NO_FACE_IDLE_MS = 10_000;
    // 对齐 SDK 的 200 ms 探测间隔，留 2 ms 容差以免两级节流错过同一拍。
    private static final long IDLE_PROBE_MIN_MS = 198;

    private long lastPairAt = -1;
    private long noFaceSince = -1;
    private long lastDetectionAt = -1;

    /** 断流不计入无人脸时间；待机也保留探测，供新入镜的人脸唤醒。 */
    boolean shouldAnalyze(long now) {
        if (lastPairAt >= 0 && now - lastPairAt > PAIR_GAP_MS) reset();
        lastPairAt = now;
        return !isIdle() || now - lastDetectionAt >= IDLE_PROBE_MIN_MS;
    }

    /** 只记录成功的 RGB 检测。SDK 节流或背压后，下一对帧仍可尝试探测。 */
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
