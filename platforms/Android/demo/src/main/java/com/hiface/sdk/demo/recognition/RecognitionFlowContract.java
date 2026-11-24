package com.hiface.sdk.demo.recognition;

import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import androidx.annotation.Nullable;
import com.hiface.sdk.flow.FaceAction;
import com.hiface.sdk.flow.FaceFlowResult;
import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.List;

/** Demo navigation payloads contain IDs/options and display results; features stay in the store. */
public final class RecognitionFlowContract {
    public static final String FACE_ID = "recognition.faceId";
    public static final String ACTIONS = "recognition.actions";
    public static final String SILENT = "recognition.silent";
    public static final String MESSAGE = "recognition.result.message";
    public static final String STATUS = "recognition.result.status";
    // Optional full view of the SDK's terminal frame, including on business rejection.
    public static final String FRAME_JPEG = "recognition.result.frameJpeg";
    public static final String PASSED = "passed", REJECTED = "rejected", ERROR = "error", CANCELED = "canceled";
    // Leave room for concurrent transactions in Android's shared Binder buffer.
    private static final int MAX_RESULT_JPEG_BYTES = 256 * 1024;
    private static final int MAX_FRAME_SIDE = 720;

    private RecognitionFlowContract() {
    }

    public static Intent configure(Intent intent, List<FaceAction> actions, boolean silent) {
        String[] names = new String[actions.size()];
        for (int i = 0; i < actions.size(); i++) {
            names[i] = actions.get(i).name();
        }
        return intent.putExtra(ACTIONS, names).putExtra(SILENT, silent);
    }

    public static List<FaceAction> actions(Intent intent) {
        String[] names = intent.getStringArrayExtra(ACTIONS);
        List<FaceAction> actions = new ArrayList<>();
        if (names == null) {
            return actions;
        }
        if (names.length > 4) {
            throw new IllegalArgumentException("At most four actions are supported");
        }
        for (String name : names) {
            if (name == null) {
                throw new IllegalArgumentException("An action name is missing");
            }
            actions.add(FaceAction.valueOf(name));
        }
        return actions;
    }

    public static Intent result(String message, String status) {
        return new Intent().putExtra(MESSAGE, message).putExtra(STATUS, status);
    }

    /** A business outcome can carry an image even when the flow did not pass. */
    public static Intent result(String message, FaceFlowResult flow) {
        return result(message, flow.isPassed() ? PASSED : REJECTED, flow.getFrameJpeg());
    }

    static Intent result(String message, String status, @Nullable byte[] frameJpeg) {
        Intent data = result(message, status);
        byte[] preview = previewForResult(frameJpeg);
        if (preview != null) {
            data.putExtra(FRAME_JPEG, preview);
        }
        return data;
    }

    /** A missing or unreadable preview leaves the result text usable. */
    @Nullable
    static Bitmap readPreview(Intent data, int maxWidth, int maxHeight) {
        byte[] jpeg = data.getByteArrayExtra(FRAME_JPEG);
        if (jpeg == null || jpeg.length == 0 || jpeg.length > MAX_RESULT_JPEG_BYTES) {
            return null;
        }
        return decodeFrame(jpeg, maxWidth, maxHeight, 1);
    }

    /** Preserve the SDK JPEG when it fits. Sample large frames for the inline preview. */
    @Nullable
    private static byte[] previewForResult(@Nullable byte[] jpeg) {
        if (jpeg == null || jpeg.length == 0) {
            return null;
        }
        if (jpeg.length <= MAX_RESULT_JPEG_BYTES) {
            return jpeg;
        }
        Bitmap bitmap = decodeFrame(jpeg, MAX_FRAME_SIDE, MAX_FRAME_SIDE, 2);
        if (bitmap == null) {
            return null;
        }
        try {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            return bitmap.compress(Bitmap.CompressFormat.JPEG, 85, output)
                    && output.size() <= MAX_RESULT_JPEG_BYTES ? output.toByteArray() : null;
        } catch (RuntimeException | OutOfMemoryError ignored) {
            return null;
        } finally {
            bitmap.recycle();
        }
    }

    @Nullable
    private static Bitmap decodeFrame(byte[] jpeg, int maxWidth, int maxHeight, int minSampleSize) {
        try {
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inJustDecodeBounds = true;
            BitmapFactory.decodeByteArray(jpeg, 0, jpeg.length, options);
            if (options.outWidth <= 0 || options.outHeight <= 0
                    || options.outWidth > MAX_FRAME_SIDE || options.outHeight > MAX_FRAME_SIDE
                    || !"image/jpeg".equals(options.outMimeType)) {
                return null;
            }
            // JPEG sampling uses powers of two. Keep enough pixels for the fitted preview.
            float downscale = Math.max(options.outWidth / (float) maxWidth, options.outHeight / (float) maxHeight);
            int sampleSize = minSampleSize;
            int shortestSide = Math.min(options.outWidth, options.outHeight);
            while (sampleSize * 2 <= downscale && sampleSize * 2 <= shortestSide) {
                sampleSize *= 2;
            }
            options.inJustDecodeBounds = false;
            options.inSampleSize = sampleSize;
            return BitmapFactory.decodeByteArray(jpeg, 0, jpeg.length, options);
        } catch (RuntimeException | OutOfMemoryError ignored) {
            return null;
        }
    }
}
