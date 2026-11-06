package com.hiface.sdk.demo.search.uvc;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.AttributeSet;
import android.view.View;
import com.hiface.sdk.search.FaceSearchFace;
import com.hiface.sdk.search.InfraredSearchDiagnostics;
import com.hiface.sdk.search.InfraredSearchInfo;

/** Last analyzed IR box on the live IR preview; no tracking or identity association. */
public final class InfraredDebugOverlayView extends View {
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private InfraredSearchInfo sample;
    private final Runnable expiry = () -> { sample = null; invalidate(); };
    public InfraredDebugOverlayView(Context context, AttributeSet attrs) { super(context, attrs); }
    void show(InfraredSearchInfo info) {
        removeCallbacks(expiry);
        sample = info;
        invalidate();
        if (sample != null) postDelayed(expiry, 300);
    }
    @Override protected void onDetachedFromWindow() {
        show(null); super.onDetachedFromWindow();
    }
    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (sample == null || sample.getFaceBounds() == null) return;
        InfraredSearchDiagnostics d = sample.getDiagnostics();
        if (d.getImageWidth() <= 0 || d.getImageHeight() <= 0) return;
        float scale = Math.min((float) getWidth() / d.getImageWidth(), (float) getHeight() / d.getImageHeight());
        float dx = (getWidth() - d.getImageWidth() * scale) / 2, dy = (getHeight() - d.getImageHeight() * scale) / 2;
        FaceSearchFace.Bounds b = sample.getFaceBounds();
        paint.setColor(sample.isPassed() ? Color.GREEN : Color.YELLOW);
        paint.setStyle(Paint.Style.STROKE); paint.setStrokeWidth(2 * getResources().getDisplayMetrics().density);
        canvas.drawRect(dx + b.getX() * scale, dy + b.getY() * scale,
                dx + (b.getX() + b.getWidth()) * scale, dy + (b.getY() + b.getHeight()) * scale, paint);
        paint.setStyle(Paint.Style.FILL); paint.setTextSize(12 * getResources().getDisplayMetrics().scaledDensity);
        canvas.drawText("IR #" + sample.getPairId(), 6, paint.getTextSize() + 4, paint);
    }
}
