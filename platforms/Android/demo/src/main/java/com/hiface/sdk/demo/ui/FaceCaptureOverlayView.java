package com.hiface.sdk.demo.ui;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.text.TextPaint;
import android.text.TextUtils;
import android.util.AttributeSet;
import android.util.TypedValue;
import android.view.View;
import android.view.animation.LinearInterpolator;

import androidx.annotation.MainThread;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.StringRes;
import androidx.core.content.ContextCompat;

import com.hiface.sdk.demo.R;

/**
 * 圆形人脸预览遮罩，同时负责绘制采集状态和倒计时进度环。
 *
 * <p>CameraX 预览保持为铺满屏幕的高性能 Surface，本 View 在它上方绘制不透明背景，
 * 仅通过 EVEN_ODD Path 留出一个透明圆孔。这样无需直接裁剪 SurfaceView，能够避免部分旧设备
 * 出现矩形预览越过圆框的问题。</p>
 *
 * <p>进度变化时只申请刷新圆环附近的脏区，不创建 Bitmap，也不对相机帧做二次绘制。</p>
 */
public final class FaceCaptureOverlayView extends View {
    /** 未完成部分的半透明圆环颜色。 */
    private static final int TRACK_COLOR = 0x66FFFFFF;
    /** 倒计时剩余部分的高亮颜色。 */
    private static final int PROGRESS_COLOR = 0xFFF7F7F7;
    /** 进度环线宽：相对原 3.25dp / 4dp 缩小到 60%。 */
    private static final float TRACK_STROKE_WIDTH_DP = 1.95f;
    private static final float PROGRESS_STROKE_WIDTH_DP = 2.4f;

    /** 竖屏取宽高中短边的 80%，横屏取短边的 70%。 */
    private static final float PORTRAIT_CIRCLE_SHORT_SIDE_FRACTION = 0.8f;
    private static final float LANDSCAPE_CIRCLE_SHORT_SIDE_FRACTION = 0.7f;
    /** 竖屏适当上移；横屏居中，为圆上方的状态文字保留完整高度。 */
    private static final float PORTRAIT_CIRCLE_CENTER_Y_FRACTION = 0.43f;
    private static final float LANDSCAPE_CIRCLE_CENTER_Y_FRACTION = 0.5f;
    /** 将圆环稍微收进透明圆孔，避免抗锯齿边缘露出相机矩形。 */
    private static final float RING_INSET_DP = 3f;
    /** 进度刷新脏区额外留白，覆盖圆头和抗锯齿像素。 */
    private static final float INVALIDATE_PADDING_DP = 8f;
    /** 文字行框底部到圆环外边缘的固定距离。 */
    private static final float STATUS_TEXT_GAP_DP = 12f;
    private static final float STATUS_TEXT_HORIZONTAL_MARGIN_DP = 24f;
    private static final float STATUS_TEXT_SIZE_SP = 19f;

    /** 全屏矩形减去透明圆孔后形成的背景遮罩路径。 */
    private final Path maskPath = new Path();
    /** 相机可见圆孔的实际边界。 */
    private final RectF circleBounds = new RectF();
    /** 轨道和进度弧的绘制边界。 */
    private final RectF ringBounds = new RectF();
    private final Paint maskPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint trackPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint progressPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final TextPaint statusTextPaint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    private final float density;

    /** 剩余倒计时比例，1 为完整圆环，0 为倒计时结束。 */
    private float countdownProgress = 1f;
    private String statusText = "";
    /** 已按可用宽度省略的绘制文字，避免倒计时每帧重新分配字符串。 */
    private String displayedStatusText = "";
    private float statusTextBaseline;
    @Nullable
    private ValueAnimator countdownAnimator;

    public FaceCaptureOverlayView(@NonNull Context context) {
        this(context, null);
    }

    public FaceCaptureOverlayView(
            @NonNull Context context,
            @Nullable AttributeSet attrs) {
        super(context, attrs);
        density = getResources().getDisplayMetrics().density;
        maskPaint.setColor(ContextCompat.getColor(context, android.R.color.white));
        maskPaint.setStyle(Paint.Style.FILL);

        trackPaint.setColor(TRACK_COLOR);
        trackPaint.setStyle(Paint.Style.STROKE);
        trackPaint.setStrokeWidth(TRACK_STROKE_WIDTH_DP * density);

        progressPaint.setColor(PROGRESS_COLOR);
        progressPaint.setStyle(Paint.Style.STROKE);
        progressPaint.setStrokeCap(Paint.Cap.ROUND);
        progressPaint.setStrokeWidth(PROGRESS_STROKE_WIDTH_DP * density);

        statusTextPaint.setColor(ContextCompat.getColor(context, R.color.api_primary));
        statusTextPaint.setTextAlign(Paint.Align.CENTER);
        statusTextPaint.setTextSize(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                STATUS_TEXT_SIZE_SP,
                getResources().getDisplayMetrics()));
        statusTextPaint.setTypeface(Typeface.DEFAULT_BOLD);

        setAccessibilityLiveRegion(ACCESSIBILITY_LIVE_REGION_POLITE);
    }

    /**
     * 更新圆框上方的状态文字。此方法应与其他 View 更新一样在主线程调用。
     */
    @MainThread
    public void setStatusText(@NonNull String text) {
        if (TextUtils.equals(statusText, text)) {
            return;
        }
        statusText = text;
        setContentDescription(text);
        updateStatusTextLayout();
        invalidateStatusTextArea();
    }

    /** 使用字符串资源更新圆框上方的状态文字。 */
    @MainThread
    public void setStatusText(@StringRes int textResId) {
        setStatusText(getResources().getString(textResId));
    }

    /**
     * 更新剩余倒计时比例。
     *
     * @param progress 取值范围 0..1；超出范围时会自动截断
     */
    private void setCountdownProgress(float progress) {
        float clamped = Math.max(0f, Math.min(1f, progress));
        if (Math.abs(countdownProgress - clamped) < 0.001f) {
            return;
        }
        countdownProgress = clamped;

        // 动画期间仅刷新圆环区域，避免全屏背景参与每一帧无效重绘。
        int padding = (int) Math.ceil(INVALIDATE_PADDING_DP * density);
        postInvalidateOnAnimation(
                (int) circleBounds.left - padding,
                (int) circleBounds.top - padding,
                (int) circleBounds.right + padding,
                (int) circleBounds.bottom + padding);
    }

    /** 从完整圆环开始倒计时；重复调用会替换上一次动画。 */
    @MainThread
    public void startCountdown(long durationMillis) {
        cancelCountdown();
        setCountdownProgress(1f);
        countdownAnimator = ValueAnimator.ofFloat(1f, 0f);
        countdownAnimator.setDuration(durationMillis);
        countdownAnimator.setInterpolator(new LinearInterpolator());
        countdownAnimator.addUpdateListener(animation -> setCountdownProgress(
                (float) animation.getAnimatedValue()));
        countdownAnimator.start();
    }

    /** 若当前没有倒计时，则从完整圆环开始；用于跨多个动作保持同一个总倒计时。 */
    @MainThread
    public void startCountdownIfIdle(long durationMillis) {
        if (countdownAnimator == null) {
            startCountdown(durationMillis);
        }
    }

    /** 没有倒计时时恢复完整圆环，已有倒计时则保持其当前进度。 */
    @MainThread
    public void resetCountdownIfIdle() {
        if (countdownAnimator == null) {
            setCountdownProgress(1f);
        }
    }

    /** 取消动画并恢复为完整圆环。 */
    @MainThread
    public void resetCountdown() {
        cancelCountdown();
        setCountdownProgress(1f);
    }

    /** 取消动画并显示倒计时完成。 */
    @MainThread
    public void finishCountdown() {
        cancelCountdown();
        setCountdownProgress(0f);
    }

    /** 仅取消当前动画；可重复调用。 */
    private void cancelCountdown() {
        if (countdownAnimator != null) {
            countdownAnimator.cancel();
            countdownAnimator = null;
        }
    }

    @Override
    protected void onDetachedFromWindow() {
        cancelCountdown();
        super.onDetachedFromWindow();
    }

    @Override
    protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
        super.onSizeChanged(width, height, oldWidth, oldHeight);
        if (width <= 0 || height <= 0) {
            return;
        }

        float shortSide = Math.min(width, height);
        boolean portrait = height >= width;
        float diameter = shortSide * (portrait
                ? PORTRAIT_CIRCLE_SHORT_SIDE_FRACTION
                : LANDSCAPE_CIRCLE_SHORT_SIDE_FRACTION);
        float radius = diameter * 0.5f;
        float centerX = width * 0.5f;
        float centerY = height * (portrait
                ? PORTRAIT_CIRCLE_CENTER_Y_FRACTION
                : LANDSCAPE_CIRCLE_CENTER_Y_FRACTION);
        circleBounds.set(
                centerX - radius,
                centerY - radius,
                centerX + radius,
                centerY + radius);

        // Paint.Style.STROKE 会以边界为中心绘制，因此向内收缩后可让圆环完整落在遮罩内侧。
        ringBounds.set(circleBounds);
        float ringInset = RING_INSET_DP * density;
        ringBounds.inset(ringInset, ringInset);

        updateStatusTextLayout();

        // EVEN_ODD 规则会从全屏矩形中减去圆形，圆内保持透明并显示底层 CameraX 预览。
        maskPath.reset();
        maskPath.setFillType(Path.FillType.EVEN_ODD);
        maskPath.addRect(0f, 0f, width, height, Path.Direction.CW);
        maskPath.addCircle(centerX, centerY, radius, Path.Direction.CW);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (circleBounds.isEmpty()) {
            return;
        }

        canvas.drawPath(maskPath, maskPaint);
        canvas.drawOval(ringBounds, trackPaint);
        if (countdownProgress > 0f) {
            // 从正上方开始顺时针绘制，剩余比例从 1 递减到 0。
            canvas.drawArc(
                    ringBounds,
                    -90f,
                    360f * countdownProgress,
                    false,
                    progressPaint);
        }
        if (!displayedStatusText.isEmpty()) {
            canvas.drawText(
                    displayedStatusText,
                    circleBounds.centerX(),
                    statusTextBaseline,
                    statusTextPaint);
        }
    }

    /** 文字底部以最粗圆环的外边缘为基准，因此视觉间距始终为 12dp。 */
    private void updateStatusTextLayout() {
        if (getWidth() <= 0 || circleBounds.isEmpty()) {
            displayedStatusText = statusText;
            return;
        }
        float horizontalMargin = STATUS_TEXT_HORIZONTAL_MARGIN_DP * density;
        float availableWidth = Math.max(0f, getWidth() - horizontalMargin * 2f);
        displayedStatusText = TextUtils.ellipsize(
                statusText,
                statusTextPaint,
                availableWidth,
                TextUtils.TruncateAt.END).toString();

        float ringOuterTop = ringBounds.top - Math.max(
                trackPaint.getStrokeWidth(),
                progressPaint.getStrokeWidth()) * 0.5f;
        Paint.FontMetrics fontMetrics = statusTextPaint.getFontMetrics();
        statusTextBaseline = ringOuterTop
                - STATUS_TEXT_GAP_DP * density
                - fontMetrics.bottom;
    }

    private void invalidateStatusTextArea() {
        if (circleBounds.isEmpty()) {
            invalidate();
            return;
        }
        Paint.FontMetrics fontMetrics = statusTextPaint.getFontMetrics();
        float top = statusTextBaseline + fontMetrics.top;
        float bottom = statusTextBaseline + fontMetrics.bottom;
        int padding = (int) Math.ceil(INVALIDATE_PADDING_DP * density);
        postInvalidateOnAnimation(
                0,
                (int) Math.floor(top) - padding,
                getWidth(),
                (int) Math.ceil(bottom) + padding);
    }
}
