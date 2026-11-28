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
import androidx.exifinterface.media.ExifInterface;
import java.io.IOException;
import java.io.InputStream;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

/**
 * System photo selection and preprocessing: decode in the background for the intended use; image
 * search preserves original resolution within SDK limits.
 *
 * 系统图片选择与预处理：后台按用途解码，图片搜索保留 SDK 上限内的原始分辨率。
 */
public final class FacePhotoPicker implements AutoCloseable {
    private static final int DEFAULT_MAX_DIMENSION_PX = 1080;
    public static final int IMAGE_SEARCH_MAX_DIMENSION_PX = 4096;
    // Longest decoded side in pixels; each caller chooses its own memory/quality limit.
    private final int maximumDimension;

    private final ContentResolver resolver;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor(runnable -> {
        Thread thread = new Thread(runnable, "HiFaceDemo-PhotoPicker");
        thread.setDaemon(true);
        return thread;
    });
    private final ActivityResultLauncher<PickVisualMediaRequest> launcher;

    // Main thread only. The system returns a URI without identifying which photo slot launched it.
    @Nullable
    private Callback pendingCallback;
    private boolean closed;

    @FunctionalInterface
    public interface Callback {
        // The recipient owns the decoded Bitmap and releases it after its last use.
        void onPicked(@NonNull Bitmap bitmap);

        default void onCanceled() {
        }

        default void onError(@NonNull Throwable error) {
        }
    }

    public FacePhotoPicker(@NonNull AppCompatActivity activity) {
        this(activity, DEFAULT_MAX_DIMENSION_PX);
    }

    public FacePhotoPicker(@NonNull AppCompatActivity activity, int maximumDimension) {
        if (maximumDimension < 2 || maximumDimension > IMAGE_SEARCH_MAX_DIMENSION_PX) {
            throw new IllegalArgumentException("Image limit must be within 2..4096");
        }
        this.maximumDimension = maximumDimension;
        resolver = activity.getContentResolver();
        launcher = activity.registerForActivityResult(
                new ActivityResultContracts.PickVisualMedia(),
                this::handlePickerResult);
    }

    /**
     * Admit one system picker at a time. Once it returns, its decode keeps the original callback
     * and another slot can open the picker. The single worker delivers photos in selection order.
     */
    @MainThread
    public void pick(@NonNull Callback callback) {
        Objects.requireNonNull(callback, "callback");
        if (closed) {
            callback.onError(new IllegalStateException("FacePhotoPicker is closed"));
            return;
        }

        if (pendingCallback != null) {
            return;
        }
        pendingCallback = callback;
        try {
            launcher.launch(new PickVisualMediaRequest.Builder()
                    .setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly.INSTANCE)
                    .build());
        } catch (RuntimeException error) {
            pendingCallback = null;
            callback.onError(error);
        }
    }

    @MainThread
    private void handlePickerResult(@Nullable Uri uri) {
        Callback callback = pendingCallback;
        pendingCallback = null;
        if (callback == null || closed) {
            return;
        }
        if (uri == null) {
            callback.onCanceled();
            return;
        }

        try {
            executor.execute(() -> decodeInBackground(uri, callback));
        } catch (RejectedExecutionException error) {
            callback.onError(error);
        }
    }

    // Keep provider I/O and image allocation off the main thread, then transfer the result to the UI.
    private void decodeInBackground(
            @NonNull Uri uri,
            @NonNull Callback callback) {
        try {
            Bitmap bitmap = decode(resolver, uri, maximumDimension);
            if (!mainHandler.post(() -> deliver(callback, bitmap, null))) {
                recycle(bitmap);
            }
        } catch (Exception | OutOfMemoryError error) {
            mainHandler.post(() -> deliver(callback, null, error));
        }
    }

    @MainThread
    private void deliver(
            @NonNull Callback callback,
            @Nullable Bitmap bitmap,
            @Nullable Throwable error) {
        if (closed) {
            recycle(bitmap);
            return;
        }

        if (bitmap != null) {
            callback.onPicked(bitmap);
        } else {
            callback.onError(error != null ? error : new IOException("Unable to read photo"));
        }
    }

    /**
     * Decode an upright software Bitmap with bounded dimensions and pixel format; avoid unnecessary JPEG
     * re-encoding.
     *
     * 解码方向正确的软件 Bitmap，并限制尺寸和像素格式；不做无用途的 JPEG 再编码。
     */
    @NonNull
    static Bitmap decode(@NonNull ContentResolver resolver, @NonNull Uri uri, int maximumDimension) throws IOException {
        Bitmap decoded = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ? Api28Impl.decode(resolver, uri, maximumDimension)
                : decodeWithBitmapFactory(resolver, uri, maximumDimension);
        if (decoded == null) {
            throw new IOException("Unsupported or damaged image");
        }

        Bitmap normalized = null;
        try {
            normalized = normalize(decoded, maximumDimension);
            return normalized;
        } finally {
            if (normalized != decoded) {
                recycle(decoded);
            }
        }
    }

    @Nullable
    private static Bitmap decodeWithBitmapFactory(ContentResolver resolver, Uri uri, int maximumDimension)
            throws IOException {
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        try (InputStream input = open(resolver, uri)) {
            BitmapFactory.decodeStream(input, null, bounds);
        }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw new IOException("Unsupported or damaged image");
        }

        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inPreferredConfig = Bitmap.Config.ARGB_8888;
        options.inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maximumDimension);
        Bitmap bitmap;
        try (InputStream input = open(resolver, uri)) {
            bitmap = BitmapFactory.decodeStream(input, null, options);
        }
        if (bitmap == null) {
            return null;
        }
        Bitmap oriented = null;
        try {
            Matrix matrix = orientationMatrix(resolver, uri);
            oriented = matrix.isIdentity() ? bitmap
                    : Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), matrix, true);
            return oriented;
        } finally {
            if (oriented != bitmap) {
                recycle(bitmap);
            }
        }
    }

    @NonNull
    private static InputStream open(ContentResolver resolver, Uri uri) throws IOException {
        InputStream input = resolver.openInputStream(uri);
        if (input == null) {
            throw new IOException("Unable to open selected image");
        }
        return input;
    }

    private static Matrix orientationMatrix(ContentResolver resolver, Uri uri) {
        Matrix matrix = new Matrix();
        try (InputStream input = open(resolver, uri)) {
            ExifInterface exif = new ExifInterface(input);
            int orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_UNDEFINED);
            if (orientation >= ExifInterface.ORIENTATION_NORMAL && orientation <= ExifInterface.ORIENTATION_ROTATE_270) {
                if (exif.isFlipped()) {
                    matrix.setScale(-1f, 1f);
                }
                matrix.postRotate(exif.getRotationDegrees());
                return matrix;
            }
        } catch (IOException | RuntimeException ignored) {
            // Images without readable EXIF may still have an orientation supplied by MediaStore.
        }
        matrix.setRotate(queryOrientation(resolver, uri));
        return matrix;
    }

    private static int queryOrientation(ContentResolver resolver, Uri uri) {
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

    private static int sampleSize(int width, int height, int maximumDimension) {
        int sample = 1;
        while (Math.max(width, height) / (sample * 2) >= maximumDimension) {
            sample *= 2;
        }
        return sample;
    }

    /**
     * Decode at original size within the limit; never enlarge or erase a tiny dimension.
     *
     * 上限内按原尺寸解码；不放大图片，也不裁掉本已很小的维度。
     */
    static int[] decodeSize(int width, int height, int maximumDimension) {
        if (width < 2 || height < 2 || maximumDimension < 2 || maximumDimension > IMAGE_SEARCH_MAX_DIMENSION_PX) {
            throw new IllegalArgumentException("Invalid photo dimensions");
        }
        double scale = Math.min(1.0, maximumDimension / (double) Math.max(width, height));
        int targetWidth = (int) Math.floor(width * scale);
        int targetHeight = (int) Math.floor(height * scale);
        if (targetWidth < 2 || targetHeight < 2) {
            throw new IllegalArgumentException("Photo is too small after resizing");
        }
        return new int[]{targetWidth, targetHeight};
    }

    /**
     * Downscale only oversized images; crop 1 px from odd trailing edges and preserve all other pixels one
     * to one.
     *
     * 仅超限图片缩小；奇数末边直接裁去 1px，保留其余像素的 1:1 映射。
     */
    @NonNull
    private static Bitmap normalize(@NonNull Bitmap source, int maximumDimension) {
        int width = source.getWidth();
        int height = source.getHeight();
        int[] size = decodeSize(width, height, maximumDimension);
        int targetWidth = size[0] & ~1;
        int targetHeight = size[1] & ~1;
        if (targetWidth == width
                && targetHeight == height
                && source.getConfig() == Bitmap.Config.ARGB_8888) {
            return source;
        }

        Bitmap resized = size[0] == width && size[1] == height ? source
                : Bitmap.createScaledBitmap(source, size[0], size[1], true);
        Bitmap cropped = null;
        try {
            cropped = Bitmap.createBitmap(resized, 0, 0, targetWidth, targetHeight);
            if (cropped.getConfig() == Bitmap.Config.ARGB_8888) {
                return cropped;
            }
            Bitmap argb = cropped.copy(Bitmap.Config.ARGB_8888, false);
            if (argb == null) {
                throw new IllegalStateException("Unable to create ARGB bitmap");
            }
            return argb;
        } finally {
            if (resized != source && resized != cropped) {
                recycle(resized);
            }
            if (cropped != null && cropped != source && cropped.getConfig() != Bitmap.Config.ARGB_8888) {
                recycle(cropped);
            }
        }
    }

    private static void recycle(@Nullable Bitmap bitmap) {
        if (bitmap != null && !bitmap.isRecycled()) {
            bitmap.recycle();
        }
    }

    /**
     * Isolate API 28 ImageDecoder calls with annotations to avoid class-verification failures on older
     * systems.
     *
     * 注解隔离 API 28 的 ImageDecoder 调用，避免旧系统类校验失败。
     */
    @RequiresApi(Build.VERSION_CODES.P)
    private static final class Api28Impl {
        private Api28Impl() {
        }

        @NonNull
        static Bitmap decode(
                @NonNull ContentResolver resolver,
                @NonNull Uri uri, int maximumDimension) throws IOException {
            ImageDecoder.Source source = ImageDecoder.createSource(resolver, uri);
            return ImageDecoder.decodeBitmap(source, (decoder, info, ignored) -> {
                int width = info.getSize().getWidth();
                int height = info.getSize().getHeight();
                int[] size = decodeSize(width, height, maximumDimension);
                decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
                if (size[0] != width || size[1] != height) {
                    decoder.setTargetSize(size[0], size[1]);
                }
            });
        }
    }

    /**
     * Cancel pending delivery and stop the image worker thread.
     *
     * 取消待返回结果并停止图片工作线程。
     */
    @MainThread
    @Override
    public void close() {
        if (closed) {
            return;
        }
        closed = true;
        pendingCallback = null;
        launcher.unregister();
        executor.shutdownNow();
        // Already queued results must still enter deliver, which observes closed and releases the newly
        // decoded Bitmap.
        // 已投递的结果仍需进入 deliver；它会看到 closed 并释放刚解码出的 Bitmap。
    }
}
