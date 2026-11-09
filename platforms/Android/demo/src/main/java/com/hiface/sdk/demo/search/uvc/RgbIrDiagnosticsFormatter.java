package com.hiface.sdk.demo.search.uvc;

import android.content.Context;
import com.facesdkpro.uvccamera.PairingDiagnostics;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.search.InfraredSearchDiagnostics;
import com.hiface.sdk.search.InfraredSearchInfo;
import java.util.Locale;

/** Formats numeric snapshots without accessing cameras or retaining images. 中文：仅生成调试文案。 */
final class RgbIrDiagnosticsFormatter {
    private RgbIrDiagnosticsFormatter() {}

    static String format(Context context, RgbIrSearchStats.Snapshot stats, PairingDiagnostics pairing) {
        String pairingText = pairing == null ? "—" : context.getString(R.string.uvc_debug_pairing,
                pairing.state.name(), pairing.rgbFrames, pairing.irFrames, pairing.dispatchedPairs,
                pairing.replacedRgb + pairing.replacedIr, pairing.expiredRgb + pairing.expiredIr,
                pairing.skewRgb + pairing.skewIr, pairing.outOfOrderRgb + pairing.outOfOrderIr,
                pairing.lastConsumerDurationNanos / 1e6, pairing.maxConsumerDurationNanos / 1e6);
        InfraredSearchInfo info = stats.latest;
        return context.getString(R.string.uvc_debug_summary, stats.pairsPerSecond,
                stats.pairs, stats.accepted, stats.skipped, stats.errors, stats.scored, stats.unavailable,
                summary(stats.skew), summary(stats.age), summary(stats.sdk), pairingText,
                info == null ? "—" : Long.toString(info.getPairId()),
                info == null ? "—" : info.getStatus().name(),
                timing(info, InfraredSearchDiagnostics.Stage.RGB_DETECTION),
                timing(info, InfraredSearchDiagnostics.Stage.IR_PREPARATION),
                timing(info, InfraredSearchDiagnostics.Stage.IR_DETECTION),
                timing(info, InfraredSearchDiagnostics.Stage.IR_LIVENESS),
                timing(info, InfraredSearchDiagnostics.Stage.FEATURE),
                timing(info, InfraredSearchDiagnostics.Stage.LOOKUP), stats.idleSkipped);
    }

    private static String summary(RgbIrSearchStats.Summary sample) {
        return sample.count == 0 ? "—" : String.format(Locale.ROOT, "%.1f / %.1f / %.1f ms (n=%d)",
                sample.mean, sample.p95, sample.max, sample.count);
    }

    private static String timing(InfraredSearchInfo info, InfraredSearchDiagnostics.Stage stage) {
        Long micros = info == null ? null : info.getDiagnostics().getDurationMicros(stage);
        return micros == null ? "—" : String.format(Locale.ROOT, "%.3f", micros / 1000.0);
    }
}
