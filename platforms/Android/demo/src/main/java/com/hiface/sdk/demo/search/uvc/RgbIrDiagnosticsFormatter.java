package com.hiface.sdk.demo.search.uvc;

import android.content.Context;
import com.facesdkpro.uvccamera.PairingDiagnostics;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.search.InfraredSearchDiagnostics;
import com.hiface.sdk.search.InfraredSearchInfo;
import java.util.Locale;

/** Formats only numeric diagnostics; image buffers, feature vectors and identity never enter this panel. */
final class RgbIrDiagnosticsFormatter {
    private RgbIrDiagnosticsFormatter() {}
    static String format(Context context, RgbIrSearchStats.Snapshot s, PairingDiagnostics p) {
        String pairing = p == null ? "—" : context.getString(R.string.uvc_debug_pairing,
                p.state.name(), p.rgbFrames, p.irFrames, p.dispatchedPairs,
                p.replacedRgb + p.replacedIr, p.expiredRgb + p.expiredIr,
                p.skewRgb + p.skewIr, p.outOfOrderRgb + p.outOfOrderIr,
                p.lastConsumerDurationNanos / 1e6, p.maxConsumerDurationNanos / 1e6);
        InfraredSearchInfo info = s.latest;
        return context.getString(R.string.uvc_debug_summary, s.pairsPerSecond,
                s.pairs, s.accepted, s.skipped, s.errors, s.scored, s.unavailable,
                summary(s.skew), summary(s.age), summary(s.sdk), pairing,
                info == null ? "—" : Long.toString(info.getPairId()),
                info == null ? "—" : info.getStatus().name(),
                timing(info, InfraredSearchDiagnostics.Stage.RGB_DETECTION),
                timing(info, InfraredSearchDiagnostics.Stage.IR_PREPARATION),
                timing(info, InfraredSearchDiagnostics.Stage.IR_DETECTION),
                timing(info, InfraredSearchDiagnostics.Stage.IR_LIVENESS),
                timing(info, InfraredSearchDiagnostics.Stage.FEATURE),
                timing(info, InfraredSearchDiagnostics.Stage.LOOKUP), s.idleSkipped);
    }
    private static String summary(RgbIrSearchStats.Summary s) {
        return s.count == 0 ? "—" : String.format(Locale.ROOT, "%.1f / %.1f / %.1f ms (n=%d)", s.mean, s.p95, s.max, s.count);
    }
    private static String timing(InfraredSearchInfo info, InfraredSearchDiagnostics.Stage stage) {
        Long us = info == null ? null : info.getDiagnostics().getDurationMicros(stage);
        return us == null ? "—" : String.format(Locale.ROOT, "%.3f", us / 1000.0);
    }
}
