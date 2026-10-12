package com.hiface.sdk.demo.detection;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.util.TypedValue;
import android.view.View;

import androidx.annotation.MainThread;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.hiface.sdk.detection.DetectedFace;
import com.hiface.sdk.detection.FaceDetectionResult;
import com.hiface.sdk.demo.ui.OutlinedOverlayText;

import java.util.Collections;
import java.util.List;

/** 检测结果到预览的绘制适配器；仅在主线程更新，复用绘制缓冲以减少逐帧分配。 */
public final class FaceDetectionOverlayView extends View {
    private static final float EYE_CONTOUR_SCALE = 1.4f;
    private static final float FACE_BOX_WIDTH_DP = 2.0f;
    private static final float LABEL_TEXT_SIZE_SP = 11.0f;
    private static final float MESH_CONTOUR_WIDTH_DP = 1.5f;
    private static final float MESH_HALO_WIDTH_DP = 3.0f;
    private static final float LANDMARK_RADIUS_DP = 2.2f;
    private static final int FACE_DETECTION_COLOR = Color.rgb(156, 39, 176);

    private final Matrix matrix = new Matrix();
    private final RectF faceRect = new RectF();
    private final float[] landmarkPointBuffer = new float[10];
    private final float[] meshPointBuffer =
            new float[DetectedFace.FaceMesh.COORDINATE_COUNT];
    private final float[] meshContourLineBuffer =
            new float[DetectedFace.FaceMesh.COORDINATE_COUNT * 2];
    private final StringBuilder faceLabelBuilder = new StringBuilder(96);

    private final float density;
    private final Paint faceBoxPaint;
    private final Paint landmarkPaint;
    private final Paint meshHaloPaint;
    private final Paint meshPaint;
    private final Paint labelFillPaint;
    private final Paint labelOutlinePaint;

    @NonNull
    private List<DetectedFace> faces = Collections.emptyList();

    // 只绘制嘴唇、双眼、脸部外轮廓和鼻部，明确排除两组眉毛连接。
    private static final int[][] FACE_CONTOUR_CONNECTION_GROUPS = {new int[]{61, 146, 146, 91, 91, 181, 181, 84, 84, 17, 17, 314, 314, 405, 405, 321, 321, 375, 375, 291, 61, 185, 185, 40, 40, 39, 39, 37, 37, 0, 0, 267, 267, 269, 269, 270, 270, 409, 409, 291, 78, 95, 95, 88, 88, 178, 178, 87, 87, 14, 14, 317, 317, 402, 402, 318, 318, 324, 324, 308, 78, 191, 191, 80, 80, 81, 81, 82, 82, 13, 13, 312, 312, 311, 311, 310, 310, 415, 415, 308}, new int[]{263, 249, 249, 390, 390, 373, 373, 374, 374, 380, 380, 381, 381, 382, 382, 362, 263, 466, 466, 388, 388, 387, 387, 386, 386, 385, 385, 384, 384, 398, 398, 362}, new int[]{33, 7, 7, 163, 163, 144, 144, 145, 145, 153, 153, 154, 154, 155, 155, 133, 33, 246, 246, 161, 161, 160, 160, 159, 159, 158, 158, 157, 157, 173, 173, 133}, new int[]{10, 338, 338, 297, 297, 332, 332, 284, 284, 251, 251, 389, 389, 356, 356, 454, 454, 323, 323, 361, 361, 288, 288, 397, 397, 365, 365, 379, 379, 378, 378, 400, 400, 377, 377, 152, 152, 148, 148, 176, 176, 149, 149, 150, 150, 136, 136, 172, 172, 58, 58, 132, 132, 93, 93, 234, 234, 127, 127, 162, 162, 21, 21, 54, 54, 103, 103, 67, 67, 109, 109, 10}, new int[]{168, 6, 6, 197, 197, 195, 195, 5, 5, 4, 4, 1, 1, 19, 19, 94, 94, 2, 98, 97, 97, 2, 2, 326, 326, 327}};

    public FaceDetectionOverlayView(@NonNull Context context) {
        this(context, null);
    }

    public FaceDetectionOverlayView(@NonNull Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
        density = getResources().getDisplayMetrics().density;
        faceBoxPaint = createPaint(FACE_DETECTION_COLOR, Paint.Style.STROKE);
        faceBoxPaint.setStrokeWidth(dp(FACE_BOX_WIDTH_DP));
        landmarkPaint = createPaint(FACE_DETECTION_COLOR, Paint.Style.FILL);
        meshHaloPaint = createMeshPaint(Color.rgb(0, 45, 52), 190, MESH_HALO_WIDTH_DP);
        meshPaint = createMeshPaint(Color.rgb(0, 188, 205), 255, MESH_CONTOUR_WIDTH_DP);
        labelFillPaint = OutlinedOverlayText.createFillPaint(sp(LABEL_TEXT_SIZE_SP), true);
        labelOutlinePaint = OutlinedOverlayText.createOutlinePaint(labelFillPaint, dp(3.0f));
    }

    @NonNull
    private static Paint createPaint(int color, @NonNull Paint.Style style) {
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(color);
        paint.setStyle(style);
        return paint;
    }

    private Paint createMeshPaint(int color, int alpha, float widthDp) {
        Paint paint = createPaint(color, Paint.Style.STROKE);
        paint.setAlpha(alpha);
        paint.setStrokeWidth(dp(widthDp));
        paint.setStrokeCap(Paint.Cap.ROUND);
        return paint;
    }

    private float dp(float value) {
        return density * value;
    }

    private float sp(float value) {
        return TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                value,
                getResources().getDisplayMetrics());
    }

    /** 将轮廓索引展开到复用的 drawLines 缓冲区；双眼轮廓适当放大以便观察。 */
    private int buildMeshContourLineBuffer(int meshPointCount) {
        int outputOffset = 0;
        for (int groupIndex = 0;
             groupIndex < FACE_CONTOUR_CONNECTION_GROUPS.length;
             groupIndex++) {
            int[] connections = FACE_CONTOUR_CONNECTION_GROUPS[groupIndex];
            boolean scaleEyeContour = groupIndex == 1 || groupIndex == 2;
            float eyeCenterX = 0.0f;
            float eyeCenterY = 0.0f;
            if (scaleEyeContour) {
                float minX = Float.POSITIVE_INFINITY;
                float minY = Float.POSITIVE_INFINITY;
                float maxX = Float.NEGATIVE_INFINITY;
                float maxY = Float.NEGATIVE_INFINITY;
                for (int pointIndex : connections) {
                    if (pointIndex < meshPointCount) {
                        int pointOffset = pointIndex * 2;
                        float pointX = meshPointBuffer[pointOffset];
                        float pointY = meshPointBuffer[pointOffset + 1];
                        minX = Math.min(minX, pointX);
                        minY = Math.min(minY, pointY);
                        maxX = Math.max(maxX, pointX);
                        maxY = Math.max(maxY, pointY);
                    }
                }
                scaleEyeContour = minX != Float.POSITIVE_INFINITY;
                eyeCenterX = (minX + maxX) * 0.5f;
                eyeCenterY = (minY + maxY) * 0.5f;
            }

            for (int index = 0; index < connections.length; index += 2) {
                int start = connections[index];
                int end = connections[index + 1];
                if (start >= meshPointCount || end >= meshPointCount) {
                    continue;
                }

                int startOffset = start * 2;
                int endOffset = end * 2;
                float startX = meshPointBuffer[startOffset];
                float startY = meshPointBuffer[startOffset + 1];
                float endX = meshPointBuffer[endOffset];
                float endY = meshPointBuffer[endOffset + 1];
                if (scaleEyeContour) {
                    startX = eyeCenterX + (startX - eyeCenterX) * EYE_CONTOUR_SCALE;
                    startY = eyeCenterY + (startY - eyeCenterY) * EYE_CONTOUR_SCALE;
                    endX = eyeCenterX + (endX - eyeCenterX) * EYE_CONTOUR_SCALE;
                    endY = eyeCenterY + (endY - eyeCenterY) * EYE_CONTOUR_SCALE;
                }

                meshContourLineBuffer[outputOffset++] = startX;
                meshContourLineBuffer[outputOffset++] = startY;
                meshContourLineBuffer[outputOffset++] = endX;
                meshContourLineBuffer[outputOffset++] = endY;
            }
        }
        return outputOffset;
    }

    /** 检测和搜索共用 CameraX 坐标变换；文字单独绘制，不随坐标镜像。 */
    @MainThread
    public void updateFaces(
            @NonNull FaceDetectionResult frameResult,
            @Nullable Matrix transform) {
        faces = transform == null ? Collections.emptyList() : frameResult.getFaces();
        if (transform != null) matrix.set(transform);
        postInvalidateOnAnimation();
    }

    @MainThread
    public void clear() {
        faces = Collections.emptyList();
        matrix.reset();
        faceLabelBuilder.setLength(0);
        invalidate();
    }

    @Override
    protected void onDetachedFromWindow() {
        clear();
        super.onDetachedFromWindow();
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);
        faces = Collections.emptyList();
    }

    @Override
    protected void onDraw(@NonNull Canvas canvas) {
        super.onDraw(canvas);
        for (DetectedFace face : faces) {
            drawFace(canvas, face);
        }
    }

    /**
     * 按“扩展检测框 → 信息标签 → 局部轮廓 → 五点”的顺序绘制一张人脸。
     * {@link DetectedFace} 中的坐标属于旋转后的检测图，绘制前统一通过 {@link #matrix} 映射到
     * 预览坐标。
     *
     * @param canvas 当前 View 的绘制画布
     * @param face 当前帧的一张不可变人脸结果
     */
    private void drawFace(@NonNull Canvas canvas, @NonNull DetectedFace face) {
        // 1. 以检测框中心为基准放大到 1.2 倍，再映射到预览坐标；结果同时供标签定位使用。
        float horizontalExpansion = face.getWidth() * (1.2f - 1.0f) * 0.5f;
        float verticalExpansion = face.getHeight() * (1.1f - 1.0f) * 0.5f;
        faceRect.set(
                face.getX() - horizontalExpansion,
                face.getY() + verticalExpansion/9,
                face.getX() + face.getWidth() + horizontalExpansion,
                face.getY() + face.getHeight() + verticalExpansion);
        matrix.mapRect(faceRect);
        canvas.drawRect(faceRect, faceBoxPaint);

        // 2. 在人脸框上方绘制置信度；有头姿结果时追加 pitch/yaw/roll。
        drawFaceLabel(canvas, face);

        // 3. 468 点有效时绘制双眼、鼻、嘴和脸部外轮廓；眉毛连接已从索引表排除。
        if (face.getMesh() != null) {
            drawMesh(canvas, face.getMesh());
        }

        // 4. 最后覆盖绘制检测模型的五点，使眼、鼻、嘴角位置在轮廓之上保持清晰。
        drawLandmarks(canvas, face.getLandmarks());
    }

    private void drawFaceLabel(@NonNull Canvas canvas, @NonNull DetectedFace face) {
        faceLabelBuilder.setLength(0);
        faceLabelBuilder.append(Math.round(face.getConfidence() * 100.0f))
                .append('%');
        DetectedFace.HeadPose pose = face.getHeadPose();
        if (pose != null) {
            faceLabelBuilder.append(",  P:  ").append(roundAngle(pose.getPitch()))
                    .append(",  Y:  ").append(roundAngle(pose.getYaw()))
                    .append(",  R:  ").append(roundAngle(pose.getRoll()));
        }
        float baseline = Math.max(
                labelFillPaint.getTextSize() + dp(6.0f),
                faceRect.top - dp(6.0f));
        drawLabel(canvas, faceLabelBuilder.toString(), faceRect.left, baseline);
    }

    /** 批量映射并绘制选定轮廓，避免逐点创建 PointF 或 Path。 */
    private void drawMesh(@NonNull Canvas canvas, @NonNull DetectedFace.FaceMesh mesh) {
        int pointCount = mesh.getPointCount();
        mesh.copyInterleavedTo(meshPointBuffer);
        int contourFloatCount = buildMeshContourLineBuffer(pointCount);
        matrix.mapPoints(
                meshContourLineBuffer,
                0,
                meshContourLineBuffer,
                0,
                contourFloatCount / 2);
        canvas.drawLines(meshContourLineBuffer, 0, contourFloatCount, meshHaloPaint);
        canvas.drawLines(meshContourLineBuffer, 0, contourFloatCount, meshPaint);
    }

    private void drawLandmarks(
            @NonNull Canvas canvas,
            @NonNull List<DetectedFace.PointF> landmarks
    ) {
        int pointCount = Math.min(5, landmarks.size());
        for (int index = 0; index < pointCount; index++) {
            DetectedFace.PointF point = landmarks.get(index);
            landmarkPointBuffer[index * 2] = point.getX();
            landmarkPointBuffer[index * 2 + 1] = point.getY();
        }
        matrix.mapPoints(landmarkPointBuffer, 0, landmarkPointBuffer, 0, pointCount);
        for (int index = 0; index < pointCount; index++) {
            canvas.drawCircle(
                    landmarkPointBuffer[index * 2],
                    landmarkPointBuffer[index * 2 + 1],
                    dp(LANDMARK_RADIUS_DP),
                    landmarkPaint);
        }
    }

    private static float roundAngle(float angle) {
        return Math.round(angle * 10.0f) / 10.0f;
    }

    private void drawLabel(Canvas canvas, String label, float left, float baseline) {
        OutlinedOverlayText.draw(
                canvas, label, left, baseline, labelFillPaint, labelOutlinePaint);
    }
}
