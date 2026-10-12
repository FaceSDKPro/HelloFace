package com.hiface.sdk.demo.comparison;

import android.content.ContentResolver;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ImageDecoder;
import android.graphics.Matrix;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.PickVisualMediaRequest;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.MainThread;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.appcompat.app.AppCompatActivity;

import java.io.IOException;
import java.io.InputStream;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

/** 系统图片选择与轻量预处理：工作线程解码，主线程交付最长边不超过 1080px 的 Bitmap。 */
final class FacePhotoPicker implements AutoCloseable {
    private static final int MAX_DIMENSION_PX = 1080;

    private final ContentResolver resolver;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor(runnable -> {
        Thread thread = new Thread(runnable, "HiFaceDemo-PhotoPicker");
        thread.setDaemon(true);
        return thread;
    });
    private final ActivityResultLauncher<PickVisualMediaRequest> launcher;

    @Nullable
    private Callback pendingCallback;
    private int requestVersion;
    private boolean closed;

    @FunctionalInterface
    interface Callback {
        void onPicked(@NonNull Bitmap bitmap);

        default void onError(@NonNull Throwable error) {
        }
    }

    FacePhotoPicker(@NonNull AppCompatActivity activity) {
        resolver = activity.getContentResolver();
        launcher = activity.registerForActivityResult(
                new ActivityResultContracts.PickVisualMedia(),
                this::handlePickerResult);
    }

    /** 打开系统图片选择器；连续调用时只交付最后一次请求。 */
    @MainThread
    void pick(@NonNull Callback callback) {
        Objects.requireNonNull(callback, "callback");
        if (closed) {
            callback.onError(new IllegalStateException("FacePhotoPicker is closed"));
            return;
        }

        pendingCallback = callback;
        requestVersion++;
        launcher.launch(new PickVisualMediaRequest.Builder()
                .setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly.INSTANCE)
                .build());
    }

    @MainThread
    private void handlePickerResult(@Nullable Uri uri) {
        Callback callback = pendingCallback;
        int version = requestVersion;
        if (callback == null || closed) {
            return;
        }
        if (uri == null) {
            pendingCallback = null;
            return;
        }

        try {
            executor.execute(() -> decodeInBackground(uri, version, callback));
        } catch (RejectedExecutionException error) {
            deliver(version, callback, null, error);
        }
    }

    private void decodeInBackground(
            @NonNull Uri uri,
            int version,
            @NonNull Callback callback) {
        try {
            Bitmap bitmap = decode(uri);
            if (!mainHandler.post(() -> deliver(version, callback, bitmap, null))) {
                recycle(bitmap);
            }
        } catch (Exception | OutOfMemoryError error) {
            mainHandler.post(() -> deliver(version, callback, null, error));
        }
    }

    @MainThread
    private void deliver(
            int version,
            @NonNull Callback callback,
            @Nullable Bitmap bitmap,
            @Nullable Throwable error) {
        if (closed || version != requestVersion || callback != pendingCallback) {
            recycle(bitmap);
            return;
        }

        pendingCallback = null;
        if (bitmap != null) {
            callback.onPicked(bitmap);
        } else {
            callback.onError(error != null ? error : new IOException("Unable to read photo"));
        }
    }

    /** 解码方向正确的软件 Bitmap，并限制尺寸和像素格式；不做无用途的 JPEG 再编码。 */
    @NonNull
    private Bitmap decode(@NonNull Uri uri) throws IOException {
        Bitmap decoded = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ? Api28Impl.decode(resolver, uri)
                : decodeWithBitmapFactory(uri);
        if (decoded == null) {
            throw new IOException("Unsupported or damaged image");
        }

        Bitmap normalized = null;
        try {
            normalized = normalize(decoded);
            return normalized;
        } finally {
            if (normalized != decoded) recycle(decoded);
        }
    }

    /** API 26-27 使用 BitmapFactory，并读取媒体库方向字段。 */
    @Nullable
    private Bitmap decodeWithBitmapFactory(@NonNull Uri uri) throws IOException {
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        try (InputStream input = open(uri)) {
            BitmapFactory.decodeStream(input, null, bounds);
        }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw new IOException("Unsupported or damaged image");
        }

        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inPreferredConfig = Bitmap.Config.ARGB_8888;
        options.inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight);
        Bitmap bitmap;
        try (InputStream input = open(uri)) {
            bitmap = BitmapFactory.decodeStream(input, null, options);
        }
        return rotate(bitmap, queryOrientation(uri));
    }

    @NonNull
    private InputStream open(@NonNull Uri uri) throws IOException {
        InputStream input = resolver.openInputStream(uri);
        if (input == null) {
            throw new IOException("Unable to open selected image");
        }
        return input;
    }

    private int queryOrientation(@NonNull Uri uri) {
        String column = MediaStore.Images.ImageColumns.ORIENTATION;
        try (Cursor cursor = resolver.query(uri, new String[]{column}, null, null, null)) {
            if (cursor == null || !cursor.moveToFirst()) {
                return 0;
            }
            int columnIndex = cursor.getColumnIndex(column);
            return columnIndex >= 0 ? cursor.getInt(columnIndex) : 0;
        } catch (RuntimeException ignored) {
            return 0;
        }
    }

    @Nullable
    private static Bitmap rotate(@Nullable Bitmap source, int degrees) {
        if (source == null || degrees % 360 == 0) {
            return source;
        }
        Matrix matrix = new Matrix();
        matrix.postRotate(degrees);
        Bitmap rotated = null;
        try {
            rotated = Bitmap.createBitmap(
                    source, 0, 0, source.getWidth(), source.getHeight(), matrix, true);
            return rotated;
        } finally {
            if (rotated != source) recycle(source);
        }
    }

    private static int sampleSize(int width, int height) {
        int sample = 1;
        while (Math.max(width, height) / (sample * 2) >= MAX_DIMENSION_PX) {
            sample *= 2;
        }
        return sample;
    }

    /** 限制最长边并统一为 SDK 可直接读取的 ARGB_8888 偶数尺寸。 */
    @NonNull
    private static Bitmap normalize(@NonNull Bitmap source) {
        int width = source.getWidth();
        int height = source.getHeight();
        float scale = Math.min(1f, (float) MAX_DIMENSION_PX / Math.max(width, height));
        int targetWidth = evenSize(Math.round(width * scale));
        int targetHeight = evenSize(Math.round(height * scale));
        if (targetWidth == width
                && targetHeight == height
                && source.getConfig() == Bitmap.Config.ARGB_8888) {
            return source;
        }

        Bitmap resized = Bitmap.createScaledBitmap(source, targetWidth, targetHeight, true);
        if (resized.getConfig() == Bitmap.Config.ARGB_8888) {
            return resized;
        }
        Bitmap argb;
        try {
            argb = resized.copy(Bitmap.Config.ARGB_8888, false);
        } finally {
            if (resized != source) recycle(resized);
        }
        if (argb == null) {
            throw new IllegalStateException("Unable to create ARGB bitmap");
        }
        return argb;
    }

    private static int evenSize(int value) {
        int safeValue = Math.max(2, value);
        return (safeValue & 1) == 0 ? safeValue : safeValue - 1;
    }

    private static void recycle(@Nullable Bitmap bitmap) {
        if (bitmap != null && !bitmap.isRecycled()) {
            bitmap.recycle();
        }
    }

    /** 注解隔离 API 28 的 ImageDecoder 调用，避免旧系统类校验失败。 */
    @RequiresApi(Build.VERSION_CODES.P)
    private static final class Api28Impl {
        private Api28Impl() {}

        @NonNull
        static Bitmap decode(
                @NonNull ContentResolver resolver,
                @NonNull Uri uri) throws IOException {
            ImageDecoder.Source source = ImageDecoder.createSource(resolver, uri);
            return ImageDecoder.decodeBitmap(source, (decoder, info, ignored) -> {
                int width = info.getSize().getWidth();
                int height = info.getSize().getHeight();
                float scale = Math.min(
                        1f,
                        (float) MAX_DIMENSION_PX / Math.max(width, height));
                decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
                if (scale < 1f) {
                    decoder.setTargetSize(
                            evenSize(Math.round(width * scale)),
                            evenSize(Math.round(height * scale)));
                }
            });
        }
    }

    /** 取消待返回结果并停止图片工作线程。 */
    @MainThread
    @Override
    public void close() {
        if (closed) {
            return;
        }
        closed = true;
        requestVersion++;
        pendingCallback = null;
        launcher.unregister();
        executor.shutdownNow();
        // 已投递的结果仍需进入 deliver；它会看到 closed 并释放刚解码出的 Bitmap。
    }
}
