package com.hiface.sdk.demo.search;

import android.content.Context;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.JsonReader;
import android.util.JsonToken;
import android.util.Log;

import androidx.annotation.MainThread;

import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.capture.FaceCaptureApi;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.common.HiFaceResult;
import com.hiface.sdk.search.FaceSearchDatabase;
import com.hiface.sdk.search.FaceSearchEntry;
import com.hiface.sdk.search.FaceSearchMetadata;
import com.hiface.sdk.search.FaceFeatureFormat;
import com.hiface.sdk.search.FaceSearchFeatureEntry;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CompletionService;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorCompletionService;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

/**
 * Demo 录入和库管理的存储入口：每个页面实例一个句柄，后台串行读写，结果统一回到主线程。
 * 两份批量清单只从 Demo assets 读取，不属于 SDK AAR 的资源或公开协议。
 * 图片清单仅供演示；业务接入时请换成已获授权的人脸测试图片 URL，并使用 CDN 加速。
 */
final class FaceSearchStore implements AutoCloseable {
    static final int FEATURE_DEMO_COUNT = 10_000;
    static final int IMAGE_DEMO_COUNT = 1000;
    private static final int DEMO_SCHEMA_VERSION = 1;
    private static final String FEATURE_FORMAT = "HF1";
    private static final String IMAGE_FORMAT = "url";
    private static final String FEATURE_DEMO_ASSET = "face_search/features_10000.json";
    private static final String IMAGE_DEMO_ASSET = "face_search/images_1000.json";
    private static final int WRITE_BATCH_SIZE = 1_000;
    private static final int IMAGE_WRITE_BATCH_SIZE = 100;
    private static final int IMAGE_PREFETCH_COUNT = 5;
    private static final int MAX_IMAGE_BYTES = 20 * 1024 * 1024;
    private static final int MAX_IMAGE_DIMENSION = 1_080;
    private static final String TAG = "FaceSearchImport";

    interface Callback<T> {
        void onResult(HiFaceResult<T> result);
    }

    interface ProgressCallback {
        void onProgress(ImportProgress progress);
    }

    interface Dispatcher {
        boolean post(Object token, Runnable action);
        void remove(Object token);
    }

    interface Opener {
        HiFaceResult<FaceSearchDatabase> open();
    }

    private interface Task<T> {
        HiFaceResult<T> run(FaceSearchDatabase database, Request<?> request);
    }

    /** 使旧任务失效：跳过尚未开始的工作并抑制结果回调；已提交的数据库批次保持有效。 */
    static final class Request<T> {
        private volatile boolean cancelled;
        private volatile boolean stopRequested;
        private volatile int savedCount;
        private final boolean importOperation;
        private boolean finished;
        private Task<T> task;
        private Callback<T> callback;
        private HiFaceResult<T> result;
        private ProgressCallback progress;
        private ImportProgress pendingProgress;
        private boolean progressPosted;
        private final Dispatcher main;
        private Set<Request<?>> owner;
        private boolean downloadsStopped;
        private final List<HttpURLConnection> connections = new ArrayList<>();

        Request() { main = null; importOperation = false; }

        private Request(Task<T> task, Callback<T> callback, ProgressCallback progress,
                Dispatcher main, Set<Request<?>> owner, boolean importOperation) {
            this.task = task;
            this.callback = callback;
            this.progress = progress;
            this.main = main;
            this.owner = owner;
            this.importOperation = importOperation;
        }

        /** 停止新输入但保留完成回调，让导入线程保存已提取的尾批。 */
        @MainThread
        void stop() {
            stopRequested = true;
            synchronized (this) {
                if (connections.isEmpty()) { downloadsStopped = true; return; }
                if (downloadsStopped) return;
                downloadsStopped = true;
            }
            new Thread(this::stopDownloads, "HiFaceDemo-StopDownload").start();
        }

        int savedCount() { return savedCount; }

        /** 取消后续工作及待交付回调；已经执行的 SQL 或图片推理自然结束。 */
        @MainThread
        synchronized void cancel() {
            cancelled = true;
            releaseLocked();
        }

        private synchronized Task<T> takeTask() {
            Task<T> value = task;
            task = null;
            return cancelled || finished ? null : value;
        }

        private synchronized void complete(HiFaceResult<T> value) {
            if (cancelled || finished) return;
            result = value;
            if (!main.post(this, this::deliverResult)) cancel();
        }

        private void deliverResult() {
            Callback<T> delivery;
            HiFaceResult<T> value;
            synchronized (this) {
                if (cancelled || finished) return;
                delivery = callback;
                value = result;
                finished = true;
                releaseLocked();
            }
            if (delivery != null && value != null) delivery.onResult(value);
        }

        /** 主线程慢时只保留最新进度，不把 1000 张图片的 UI 回调逐条积压。 */
        synchronized void postProgress(int processed, int total) {
            postProgress(processed, total, savedCount, 0);
        }

        synchronized void postProgress(int processed, int total, int imported, int failed) {
            savedCount = imported;
            if (cancelled || finished || progress == null) return;
            pendingProgress = new ImportProgress(processed, total, imported, failed);
            if (progressPosted) return;
            progressPosted = true;
            if (!main.post(this, this::deliverProgress)) cancel();
        }

        private void deliverProgress() {
            ProgressCallback delivery;
            ImportProgress value;
            synchronized (this) {
                if (cancelled || finished) return;
                delivery = progress;
                value = pendingProgress;
                pendingProgress = null;
                progressPosted = false;
            }
            if (delivery != null && value != null) delivery.onProgress(value);
        }

        /** 排队任务只持有 Request；取消时立即释放页面、结果和尚未执行的输入。 */
        private void releaseLocked() {
            task = null;
            callback = null;
            result = null;
            progress = null;
            pendingProgress = null;
            progressPosted = false;
            if (main != null) main.remove(this);
            if (owner != null) {
                owner.remove(this);
                owner = null;
            }
        }

        synchronized boolean trackDownload(HttpURLConnection connection) {
            if (cancelled || stopRequested || downloadsStopped) return false;
            connections.add(connection);
            return true;
        }

        synchronized void untrackDownload(HttpURLConnection connection) {
            connections.remove(connection);
        }

        /** 在导入线程断开网络，避免关闭连接阻塞 UI；登记和停止互斥，不能漏掉刚启动的下载。 */
        void stopDownloads() {
            List<HttpURLConnection> pending;
            synchronized (this) {
                downloadsStopped = true;
                pending = new ArrayList<>(connections);
                connections.clear();
            }
            for (HttpURLConnection connection : pending) connection.disconnect();
        }
    }

    /** 列表只需要 ID、分组和标签，不把特征向量保留到主线程或 Adapter。 */
    static final class Person {
        final String id;
        final String group;
        final String tag;

        Person(FaceSearchMetadata entry) {
            id = entry.getFaceId();
            group = entry.getGroup();
            tag = entry.getTag();
        }
    }

    static final class Page {
        final long total;
        final List<Person> people;

        Page(long total, List<? extends FaceSearchMetadata> entries) {
            this.total = total;
            people = people(entries);
        }
    }

    /** 批量导入只向页面报告已处理数量；图片失败会跳过并继续。 */
    static final class ImportProgress {
        final int processed;
        final int total;
        final int imported;
        final int failed;

        ImportProgress(int processed, int total, int imported, int failed) {
            this.processed = processed;
            this.total = total;
            this.imported = imported;
            this.failed = failed;
        }
    }

    /** 导入结束时区分成功写入与下载、检测或提取失败的图片。 */
    static final class ImportSummary {
        final int imported;
        final int failed;
        final boolean stopped;

        ImportSummary(int imported, int failed) {
            this(imported, failed, false);
        }

        ImportSummary(int imported, int failed, boolean stopped) {
            this.imported = imported;
            this.failed = failed;
            this.stopped = stopped;
        }
    }

    private static final class ImageEntry {
        String faceId;
        String imageUrl;
        String group = "";
        String tag = "";
        long updateTimeMillis;
    }

    private static final class DownloadedImage {
        final ImageEntry entry;
        final byte[] encoded;
        final IOException error;

        DownloadedImage(ImageEntry entry, byte[] encoded, IOException error) {
            this.entry = entry;
            this.encoded = encoded;
            this.error = error;
        }
    }

    private final ExecutorService worker;
    private final Dispatcher main;
    private final AssetManager assets;
    private final Opener opener;
    private final Set<Request<?>> requests = Collections.synchronizedSet(new HashSet<>());
    private FaceSearchDatabase database;
    private volatile boolean closed;

    /** 为页面创建串行数据库线程，任务结果统一投递到主线程。 */
    FaceSearchStore(Context context) {
        this(Executors.newSingleThreadExecutor(task -> new Thread(task, "HiFaceDemo-Database")),
                mainThreadDispatcher(),
                databaseOpener(context), context.getApplicationContext().getAssets());
    }

    private static Dispatcher mainThreadDispatcher() {
        Handler handler = new Handler(Looper.getMainLooper());
        return new Dispatcher() {
            @Override public boolean post(Object token, Runnable action) {
                return handler.postAtTime(action, token, SystemClock.uptimeMillis());
            }
            @Override public void remove(Object token) {
                handler.removeCallbacksAndMessages(token);
            }
        };
    }

    /** 只保留 Application Context，由 SDK 决定人脸库文件名和存储路径。 */
    private static Opener databaseOpener(Context context) {
        Context applicationContext = context.getApplicationContext();
        return () -> HiFaceSdk.openSearchDatabase(applicationContext);
    }

    // 允许主机测试控制任务与回调时序，不依赖相机或 Android Looper。
    FaceSearchStore(ExecutorService worker, Dispatcher main, Opener opener) {
        this(worker, main, opener, null);
    }

    private FaceSearchStore(ExecutorService worker, Dispatcher main, Opener opener,
            AssetManager assets) {
        this.worker = worker;
        this.main = main;
        this.assets = assets;
        this.opener = opener;
    }

    /** 先统计总数再读取指定页，将记录裁成界面所需的 ID、分组和标签。 */
    @MainThread
    Request<Page> loadPage(int offset, int limit, Callback<Page> callback) {
        return execute((db, request) -> {
            HiFaceResult<Long> count = db.count(null, null);
            if (count.isFailure()) {
                return HiFaceResult.failure(count.requireError());
            }
            HiFaceResult<List<FaceSearchMetadata>> entries = db.listRecent(null, null, offset, limit);
            if (entries.isFailure()) {
                return HiFaceResult.failure(entries.requireError());
            }
            return HiFaceResult.success(new Page(count.requireValue(), entries.requireValue()));
        }, callback);
    }

    /** 按 ID 读取一条轻量记录，未找到等状态原样交给页面处理。 */
    @MainThread
    Request<Person> find(String faceId, Callback<Person> callback) {
        return execute((db, request) -> {
            HiFaceResult<FaceSearchEntry> found = db.get(faceId);
            return found.isSuccess()
                    ? HiFaceResult.success(new Person(found.requireValue()))
                    : HiFaceResult.failure(found.requireError());
        }, callback);
    }

    /** 后台删除指定 ID，返回值表示是否实际删除了记录。 */
    @MainThread
    Request<Boolean> delete(String faceId, Callback<Boolean> callback) {
        return execute((db, request) -> db.delete(faceId), callback);
    }

    /** 从 APK 内置 JSON 流式读取 HF1 文本，每 1000 条原子写入一次。 */
    @MainThread
    Request<ImportSummary> importFeatureDemo(ProgressCallback progress, Callback<ImportSummary> callback) {
        return execute(this::importFeatureJson, callback, progress, true);
    }

    /** 按内置清单逐张下载图片并同步提取特征，任何时刻只持有一张 Bitmap。 */
    @MainThread
    Request<ImportSummary> importImageDemo(FaceCaptureApi capture, ProgressCallback progress,
            Callback<ImportSummary> callback) {
        return execute((db, request) -> importImageJson(db, capture, request), callback, progress, true);
    }

    /** 将本次采集的 HF1 文本排入数据库线程；布尔值只表示页面是否已经确认覆盖重复 ID。 */
    @MainThread
    Request<Boolean> save(String faceId, String feature, String group, boolean overwriteConfirmed,
            Callback<Boolean> callback) {
        return execute((db, request) -> saveFeature(db, faceId, feature, group, overwriteConfirmed, request), callback);
    }

    /** 新录入先检查重复 ID；用户明确确认覆盖后，保留 Demo 没有编辑的 tag。 */
    static HiFaceResult<Boolean> saveFeature(FaceSearchDatabase db, String faceId,
            String feature, String group, boolean overwriteConfirmed, Request<?> request) {
        if (request.cancelled) {
            return HiFaceResult.failure(HiFaceErrorCode.CLOSED, "Enrollment save cancelled");
        }
        String tag = null;
        if (!overwriteConfirmed) {
            HiFaceResult<Boolean> exists = db.contains(faceId);
            if (exists.isFailure()) {
                return HiFaceResult.failure(exists.requireError());
            }
            if (exists.requireValue()) {
                return HiFaceResult.failure(HiFaceErrorCode.ALREADY_EXISTS, "Face ID already exists");
            }
        } else {
            HiFaceResult<FaceSearchEntry> existing = db.get(faceId);
            if (existing.isFailure() && existing.requireError().getCode() != HiFaceErrorCode.NOT_FOUND) {
                return HiFaceResult.failure(existing.requireError());
            }
            tag = existing.isSuccess() ? existing.requireValue().getTag() : null;
        }
        // 查询期间页面可能已经离开；不再启动后续写入。
        if (request.cancelled) {
            return HiFaceResult.failure(HiFaceErrorCode.CLOSED, "Enrollment save cancelled");
        }
        return db.saveFeature(faceId, feature, 0, tag, group);
    }

    /** 提取不可修改的展示列表，避免把特征数组随列表一起保留到主线程。 */
    static List<Person> people(List<? extends FaceSearchMetadata> entries) {
        List<Person> people = new ArrayList<>(entries.size());
        for (FaceSearchMetadata entry : entries) {
            people.add(new Person(entry));
        }
        return Collections.unmodifiableList(people);
    }

    /** 分页期间记录可能更新并移动位置；按 ID 合并，更新元数据且不向列表追加重复项。 */
    static List<Person> mergePeople(List<Person> current, List<Person> page) {
        Map<String, Person> merged = new LinkedHashMap<>();
        for (Person person : current) merged.put(person.id, person);
        for (Person person : page) merged.put(person.id, person);
        return new ArrayList<>(merged.values());
    }

    private HiFaceResult<ImportSummary> importFeatureJson(FaceSearchDatabase db,
            Request<?> request) {
        if (request.stopRequested) return HiFaceResult.success(new ImportSummary(0, 0, true));
        if (assets == null) {
            return HiFaceResult.failure(HiFaceErrorCode.INTERNAL_ERROR, "Demo assets unavailable");
        }
        int imported = 0;
        List<FaceSearchFeatureEntry> batch = new ArrayList<>(WRITE_BATCH_SIZE);
        try (JsonReader reader = reader(FEATURE_DEMO_ASSET)) {
            reader.beginObject();
            int schemaVersion = -1;
            int entryCount = -1;
            String featureFormat = null;
            String featureSpaceId = null;
            boolean entriesFound = false;
            while (reader.hasNext()) {
                switch (reader.nextName()) {
                    case "schemaVersion": schemaVersion = reader.nextInt(); continue;
                    case "entryCount": entryCount = reader.nextInt(); continue;
                    case "featureFormat": featureFormat = string(reader); continue;
                    case "featureSpaceId": featureSpaceId = string(reader); continue;
                    case "entries": break;
                    default: reader.skipValue(); continue;
                }
                if (entriesFound) {
                    return invalidImport("Feature JSON contains duplicate entries");
                }
                if (schemaVersion != DEMO_SCHEMA_VERSION
                        || !FEATURE_FORMAT.equals(featureFormat)
                        || !FaceFeatureFormat.FEATURE_SPACE_ID.equals(featureSpaceId)
                        || entryCount != FEATURE_DEMO_COUNT) {
                    return invalidImport("Unsupported bundled feature JSON");
                }
                entriesFound = true;
                reader.beginArray();
                while (reader.hasNext()) {
                    if (request.cancelled) {
                        return cancelledImport();
                    }
                    if (request.stopRequested) return finishImport(db, request, batch, imported, 0, imported + batch.size(), FEATURE_DEMO_COUNT, true);
                    batch.add(readFeatureEntry(reader));
                    if (batch.size() == WRITE_BATCH_SIZE) {
                        if (request.cancelled) {
                            return cancelledImport();
                        }
                        HiFaceResult<Boolean> saved = db.saveFeatures(batch);
                        if (saved.isFailure()) {
                            return HiFaceResult.failure(saved.requireError());
                        }
                        imported += batch.size();
                        batch.clear();
                        request.postProgress(imported, FEATURE_DEMO_COUNT, imported, 0);
                    }
                }
                reader.endArray();
            }
            reader.endObject();
            if (!entriesFound) {
                return invalidImport("Feature JSON has no entries");
            }
            if (!batch.isEmpty()) {
                if (request.cancelled) {
                    return cancelledImport();
                }
                HiFaceResult<Boolean> saved = db.saveFeatures(batch);
                if (saved.isFailure()) {
                    return HiFaceResult.failure(saved.requireError());
                }
                imported += batch.size();
                request.postProgress(imported, FEATURE_DEMO_COUNT, imported, 0);
            }
            if (imported != FEATURE_DEMO_COUNT) {
                return invalidImport("Feature JSON entry count does not match its header");
            }
            return HiFaceResult.success(new ImportSummary(imported, 0, request.stopRequested && imported < FEATURE_DEMO_COUNT));
        } catch (IOException | IllegalStateException | IllegalArgumentException error) {
            return HiFaceResult.failure(HiFaceErrorCode.INVALID_ARGUMENT,
                    "Invalid bundled feature JSON", error);
        }
    }

    private HiFaceResult<ImportSummary> importImageJson(FaceSearchDatabase db,
            FaceCaptureApi capture, Request<?> request) {
        if (request.stopRequested) return HiFaceResult.success(new ImportSummary(0, 0, true));
        if (assets == null) {
            return HiFaceResult.failure(HiFaceErrorCode.INTERNAL_ERROR, "Demo assets unavailable");
        }
        int processed = 0;
        int imported = 0;
        int failed = 0;
        List<FaceSearchFeatureEntry> batch = new ArrayList<>(IMAGE_WRITE_BATCH_SIZE);
        ExecutorService downloads = Executors.newFixedThreadPool(IMAGE_PREFETCH_COUNT,
                task -> new Thread(task, "HiFaceDemo-ImageDownload"));
        try (JsonReader reader = reader(IMAGE_DEMO_ASSET)) {
            reader.beginObject();
            int schemaVersion = -1;
            int entryCount = -1;
            String imageFormat = null;
            boolean entriesFound = false;
            while (reader.hasNext()) {
                switch (reader.nextName()) {
                    case "schemaVersion": schemaVersion = reader.nextInt(); continue;
                    case "entryCount": entryCount = reader.nextInt(); continue;
                    case "imageFormat": imageFormat = string(reader); continue;
                    case "entries": break;
                    default: reader.skipValue(); continue;
                }
                if (entriesFound) {
                    return invalidImport("Image JSON contains duplicate entries");
                }
                if (schemaVersion != DEMO_SCHEMA_VERSION
                        || !IMAGE_FORMAT.equals(imageFormat)
                        || entryCount != IMAGE_DEMO_COUNT) {
                    return invalidImport("Unsupported bundled image JSON");
                }
                entriesFound = true;
                reader.beginArray();
                CompletionService<DownloadedImage> completed =
                        new ExecutorCompletionService<>(downloads);
                int pending = prefetchImages(reader, completed, 0, request);
                while (pending > 0) {
                    if (request.cancelled) {
                        return cancelledImport();
                    }
                    if (request.stopRequested) return finishImport(db, request, batch, imported, failed, processed, IMAGE_DEMO_COUNT, true);
                    DownloadedImage downloaded;
                    try {
                        // 定时检查取消，不能等慢下载超时后才允许页面重新读库。
                        Future<DownloadedImage> ready = completed.poll(200, TimeUnit.MILLISECONDS);
                        if (ready == null) continue;
                        downloaded = ready.get();
                    } catch (InterruptedException error) {
                        Thread.currentThread().interrupt();
                        return cancelledImport();
                    } catch (ExecutionException error) {
                        return HiFaceResult.failure(HiFaceErrorCode.PROCESSING_FAILED,
                                "Demo image download failed", error);
                    }
                    if (request.cancelled) {
                        return cancelledImport();
                    }
                    if (request.stopRequested) return finishImport(db, request, batch, imported, failed, processed, IMAGE_DEMO_COUNT, true);
                    // 按完成顺序消费，并在解码前补位，避免慢请求阻塞后续图片。
                    pending = prefetchImages(reader, completed, pending - 1, request);
                    ImageEntry entry = downloaded.entry;
                    if (downloaded.error != null) {
                        failed++;
                        processed++;
                        Log.w(TAG, "Unable to download " + entry.faceId, downloaded.error);
                        // 每张结束立即更新；最后一张在尾批写库完成后报告，避免重复终值。
                        if (processed < IMAGE_DEMO_COUNT) {
                            request.postProgress(processed, IMAGE_DEMO_COUNT, imported, failed);
                        }
                        continue;
                    }
                    if (request.cancelled) {
                        return cancelledImport();
                    }
                    Bitmap bitmap = null;
                    try {
                        bitmap = decodeBitmap(downloaded.encoded);
                        if (request.stopRequested) return finishImport(db, request, batch, imported, failed, processed, IMAGE_DEMO_COUNT, true);
                        HiFaceResult<String> feature = capture.extractFeatureBlocking(bitmap);
                        if (request.cancelled) {
                            return cancelledImport();
                        }
                        if (feature.isSuccess()) {
                            batch.add(new FaceSearchFeatureEntry(entry.faceId,
                                    feature.requireValue(), entry.updateTimeMillis,
                                    entry.tag, entry.group));
                        } else {
                            failed++;
                            Log.w(TAG, entry.faceId + ": " + feature.requireError());
                        }
                    } catch (IOException | RuntimeException error) {
                        failed++;
                        Log.w(TAG, "Unable to decode or extract " + entry.faceId, error);
                    } finally {
                        if (bitmap != null) {
                            bitmap.recycle();
                        }
                    }
                    processed++;
                    if (request.stopRequested) return finishImport(db, request, batch,
                            imported, failed, processed, IMAGE_DEMO_COUNT, true);
                    if (batch.size() >= IMAGE_WRITE_BATCH_SIZE) {
                        if (request.cancelled) {
                            return cancelledImport();
                        }
                        HiFaceResult<Boolean> saved = db.saveFeatures(batch);
                        if (saved.isFailure()) {
                            return HiFaceResult.failure(saved.requireError());
                        }
                        imported += batch.size();
                        batch.clear();
                    }
                    if (processed < IMAGE_DEMO_COUNT) {
                        request.postProgress(processed, IMAGE_DEMO_COUNT, imported, failed);
                    }
                }
                reader.endArray();
            }
            reader.endObject();
            if (!entriesFound) {
                return invalidImport("Image JSON has no entries");
            }
            if (!batch.isEmpty()) {
                if (request.cancelled) {
                    return cancelledImport();
                }
                HiFaceResult<Boolean> saved = db.saveFeatures(batch);
                if (saved.isFailure()) {
                    return HiFaceResult.failure(saved.requireError());
                }
                imported += batch.size();
            }
            if (processed != IMAGE_DEMO_COUNT) {
                return invalidImport("Image JSON entry count does not match its header");
            }
            request.postProgress(processed, IMAGE_DEMO_COUNT, imported, failed);
            return HiFaceResult.success(new ImportSummary(imported, failed, request.stopRequested && processed < IMAGE_DEMO_COUNT));
        } catch (IOException | IllegalStateException | IllegalArgumentException error) {
            return HiFaceResult.failure(HiFaceErrorCode.INVALID_ARGUMENT,
                    "Invalid bundled image JSON", error);
        } finally {
            downloads.shutdownNow();
            request.stopDownloads();
        }
    }

    /** 保存停止前已完成的结果；写库失败仍报告原有已提交数量。 */
    static HiFaceResult<ImportSummary> finishImport(FaceSearchDatabase db, Request<?> request,
            List<FaceSearchFeatureEntry> batch, int imported, int failed, int processed,
            int total, boolean stopped) {
        if (request.cancelled) return cancelledImport();
        if (!batch.isEmpty()) {
            HiFaceResult<Boolean> saved = db.saveFeatures(batch);
            if (saved.isFailure()) return HiFaceResult.failure(saved.requireError());
            imported += batch.size();
            batch.clear();
        }
        request.postProgress(processed, total, imported, failed);
        return HiFaceResult.success(new ImportSummary(imported, failed, stopped && processed < total));
    }

    private static int prefetchImages(JsonReader reader,
            CompletionService<DownloadedImage> downloads, int pending,
            Request<?> request) throws IOException {
        while (!request.cancelled && !request.stopRequested && pending < IMAGE_PREFETCH_COUNT && reader.hasNext()) {
            ImageEntry entry = readImageEntry(reader);
            downloads.submit(() -> {
                try {
                    return new DownloadedImage(entry, download(entry.imageUrl, request), null);
                } catch (IOException error) {
                    return new DownloadedImage(entry, null, error);
                }
            });
            pending++;
        }
        return pending;
    }

    private JsonReader reader(String asset) throws IOException {
        return new JsonReader(new InputStreamReader(assets.open(asset), StandardCharsets.UTF_8));
    }

    private static FaceSearchFeatureEntry readFeatureEntry(JsonReader reader) throws IOException {
        String faceId = null;
        String feature = null;
        String group = "";
        String tag = "";
        long updateTimeMillis = 0;
        reader.beginObject();
        while (reader.hasNext()) {
            switch (reader.nextName()) {
                case "faceId": faceId = string(reader); break;
                case "feature": feature = string(reader); break;
                case "group": group = string(reader); break;
                case "tag": tag = string(reader); break;
                case "updateTimeMillis": updateTimeMillis = reader.nextLong(); break;
                default: reader.skipValue();
            }
        }
        reader.endObject();
        return new FaceSearchFeatureEntry(faceId, feature, updateTimeMillis, tag, group);
    }

    private static ImageEntry readImageEntry(JsonReader reader) throws IOException {
        ImageEntry entry = new ImageEntry();
        reader.beginObject();
        while (reader.hasNext()) {
            switch (reader.nextName()) {
                case "faceId": entry.faceId = string(reader); break;
                case "imageUrl": entry.imageUrl = string(reader); break;
                case "group": entry.group = string(reader); break;
                case "tag": entry.tag = string(reader); break;
                case "updateTimeMillis": entry.updateTimeMillis = reader.nextLong(); break;
                default: reader.skipValue();
            }
        }
        reader.endObject();
        if (entry.faceId == null || entry.faceId.isEmpty()
                || entry.imageUrl == null || entry.imageUrl.isEmpty()) {
            throw new IllegalArgumentException("Image entry requires faceId and imageUrl");
        }
        return entry;
    }

    private static String string(JsonReader reader) throws IOException {
        if (reader.peek() == JsonToken.NULL) {
            reader.nextNull();
            return "";
        }
        return reader.nextString();
    }

    /** 下载阶段限制压缩数据大小，避免异常响应把 Demo 内存耗尽。 */
    private static byte[] download(String value, Request<?> request) throws IOException {
        URL url = new URL(value);
        if (!"https".equals(url.getProtocol())) {
            throw new IOException("Only HTTPS image URLs are supported");
        }
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setConnectTimeout(10_000);
        connection.setReadTimeout(20_000);
        connection.setInstanceFollowRedirects(true);
        try {
            if (!request.trackDownload(connection)) throw new IOException("Import cancelled");
            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) {
                throw new IOException("HTTP " + status);
            }
            // getContentLengthLong() requires API 24. The download cap is only 20 MB,
            // so the API 1 int variant is sufficient and keeps the Demo compatible with minSdk 23.
            int contentLength = connection.getContentLength();
            if (contentLength > MAX_IMAGE_BYTES) {
                throw new IOException("Image exceeds 20 MB");
            }
            try (InputStream input = connection.getInputStream()) {
                ByteArrayOutputStream output = new ByteArrayOutputStream(
                        contentLength > 0 ? contentLength : 16 * 1024);
                byte[] buffer = new byte[16 * 1024];
                int total = 0;
                int read;
                while ((read = input.read(buffer)) != -1) {
                    if (request.cancelled) throw new IOException("Import cancelled");
                    total += read;
                    if (total > MAX_IMAGE_BYTES) {
                        throw new IOException("Image exceeds 20 MB");
                    }
                    output.write(buffer, 0, read);
                }
                return output.toByteArray();
            }
        } finally {
            request.untrackDownload(connection);
            connection.disconnect();
        }
    }

    /** 先读尺寸再降采样，最终只把最长边不超过 1080px 的偶数尺寸 Bitmap 送入 SDK。 */
    private static Bitmap decodeBitmap(byte[] encoded) throws IOException {
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(encoded, 0, encoded.length, bounds);
        if (bounds.outWidth < 2 || bounds.outHeight < 2) {
            throw new IOException("Unsupported image data");
        }

        int sampleSize = 1;
        while (bounds.outWidth / sampleSize > MAX_IMAGE_DIMENSION * 2
                || bounds.outHeight / sampleSize > MAX_IMAGE_DIMENSION * 2) {
            sampleSize *= 2;
        }
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inPreferredConfig = Bitmap.Config.ARGB_8888;
        options.inSampleSize = sampleSize;
        Bitmap decoded = BitmapFactory.decodeByteArray(encoded, 0, encoded.length, options);
        if (decoded == null) {
            throw new IOException("Unsupported image data");
        }

        int width = decoded.getWidth();
        int height = decoded.getHeight();
        float scale = Math.min(1.0f,
                MAX_IMAGE_DIMENSION / (float) Math.max(width, height));
        int targetWidth = Math.max(2, ((int) (width * scale)) & ~1);
        int targetHeight = Math.max(2, ((int) (height * scale)) & ~1);
        if (targetWidth == width && targetHeight == height) {
            return decoded;
        }
        try {
            return Bitmap.createScaledBitmap(decoded, targetWidth, targetHeight, true);
        } finally {
            decoded.recycle();
        }
    }

    private static HiFaceResult<ImportSummary> invalidImport(String message) {
        return HiFaceResult.failure(HiFaceErrorCode.INVALID_ARGUMENT, message);
    }

    private static HiFaceResult<ImportSummary> cancelledImport() {
        return HiFaceResult.failure(HiFaceErrorCode.CLOSED, "Import cancelled");
    }

    /** 按需开库并复用连接；打开失败不缓存错误，下次刷新可以重试。 */
    @MainThread
    private <T> Request<T> execute(Task<T> task, Callback<T> callback) {
        return execute(task, callback, null);
    }

    @MainThread
    private <T> Request<T> execute(Task<T> task, Callback<T> callback, ProgressCallback progress) {
        return execute(task, callback, progress, false);
    }

    private <T> Request<T> execute(Task<T> task, Callback<T> callback, ProgressCallback progress,
            boolean importOperation) {
        Request<T> request = new Request<>(task, callback, progress, main, requests, importOperation);
        if (closed) {
            request.cancel();
            return request;
        }
        requests.add(request);
        worker.execute(() -> {
            Task<T> work = request.takeTask();
            if (work != null && request.importOperation && request.stopRequested) {
                request.complete(work.run(null, request));
                return;
            }
            if (work == null || request.cancelled) {
                return;
            }
            if (closed) {
                if (request.importOperation) {
                    request.stop();
                    request.complete(work.run(null, request));
                }
                return;
            }
            HiFaceError error = null;
            if (database == null) {
                HiFaceResult<FaceSearchDatabase> opened = opener.open();
                if (opened.isSuccess()) database = opened.requireValue();
                else error = opened.requireError();
            }
            // 开库也可能耗时，返回后再次校验，避免离开页面后执行排队的删除。
            if (request.cancelled) return;
            if (closed || request.stopRequested) {
                if (request.importOperation) {
                    request.stop();
                    request.complete(work.run(null, request));
                }
                return;
            }
            HiFaceResult<T> result = error == null
                    ? work.run(database, request) : HiFaceResult.failure(error);
            request.complete(result);
        });
        return request;
    }

    /** 导入停止新输入并保存尾批，再关库；其他未开始的任务及界面回调失效。 */
    @MainThread
    @Override
    public void close() {
        if (closed) {
            return;
        }
        closed = true;
        List<Request<?>> pending;
        synchronized (requests) { pending = new ArrayList<>(requests); }
        for (Request<?> request : pending) {
            if (request.importOperation) request.stop(); else request.cancel();
        }
        worker.execute(() -> {
            if (database != null) {
                try { database.close(); }
                finally { database = null; }
            }
        });
        worker.shutdown();
    }
}
