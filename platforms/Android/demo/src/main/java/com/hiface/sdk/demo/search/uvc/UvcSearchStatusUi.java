package com.hiface.sdk.demo.search.uvc;

import android.content.Context;
import android.os.Handler;
import android.os.SystemClock;
import android.text.TextUtils;
import android.view.View;
import android.widget.TextView;
import androidx.annotation.StringRes;
import androidx.appcompat.app.AlertDialog;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.search.SearchUi;
import com.hiface.sdk.search.FaceSearchFace;
import com.hiface.sdk.search.FaceSearchFrame;
import com.hiface.sdk.search.FaceSearchProgress;
import com.hiface.sdk.search.FaceSearchResult;
import com.hiface.sdk.search.FaceSearchSessionConfig;
import com.hiface.sdk.search.InfraredSearchInfo;

/** Main-thread guidance and completed-sample display. 中文：展示快照不作为跨帧身份或放行状态。 */
final class UvcSearchStatusUi {
    private static final long RESULT_HOLD_MS = 1500, RESULT_REFRESH_MS = 500, STATUS_REFRESH_MS = 250;
    private final Context context;
    private final TextView status, resultView;
    private final Handler handler;
    private FaceSearchProgress.Stage stage = FaceSearchProgress.Stage.WAITING_FOR_FACE;
    private InfraredSearchInfo infrared;
    private boolean multipleFaces, resultIsMatch, waitingPair;
    private int successInterval;
    // Frame IDs reject late results; UI expiry/throttling use uptimeMillis, separate from capture timestamps.
    private long newestFrame = -1, invalidatedThrough = -1, resultDeadline, nextResultUpdate;
    private String fullResult, resultKey, pendingResult, pendingFullResult;
    @StringRes private int pendingStatus;
    private AlertDialog detailsDialog;

    private final Runnable renderStatus = this::publishStatus;
    private final Runnable renderResult = this::publishResult;
    private final Runnable expire = new Runnable() {
        @Override public void run() {
            long remaining = resultDeadline - SystemClock.uptimeMillis();
            if (remaining > 0) handler.postDelayed(this, remaining);
            else clearResult();
        }
    };

    UvcSearchStatusUi(View root, Handler handler) {
        context = root.getContext();
        this.handler = handler;
        status = root.findViewById(R.id.uvcStatus);
        resultView = root.findViewById(R.id.uvcResult);
        resultView.setOnClickListener(v -> showDetails());
        resultView.setClickable(false);
    }

    private void showDetails() {
        if (fullResult == null) return;
        TextView text = new TextView(context);
        int padding = (int) (24 * context.getResources().getDisplayMetrics().density);
        text.setPadding(padding, padding, padding, padding);
        // Freeze the opened sample so live updates do not interrupt reading or copying its ID.
        text.setText(fullResult);
        text.setTextIsSelectable(true);
        detailsDialog = new MaterialAlertDialogBuilder(context).setTitle(R.string.uvc_search_details)
                .setView(text).setPositiveButton(android.R.string.ok, null).show();
    }

    void config(FaceSearchSessionConfig config) {
        successInterval = config.getSearchIntervalMillis();
    }

    void camerasReady() {
        if (newestFrame < 0) setText(status, context.getString(R.string.uvc_search_waiting_pair));
    }

    void frame(FaceSearchFrame frame) {
        long frameId = frame.getFrameId();
        if (frameId < newestFrame || frameId <= invalidatedThrough) return;
        waitingPair = false;
        newestFrame = frameId;
        infrared = frame.getInfrared();
        // Preserve completed results across detections, but clear a success on face loss, missing pairs or IR rejection.
        if (frame.getFaces().isEmpty() || missingPair() || (resultIsMatch && invalidInfrared())) clearResult();
        render();
    }

    void progress(FaceSearchProgress progress) {
        if (waitingPair) return;
        stage = progress.getStage();
        multipleFaces = progress.getDetectedCount() > 1;
        if (stage == FaceSearchProgress.Stage.EMPTY_GALLERY || multipleFaces
                || progress.getDetectedCount() == 0
                || stage == FaceSearchProgress.Stage.FACE_TOO_SMALL) clearResult();
        render();
    }

    void result(FaceSearchResult result) {
        long frameId = result.getFrame().getFrameId();
        if (waitingPair || frameId < newestFrame || frameId <= invalidatedThrough
                || stage == FaceSearchProgress.Stage.EMPTY_GALLERY || multipleFaces) return;
        newestFrame = frameId;
        infrared = result.getFrame().getInfrared();
        if (result.getEndReason() == FaceSearchResult.EndReason.NO_FACE) {
            clearResult();
            render();
            return;
        }
        String text, key = result.getEndReason() + "/" + (infrared == null ? "" : infrared.getStatus());
        int hint = 0;
        FaceSearchFace match = confirmedMatch(result);
        if (match != null) {
            text = matchCaption(match, infrared);
            key = "match/" + match.getFaceId();
        } else if (result.getEndReason() == FaceSearchResult.EndReason.SPOOF_DETECTED
                || (infrared != null && infrared.getStatus() == InfraredSearchInfo.Status.REJECTED)) {
            text = context.getString(R.string.search_spoof);
            hint = R.string.uvc_search_ir_rejected_hint;
        } else if (infrared != null && infrared.isPassed()) {
            text = context.getString(R.string.search_ui_overlay_unmatched);
            hint = R.string.uvc_search_unmatched_hint;
        } else {
            text = context.getString(R.string.uvc_search_ir_unavailable);
            hint = infraredHint();
        }
        boolean first = fullResult == null;
        long now = SystemClock.uptimeMillis();
        resultDeadline = now + RESULT_HOLD_MS;
        pendingResult = text;
        pendingFullResult = resultDetails(result, text, match, hint);
        handler.removeCallbacks(renderResult);
        // Throttle scores for one identity to 500 ms; replace a changed identity/verdict immediately.
        if (!key.equals(resultKey) || now >= nextResultUpdate) renderResult.run();
        else handler.postAtTime(renderResult, nextResultUpdate);
        resultKey = key;
        resultIsMatch = match != null;
        if (first) handler.postDelayed(expire, RESULT_HOLD_MS);
        render();
    }

    /** Use the standard caption format with the same sample's IR score, never the RGB liveness score. */
    static String matchCaption(FaceSearchFace face, InfraredSearchInfo infrared) {
        return SearchUi.matchCaption(face.getFaceId(), face.getSimilarity(), infrared.getRealScore());
    }

    static FaceSearchFace confirmedMatch(FaceSearchResult result) {
        // Require identity and IR to pass in one result; caption and details share that confirmed face.
        FaceSearchFrame frame = result.getFrame();
        InfraredSearchInfo infrared = frame.getInfrared();
        if (result.getEndReason() != FaceSearchResult.EndReason.MATCH_FOUND
                || infrared == null || !infrared.isPassed()) return null;
        FaceSearchFace best = null;
        for (FaceSearchFace face : frame.getFaces())
            if (validMatch(face) && (best == null || face.getSimilarity() > best.getSimilarity())) best = face;
        return best;
    }

    private String resultDetails(FaceSearchResult result, String caption, FaceSearchFace match, @StringRes int hint) {
        FaceSearchFrame frame = result.getFrame();
        FaceSearchFace face = match != null ? match : frame.getFaces().isEmpty() ? null : frame.getFaces().get(0);
        String title = match != null ? context.getString(R.string.uvc_search_result_face_id, match.getFaceId()) : caption;
        InfraredSearchInfo info = frame.getInfrared();
        // Keep low/zero scores and mark unavailable values with —; a rejected candidate is never a match.
        return title + "\n" + context.getString(R.string.search_ui_overlay_similarity) + " "
                + detailScore(face == null ? null : face.getSimilarity()) + " · "
                + context.getString(R.string.search_ui_overlay_liveness) + " "
                + detailScore(info == null ? null : info.getRealScore())
                + (hint == 0 ? "" : "\n" + context.getString(hint));
    }

    private static boolean validMatch(FaceSearchFace face) {
        return face.isThresholdPassed() && face.getFaceId() != null
                && face.getSimilarity() != null && Float.isFinite(face.getSimilarity());
    }

    void clear() {
        clearResult();
        cancelStatus();
        if (detailsDialog != null) { detailsDialog.dismiss(); detailsDialog = null; }
        newestFrame = invalidatedThrough = -1;
        infrared = null;
        multipleFaces = waitingPair = false;
        stage = FaceSearchProgress.Stage.WAITING_FOR_FACE;
    }

    /** Keep the frame cutoff across pair loss so late terminal results cannot restore identity. */
    void waitingForPair() {
        clearResult();
        cancelStatus();
        waitingPair = true;
        invalidatedThrough = Math.max(invalidatedThrough, newestFrame);
        setText(status, context.getString(R.string.uvc_search_waiting_pair));
    }

    private void clearResult() {
        handler.removeCallbacks(expire);
        handler.removeCallbacks(renderResult);
        fullResult = resultKey = pendingResult = pendingFullResult = null;
        resultDeadline = nextResultUpdate = 0;
        resultIsMatch = false;
        String placeholder = context.getString(R.string.uvc_search_no_result);
        setText(resultView, placeholder);
        resultView.setContentDescription(placeholder);
        resultView.setClickable(false);
    }

    private void cancelStatus() {
        handler.removeCallbacks(renderStatus);
        pendingStatus = 0;
    }

    private void render() {
        int next = guidance();
        // Coalesce frame/progress guidance at 4 Hz; avoid rewriting identical text.
        if (TextUtils.equals(status.getText(), context.getText(next))) {
            cancelStatus();
        } else {
            if (pendingStatus == 0) handler.postDelayed(renderStatus, STATUS_REFRESH_MS);
            pendingStatus = next;
        }
    }

    @StringRes private int guidance() {
        // Prioritize the current blocker over the previous round's success interval.
        if (missingPair()) return R.string.uvc_search_waiting_pair;
        if (stage == FaceSearchProgress.Stage.EMPTY_GALLERY) return R.string.search_ui_empty_caption;
        if (multipleFaces) return R.string.capture_status_multiple_faces;
        if (stage == FaceSearchProgress.Stage.FACE_TOO_SMALL) return R.string.search_ui_move_closer;
        int hint = infraredHint();
        if (hint != 0) return hint;
        if (stage == FaceSearchProgress.Stage.SUCCESS_INTERVAL && successInterval > 0)
            return R.string.search_ui_interval_title;
        return stage == FaceSearchProgress.Stage.WAITING_FOR_FACE
                ? R.string.search_waiting : R.string.search_searching;
    }

    private void publishStatus() {
        int next = pendingStatus;
        pendingStatus = 0;
        if (next != 0) setText(status, context.getString(next));
    }

    private void publishResult() {
        if (pendingResult == null) return;
        if (SystemClock.uptimeMillis() >= resultDeadline) { clearResult(); return; }
        String text = pendingResult;
        fullResult = pendingFullResult;
        pendingResult = pendingFullResult = null;
        setText(resultView, text);
        resultView.setContentDescription(fullResult);
        resultView.setClickable(true);
        nextResultUpdate = SystemClock.uptimeMillis() + RESULT_REFRESH_MS;
    }

    private boolean invalidInfrared() {
        if (infrared == null) return false;
        return infrared.getStatus() != InfraredSearchInfo.Status.NOT_EVALUATED && !infrared.isPassed();
    }

    private boolean missingPair() {
        return infrared != null && (infrared.getStatus() == InfraredSearchInfo.Status.WAITING_PAIR
                || infrared.getStatus() == InfraredSearchInfo.Status.STALE_PAIR);
    }

    @StringRes private int infraredHint() {
        if (infrared == null) return 0;
        switch (infrared.getStatus()) {
            case WAITING_PAIR:
            case STALE_PAIR: return R.string.uvc_search_waiting_pair;
            case MULTIPLE_FACES: return R.string.capture_status_multiple_faces;
            case NO_FACE: return R.string.uvc_search_no_ir_face;
            case FACE_MISMATCH: return R.string.uvc_search_face_mismatch;
            case FACE_TOO_SMALL: return R.string.search_ui_move_closer;
            case REJECTED: return R.string.search_spoof;
            default: return 0;
        }
    }

    private static void setText(TextView view, String text) {
        if (!TextUtils.equals(view.getText(), text)) view.setText(text);
    }

    private static String detailScore(Float value) {
        return value == null ? "—" : SearchUi.formatScore(value);
    }
}
