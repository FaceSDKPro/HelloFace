package com.hiface.sdk.demo.ui;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;

import androidx.annotation.NonNull;

/** 相机 Overlay 共用的高对比文字：白色字形配深灰圆角描边，不遮挡人脸画面。 */
public final class OutlinedOverlayText {
    private static final int OUTLINE_COLOR = Color.argb(235, 24, 24, 24);

    private OutlinedOverlayText() {
    }

    @NonNull
    public static Paint createFillPaint(float textSize, boolean bold) {
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
        paint.setColor(Color.WHITE);
        paint.setStyle(Paint.Style.FILL);
        paint.setTextSize(textSize);
        paint.setFakeBoldText(bold);
        return paint;
    }

    @NonNull
    public static Paint createOutlinePaint(@NonNull Paint fillPaint, float strokeWidth) {
        Paint paint = new Paint(fillPaint);
        paint.setColor(OUTLINE_COLOR);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(strokeWidth);
        paint.setStrokeJoin(Paint.Join.ROUND);
        paint.setStrokeMiter(2.0f);
        return paint;
    }

    public static void draw(@NonNull Canvas canvas, @NonNull String text,
            float x, float baseline, @NonNull Paint fillPaint, @NonNull Paint outlinePaint) {
        if (text.isEmpty()) {
            return;
        }
        canvas.drawText(text, x, baseline, outlinePaint);
        canvas.drawText(text, x, baseline, fillPaint);
    }
}
