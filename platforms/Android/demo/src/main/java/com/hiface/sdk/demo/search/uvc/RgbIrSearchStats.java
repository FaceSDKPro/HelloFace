package com.hiface.sdk.demo.search.uvc;

import com.hiface.sdk.search.InfraredSearchInfo;
import java.util.Arrays;

/** UVC-pairs 写入送帧统计，主线程补充 IR 结果并读取快照；只保存数值和有界采样。 */
final class RgbIrSearchStats {
    enum Outcome { ACCEPTED, SKIPPED, ERROR, IDLE_SKIPPED }
    static final int WINDOW = 120;
    private final Samples skew = new Samples(), age = new Samples(), sdkDuration = new Samples();
    private long epoch, startedNanos, pairs, accepted, skipped, errors, idleSkipped;
    private long scored, unavailable;
    private boolean active;
    private InfraredSearchInfo latest;

    synchronized void start(long epoch, long nowNanos) {
        this.epoch = epoch;
        startedNanos = nowNanos;
        active = true;
        pairs = accepted = skipped = errors = idleSkipped = scored = unavailable = 0;
        latest = null;
        skew.clear();
        age.clear();
        sdkDuration.clear();
    }

    synchronized void stop(long epoch) { if (this.epoch == epoch) active = false; }
    synchronized boolean accepts(long epoch) { return active && this.epoch == epoch; }

    synchronized void pair(long epoch, long rgbNanos, long irNanos, long nowNanos, long durationNanos, Outcome outcome) {
        if (!accepts(epoch)) return;
        ++pairs;
        // 到达时间与提交时间使用同一单调时钟；异常时间不参与延迟统计。
        if (rgbNanos >= 0 && irNanos >= 0 && nowNanos >= rgbNanos && nowNanos >= irNanos) {
            skew.add(Math.abs(rgbNanos - irNanos) / 1e6);
            age.add((nowNanos - Math.min(rgbNanos, irNanos)) / 1e6);
        }
        if (durationNanos >= 0) sdkDuration.add(durationNanos / 1e6);
        switch (outcome) {
            case ACCEPTED: ++accepted; break;
            case SKIPPED: ++skipped; break;
            case ERROR: ++errors; break;
            case IDLE_SKIPPED: ++idleSkipped; break;
        }
    }

    synchronized void core(long epoch, InfraredSearchInfo info) {
        if (!accepts(epoch) || info == null) return;
        // onFrame/onResult 可能指向同一帧对，只计数一次，同时保留最终耗时。
        boolean sameSource = latest != null && latest.getSourceId() == info.getSourceId();
        if (sameSource && info.getPairId() < latest.getPairId()) return;
        if (!sameSource || info.getPairId() != latest.getPairId()) {
            if (info.getRealScore() != null) ++scored;
            else if (info.getStatus() != InfraredSearchInfo.Status.NOT_EVALUATED) ++unavailable;
        }
        latest = info;
    }

    synchronized Snapshot snapshot(long nowNanos) {
        return new Snapshot(pairs, accepted, skipped, errors, idleSkipped, scored, unavailable,
                nowNanos > startedNanos ? pairs * 1e9 / (nowNanos - startedNanos) : 0,
                skew.snapshot(), age.snapshot(), sdkDuration.snapshot(), latest);
    }

    static final class Snapshot {
        final long pairs, accepted, skipped, errors, idleSkipped, scored, unavailable;
        final double pairsPerSecond;
        final Summary skew, age, sdk;
        final InfraredSearchInfo latest;

        Snapshot(long pairs, long accepted, long skipped, long errors, long idleSkipped, long scored, long unavailable,
                double rate, Summary skew, Summary age, Summary sdk, InfraredSearchInfo latest) {
            this.pairs = pairs;
            this.accepted = accepted;
            this.skipped = skipped;
            this.errors = errors;
            this.idleSkipped = idleSkipped;
            this.scored = scored;
            this.unavailable = unavailable;
            pairsPerSecond = rate;
            this.skew = skew;
            this.age = age;
            this.sdk = sdk;
            this.latest = latest;
        }
    }

    static final class Summary {
        final int count;
        final double mean, p95, max;

        Summary(int count, double mean, double p95, double max) {
            this.count = count;
            this.mean = mean;
            this.p95 = p95;
            this.max = max;
        }
    }

    private static final class Samples {
        private final double[] values = new double[WINDOW];
        private int count, next;

        void clear() { count = next = 0; }

        void add(double value) {
            values[next] = value;
            next = (next + 1) % WINDOW;
            count = Math.min(WINDOW, count + 1);
        }

        Summary snapshot() {
            if (count == 0) return new Summary(0, 0, 0, 0);
            // 排序副本，避免主线程读取统计时改变环形采样顺序。
            double[] sorted = Arrays.copyOf(values, count);
            Arrays.sort(sorted);
            double sum = 0;
            for (double value : sorted) sum += value;
            return new Summary(count, sum / count, sorted[(int) Math.ceil(count * .95) - 1], sorted[count - 1]);
        }
    }
}
