package com.hiface.sdk.demo.storage;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Looper;
import androidx.annotation.Nullable;
import com.hiface.sdk.capture.FaceCaptureResult;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;

/** Demo-owned confirmed face photos, in internal no-backup storage. No shared URI or disk history. */
public final class FacePhotoStore {
    public interface Callback {
        void onLoaded(@Nullable Bitmap bitmap);
    }

    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static final Pattern NUMERIC_ID = Pattern.compile("[0-9]+");
    private static final Object LOCK = new Object();
    private static final ExecutorService IO = Executors.newSingleThreadExecutor(
            r -> new Thread(r, "HiFaceDemo-Photos"));
    public static final FacePhotoStore SEARCH = new FacePhotoStore("search");
    public static final FacePhotoStore REFERENCE = new FacePhotoStore("reference");
    private final String library;

    private FacePhotoStore(String library) {
        this.library = library;
    }

    // Numeric IDs keep their readable filenames. Other UTF-8 IDs use reversible hex encoding,
    // avoiding path traversal, reserved Windows names and case-insensitive filename collisions.
    static String key(String id) {
        if (id == null || id.isEmpty() || id.indexOf('\0') >= 0) {
            throw new IllegalArgumentException("Invalid Face ID");
        }
        if (NUMERIC_ID.matcher(id).matches()) {
            return id;
        }
        StringBuilder out = new StringBuilder("~");
        for (byte b : id.getBytes(StandardCharsets.UTF_8)) {
            out.append(Character.forDigit((b & 255) >>> 4, 16)).append(Character.forDigit(b & 15, 16));
        }
        return out.toString();
    }

    private File file(Context context, String id, boolean create) throws IOException {
        File directory = new File(context.getNoBackupFilesDir(), "face-photos-v1/" + library);
        String encoded = key(id);
        while (encoded.length() > 120) {
            directory = new File(directory, encoded.substring(0, 120));
            encoded = encoded.substring(120);
        }
        if (create && !directory.isDirectory() && !directory.mkdirs()) {
            throw new IOException("Cannot create private photo directory");
        }
        return new File(directory, encoded + ".jpg");
    }

    /** Call on a worker after the feature transaction succeeds; owns/recycles its own preview copy. */
    public boolean save(Context context, String id, FaceCaptureResult capture) {
        Bitmap bitmap = capture.getAlignedFace();
        try {
            return save(context, id, bitmap);
        } finally {
            bitmap.recycle();
        }
    }

    public boolean save(Context context, String id, Bitmap bitmap) {
        synchronized (LOCK) {
            File temporary = null;
            try {
                File target = file(context, id, true);
                temporary = File.createTempFile("photo-", ".tmp", target.getParentFile());
                try (FileOutputStream stream = new FileOutputStream(temporary)) {
                    if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 95, stream)) {
                        throw new IOException("JPEG encoding failed");
                    }
                    stream.getFD().sync();
                }
                if (!temporary.renameTo(target)) {
                    throw new IOException("Cannot replace private photo");
                }
                return true;
            } catch (IOException | RuntimeException error) {
                // A newly committed feature must never keep the previous person's photo.
                remove(context, id);
                return false;
            } finally {
                if (temporary != null) {
                    temporary.delete();
                }
            }
        }
    }

    /** A missing/corrupt photo is optional. Decode only a thumbnail, with no process-wide bitmap cache. */
    @Nullable
    public Bitmap load(Context context, String id) {
        synchronized (LOCK) {
            try {
                File target = file(context, id, false);
                if (!target.isFile() || target.length() > 1024 * 1024) {
                    return null;
                }
                BitmapFactory.Options options = new BitmapFactory.Options();
                options.inJustDecodeBounds = true;
                BitmapFactory.decodeFile(target.getPath(), options);
                if (options.outWidth < 1 || options.outHeight < 1 || options.outWidth > 720 || options.outHeight > 720) {
                    return null;
                }
                options.inJustDecodeBounds = false;
                options.inSampleSize = 2;
                return BitmapFactory.decodeFile(target.getPath(), options);
            } catch (IOException | RuntimeException error) {
                return null;
            }
        }
    }

    public static final class Request {
        private Callback completion;

        private Request(Callback completion) {
            this.completion = completion;
        }

        public synchronized void cancel() {
            completion = null;
        }

        private synchronized boolean active() {
            return completion != null;
        }

        private synchronized void deliver(Bitmap bitmap) {
            Callback callback = completion;
            completion = null;
            if (callback != null) {
                callback.onLoaded(bitmap);
            } else if (bitmap != null) {
                bitmap.recycle();
            }
        }
    }

    public Request loadAsync(Context context, String id, Callback completion) {
        Context app = context.getApplicationContext();
        Request request = new Request(completion);
        IO.execute(() -> {
            if (!request.active()) {
                return;
            }
            Bitmap image = load(app, id);
            if (!MAIN.post(() -> request.deliver(image)) && image != null) {
                image.recycle();
            }
        });
        return request;
    }

    public static void execute(Runnable work) {
        IO.execute(work);
    }

    public void remove(Context context, String id) {
        synchronized (LOCK) {
            try {
                File target = file(context, id, false);
                target.delete();
                File root = new File(context.getNoBackupFilesDir(), "face-photos-v1/" + library);
                for (File parent = target.getParentFile(); parent != null && !parent.equals(
                        root); parent = parent.getParentFile()) {
                    if (!parent.delete()) {
                        break;
                    }
                }
            } catch (IOException | RuntimeException ignored) {
            }
        }
    }
}
