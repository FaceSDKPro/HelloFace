package com.hiface.sdk.demo.search;

/** 延长期限时保留较早的检查，只有提前到期或清空画面才替换任务。 */
final class FaceSearchOverlayExpirySchedule {
    private long deadline;

    boolean update(long value) {
        if (deadline == value || (deadline != 0 && value >= deadline)) return false;
        deadline = value;
        return true;
    }

    void reset() { deadline = 0; }
}
