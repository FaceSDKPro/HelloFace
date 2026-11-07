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

/** 实时引导与最近一次完整采样分开展示；短暂保留的是展示快照，不是跨帧身份或放行状态。 */
final class UvcSearchStatusUi {
    private static final long RESULT_HOLD_MS = 1500, RESULT_REFRESH_MS = 500, STATUS_REFRESH_MS = 250;
    private final Context context;
    private final TextView status, resultView;
    private final Handler handler;
    private FaceSearchProgress.Stage stage = FaceSearchProgress.Stage.WAITING_FOR_FACE;
    private InfraredSearchInfo infrared;
    private boolean multipleFaces, resultIsMatch, waitingPair;
    private int successInterval;
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
        // 固定打开时的完整采样；后续刷新不打断阅读或复制长 ID。
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
        // 新检测帧不再清空完整结果；离人、缺帧或 IR 拒绝时立即清除旧成功快照。
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
        // 同一身份的分数最多每 500ms 更新；新身份或新结论立即替换，不先隐藏再显示。
        if (!key.equals(resultKey) || now >= nextResultUpdate) renderResult.run();
        else handler.postAtTime(renderResult, nextResultUpdate);
        resultKey = key;
        resultIsMatch = match != null;
        if (first) handler.postDelayed(expire, RESULT_HOLD_MS);
        render();
    }

    static boolean recognized(FaceSearchResult result) {
        return confirmedMatch(result) != null;
    }

    /** 与普通搜索页采用相同摘要语法；Liveness 始终取同一结果的 IR 分数，不读取 RGB 活体分数。 */
    static String matchCaption(FaceSearchResult result) {
        FaceSearchFace match = confirmedMatch(result);
        return match == null ? "" : matchCaption(match, result.getFrame().getInfrared());
    }

    private static String matchCaption(FaceSearchFace face, InfraredSearchInfo infrared) {
        return SearchUi.matchCaption(face.getFaceId(), face.getSimilarity(), infrared.getRealScore());
    }

    private static FaceSearchFace confirmedMatch(FaceSearchResult result) {
        // 身份和红外活体必须在同一结果里通过，摘要和详情共用该人脸。
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
        // 低相似度与 0 分均按原样显示；未执行用 —，活体拒绝不展示候选身份为识别成功。
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

    /** 配对中断保留帧号边界，迟到的旧终态不能重新显示身份。 */
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
        // 合并 frame/progress 的中间状态；实时引导最多 4Hz，文本相同不重复 setText。
        if (TextUtils.equals(status.getText(), context.getText(next))) {
            cancelStatus();
        } else {
            if (pendingStatus == 0) handler.postDelayed(renderStatus, STATUS_REFRESH_MS);
            pendingStatus = next;
        }
    }

    @StringRes private int guidance() {
        // 优先提示当前阻塞原因。上一轮的搜索间隔不能盖住本帧的配对或红外问题。
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
