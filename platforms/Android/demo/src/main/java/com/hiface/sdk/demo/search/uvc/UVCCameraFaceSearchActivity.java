package com.hiface.sdk.demo.search.uvc;

import android.Manifest;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Matrix;
import android.graphics.SurfaceTexture;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.Surface;
import android.view.TextureView;
import android.view.View;
import android.view.WindowManager;
import android.widget.TextView;
import android.widget.Toast;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.widget.PopupMenu;
import androidx.core.content.ContextCompat;
import androidx.core.content.IntentCompat;
import com.facesdkpro.uvccamera.CameraFailure;
import com.facesdkpro.uvccamera.DualCameraConfig;
import com.facesdkpro.uvccamera.DualCameraSession;
import com.facesdkpro.uvccamera.FramePair;
import com.facesdkpro.uvccamera.Nv21Planes;
import com.facesdkpro.uvccamera.PreviewTransform;
import com.facesdkpro.uvccamera.UvcCameraManager;
import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.common.HiFaceResult;
import com.hiface.sdk.demo.ui.DemoWindowInsets;
import com.hiface.sdk.detection.FaceDetectionResult;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.search.FaceSearchLibraryActivity;
import com.hiface.sdk.demo.search.FaceSearchOverlayView;
import com.hiface.sdk.demo.ui.DemoErrorUi;
import com.hiface.sdk.frame.RgbIrFrame;
import com.hiface.sdk.frame.Yuv420Frame;
import com.hiface.sdk.frame.YuvColorMatrix;
import com.hiface.sdk.frame.YuvColorRange;
import com.hiface.sdk.search.FaceSearchFrame;
import com.hiface.sdk.search.FaceSearchListener;
import com.hiface.sdk.search.FaceSearchProgress;
import com.hiface.sdk.search.FaceSearchResult;
import com.hiface.sdk.search.FaceSearchSession;
import com.hiface.sdk.search.FaceSearchSessionConfig;
import com.hiface.sdk.search.InfraredSearchInfo;

/**
 * Owns RGB/IR capture and SDK search sessions. Settings, result display and brightness stay separate.
 * The SDK makes the final identity/IR decision for the same sample; ordinary RGB search is independent.
 *
 * <p>Main owns lifecycle and UI; UVC-pairs synchronously borrows pixels and applies analysis throttling.
 * A generation change rejects old callbacks. Logs contain no images, features, identities or scores.</p>
 * 中文：主线程管理会话，帧回调只同步借用像素；停止后拒绝旧回调并等待资源排空。
 */
public final class UVCCameraFaceSearchActivity extends AppCompatActivity {
    private static final String TAG = "HiFaceRgbIr";
    private static final long PAIR_TIMEOUT_MS = 5000;

    private final Handler main = new Handler(Looper.getMainLooper());
    private HiFaceSdk sdk;
    private FaceSearchSession search;
    private DualCameraSession cameras;
    private UvcCameraSettings cameraSettings;
    private UvcCameraSettings.Selection capture;
    private DualCameraConfig actualConfig;
    private TextureView preview, irPreview;
    private final UvcPreviewSurfaces surfaces = new UvcPreviewSurfaces();
    private InfraredDebugOverlayView irOverlay;
    private TextView diagnostics;
    private final RgbIrSearchStats stats = new RgbIrSearchStats();
    private AlertDialog searchSettingsDialog;
    private FaceSearchSessionConfig searchOptions;
    private UvcSearchStatusUi statusUi;
    private UvcSearchDisplayPolicy displayPolicy;
    private final UvcCameraCloseBarrier closeBarrier = new UvcCameraCloseBarrier();
    private FaceSearchOverlayView overlay;
    private TextView status;
    // requested survives backgrounding; running admits callbacks only for the current session.
    private boolean started, requested, permissionPending;
    private boolean usbReceiverRegistered, devicesRefreshPending, discoveryPending;
    private volatile boolean running;
    private volatile long generation, lastPairAt;

    private final Runnable refreshUsbDevices = this::flushDeviceChanges;
    private final BroadcastReceiver usbDevices = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (!started) return;
            String action = intent.getAction();
            boolean attached = UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action);
            if (!attached && !UsbManager.ACTION_USB_DEVICE_DETACHED.equals(action)) return;
            UsbDevice device = IntentCompat.getParcelableExtra(intent, UsbManager.EXTRA_DEVICE, UsbDevice.class);
            if (!UvcCameraManager.isCamera(device)) return;
            devicesRefreshPending = true;
            discoveryPending |= attached;
            if (!attached && (running || requested) && (cameraSettings.usesDevice(device)
                    || capture != null && (device.equals(capture.rgb) || device.equals(capture.ir)))) {
                // Invalidate old callbacks immediately; the close barrier still waits for USB/Surface cleanup.
                failCapture(getString(R.string.uvc_search_usb_detached), true);
            }
            main.removeCallbacks(refreshUsbDevices);
            main.postDelayed(refreshUsbDevices, 300); // A dual-camera hub can send two attachment broadcasts.
        }
    };

    private final Runnable diagnosticsTicker = new Runnable() {
        @Override public void run() {
            if (!running) return;
            renderDiagnostics();
            main.postDelayed(this, 1000);
        }
    };

    private final ActivityResultLauncher<String> permission =
            registerForActivityResult(new ActivityResultContracts.RequestPermission(), this::onCameraPermission);

    private final Runnable watchdog = new Runnable() {
        @Override public void run() {
            if (!running) return;
            long age = SystemClock.elapsedRealtime() - lastPairAt;
            if (age > PAIR_TIMEOUT_MS) {
                failCapture(getString(R.string.uvc_search_pair_timeout), true);
                return;
            }
            // Two live streams may still fail pairing; clear stale results rather than retain a previous pass.
            if (age > UvcSearchIdlePolicy.PAIR_GAP_MS) {
                overlay.clear();
                irOverlay.show(null);
                statusUi.waitingForPair();
                displayPolicy.setIdle(false);
            }
            main.postDelayed(this, 500);
        }
    };

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_uvc_camera_face_search);
        DemoWindowInsets.applyToContent(this);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        bindViews(state);
        bindActions();
        bindPreview();
        sdk = HiFaceSdk.builder(this).lifecycleOwner(this).build();
        refreshDevices();
        cameraSettings.restore(state);
        requested = state != null && state.getBoolean("captureRequested");
        updateButtons();
    }

    @Override protected void onStart() {
        super.onStart();
        started = true;
        IntentFilter usbFilter = new IntentFilter(UsbManager.ACTION_USB_DEVICE_ATTACHED);
        usbFilter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        ContextCompat.registerReceiver(this, usbDevices, usbFilter, ContextCompat.RECEIVER_EXPORTED);
        usbReceiverRegistered = true;
        devicesRefreshPending = true;
        closeBarrier.listen(() -> {
            updateButtons();
            flushDeviceChanges();
            startCapture();
        });
        flushDeviceChanges();
        updateButtons();
        startCapture();
    }

    @Override protected void onStop() {
        started = false;
        main.removeCallbacks(refreshUsbDevices);
        if (usbReceiverRegistered) {
            unregisterReceiver(usbDevices);
            usbReceiverRegistered = false;
        }
        closeBarrier.listen(null);
        cameraSettings.dismiss();
        if (searchSettingsDialog != null) searchSettingsDialog.dismiss();
        stopCapture(false);
        super.onStop();
    }

    @Override protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        cameraSettings.save(out);
        out.putBoolean("captureRequested", requested);
        UvcSearchSettingsDialog.save(out, searchOptions);
    }

    private void bindViews(Bundle state) {
        preview = findViewById(R.id.uvcPreview);
        irPreview = findViewById(R.id.uvcIrPreview);
        irOverlay = findViewById(R.id.uvcIrOverlay);
        diagnostics = findViewById(R.id.uvcDiagnostics);
        overlay = findViewById(R.id.uvcOverlay);
        overlay.setAssociationEnabled(false); // Never associate identity and IR verdicts across samples.
        status = findViewById(R.id.uvcStatus);
        searchOptions = UvcSearchSettingsDialog.restore(state);
        statusUi = new UvcSearchStatusUi(findViewById(android.R.id.content), main);
        statusUi.config(searchOptions);
        displayPolicy = new UvcSearchDisplayPolicy(getWindow());
        cameraSettings = new UvcCameraSettings(this, this::refreshDevices, this::updateDebugPreview);
    }

    private void bindActions() {
        findViewById(R.id.backButton).setOnClickListener(v -> finish());
        findViewById(R.id.uvcSettings).setOnClickListener(this::showSettingsMenu);
        for (int id : new int[]{R.id.uvcStart, R.id.uvcRetry}) findViewById(id).setOnClickListener(v -> {
            requested = true;
            startCapture();
        });
        findViewById(R.id.uvcStop).setOnClickListener(v -> {
            stopCapture();
            show(R.string.uvc_search_stopped);
        });
        findViewById(R.id.uvcLibrary).setOnClickListener(v -> openPage(new Intent(this, FaceSearchLibraryActivity.class)));
        findViewById(R.id.uvcEnroll).setOnClickListener(v -> openPage(UVCCameraFaceEnrollmentActivity.intent(
                this, cameraSettings.enrollmentChoice(), searchOptions.getGroup())));
    }

    private void bindPreview() {
        TextureView.SurfaceTextureListener textures = new TextureView.SurfaceTextureListener() {
            @Override public void onSurfaceTextureAvailable(SurfaceTexture texture, int width, int height) {
                startCapture();
            }
            @Override public void onSurfaceTextureSizeChanged(SurfaceTexture texture, int width, int height) {
                updatePreviewTransform();
                clearResults();
            }
            @Override public boolean onSurfaceTextureDestroyed(SurfaceTexture texture) {
                if (cameras != null) {
                    surfaces.retain(texture);
                    stopCapture(false);
                    return false;
                }
                return true;
            }
            @Override public void onSurfaceTextureUpdated(SurfaceTexture texture) {}
        };
        preview.setSurfaceTextureListener(textures);
        irPreview.setSurfaceTextureListener(textures);
    }

    private void onCameraPermission(boolean granted) {
        permissionPending = false;
        flushDeviceChanges();
        // A late permission result must not restart a stopped or hidden page.
        if (started && requested) {
            if (granted) startCapture();
            else {
                requested = false;
                show(R.string.uvc_search_camera_permission);
            }
        }
        updateButtons();
    }

    private void showSettingsMenu(View anchor) {
        PopupMenu menu = new PopupMenu(this, anchor);
        menu.inflate(R.menu.uvc_search_settings);
        menu.setOnMenuItemClickListener(item -> {
            if (item.getItemId() == R.id.uvcSearchSettings) showSearchSettings();
            else if (item.getItemId() == R.id.uvcCameraSettings) showCameraSettings();
            return true;
        });
        menu.show();
    }

    /** Edit device/preview settings only while idle; search settings can be applied independently. */
    private void showCameraSettings() {
        showCameraSettings(false);
    }

    private void showCameraSettings(boolean discovered) {
        if (!canEditCameras()) {
            Toast.makeText(this, R.string.uvc_search_settings_running, Toast.LENGTH_SHORT).show();
            return;
        }
        cameraSettings.show(discovered, () -> {
            show(cameraSettings.setupHint());
            offerRetry(false);
        });
    }

    private void showSearchSettings() {
        if (searchSettingsDialog != null && searchSettingsDialog.isShowing()) return;
        searchSettingsDialog = UvcSearchSettingsDialog.show(this, searchOptions, next -> {
            searchOptions = next;
            clearResults();
            statusUi.config(next);
            if (search != null) search.setConfig(UvcSearchSettingsDialog.withInfrared(next, capture.infrared));
        });
    }

    private void openPage(Intent page) {
        // Register USB closure before navigation; enrollment opens the shared RGB device only after draining.
        started = false;
        stopCapture(false);
        startActivity(page);
    }

    /** Refresh idle device choices and return the change directly, without retaining temporary state. */
    private boolean refreshDevices() {
        if (cameras != null) return false;
        try {
            boolean changed = cameraSettings.refreshDevices();
            show(cameraSettings.setupHint());
            return changed;
        } catch (RuntimeException error) {
            failCamera("Cannot enumerate UVC cameras", error);
            return false;
        }
    }

    /** Coalesce USB events; refresh only after old cameras and permission requests finish. */
    private void flushDeviceChanges() {
        if (!devicesRefreshPending || !started || isFinishing() || isDestroyed()
                || !camerasIdle() || permissionPending) return;
        boolean discovered = discoveryPending;
        devicesRefreshPending = discoveryPending = false;
        boolean changed = refreshDevices();
        if ((discovered || requested && changed) && cameraSettings.deviceCount() > 0) {
            // Confirm roles after reconnection; never resume with stale UsbDevice handles.
            requested = false;
            updateButtons();
            showCameraSettings(true);
        }
    }

    /** Validate devices/IR before permissions and surfaces; recheck user intent on every continuation. */
    private void startCapture() {
        if (!started || !requested || !camerasIdle() || permissionPending || isFinishing() || isDestroyed()) return;
        offerRetry(false);
        UvcCameraSettings.Selection selection = cameraSettings.read();
        if (selection == null) {
            requested = false;
            show(cameraSettings.validationMessage());
            updateButtons();
            showCameraSettings();
            return;
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            permissionPending = true;
            show(R.string.uvc_search_allow_camera);
            updateButtons();
            permission.launch(Manifest.permission.CAMERA);
            return;
        }
        if (!preview.isAvailable() || (cameraSettings.debugEnabled() && !irPreview.isAvailable())) {
            show(R.string.uvc_search_opening);
            updateButtons();
            return; // Surface availability continues this request; Stop can still cancel it.
        }

        capture = selection;
        actualConfig = null;
        final long epoch = ++generation;
        stats.start(epoch, SystemClock.elapsedRealtimeNanos());
        statusUi.clear();
        try {
            // Require explicit IR liveness for this sample; disabling RGB liveness cannot grant a pass.
            search = sdk.search().startCameraSearch(
                    UvcSearchSettingsDialog.withInfrared(searchOptions, capture.infrared), searchListener(epoch));
            Surface rgbSurface = surfaces.open(preview);
            Surface irSurface = cameraSettings.debugEnabled() ? surfaces.open(irPreview) : null;
            running = true;
            displayPolicy.start();
            lastPairAt = SystemClock.elapsedRealtime();
            UvcSearchIdlePolicy idle = new UvcSearchIdlePolicy();
            // Assign before starting so even startup failures use the same camera/Surface cleanup path.
            cameras = DualCameraSession.create(this, capture.rgb, capture.ir, capture.config,
                    rgbSurface, irSurface, cameraListener(epoch), pair -> processPair(pair, epoch, idle));
            cameras.start();
            updatePreviewTransform();
            show(R.string.uvc_search_opening);
            main.post(diagnosticsTicker);
        } catch (RuntimeException error) {
            // Include search and Surface creation failures in cleanup; do not retain a partial session.
            failCamera("Cannot start RGB/IR search", error);
        }
        updateButtons();
    }

    private FaceSearchListener searchListener(long epoch) {
        return new FaceSearchListener() {
            @Override public void onFrame(FaceSearchFrame frame) {
                if (!current(epoch)) return;
                overlay.show(frame, analysisToPreview(frame.getImageWidth(), frame.getImageHeight()));
                renderInfrared(epoch, frame.getInfrared());
                statusUi.frame(frame);
            }
            @Override public void onProgress(FaceSearchProgress progress) {
                if (!current(epoch)) return;
                if (progress.getStage() == FaceSearchProgress.Stage.EMPTY_GALLERY) overlay.rejectScores();
                statusUi.progress(progress);
            }
            @Override public void onResult(FaceSearchResult result) {
                if (!current(epoch)) return;
                overlay.showResult(result);
                renderInfrared(epoch, result.getFrame().getInfrared());
                statusUi.result(result);
            }
            @Override public void onError(HiFaceError error) {
                if (current(epoch)) failSearch(error);
            }
        };
    }

    private DualCameraSession.Listener cameraListener(long epoch) {
        return new DualCameraSession.Listener() {
            @Override public void onReady(DualCameraSession source) {
                if (!current(epoch)) return;
                actualConfig = source.actualConfig();
                updatePreviewTransform();
                ((TextView) findViewById(R.id.uvcPreviewLabel)).setText(getString(
                        R.string.uvc_stream_actual, actualConfig.rgb.toString(), actualConfig.ir.toString()));
                lastPairAt = SystemClock.elapsedRealtime();
                statusUi.camerasReady();
                // USB permissions may be sequential; start the pair watchdog only when both cameras are open.
                main.postDelayed(watchdog, 500);
            }
            @Override public void onError(DualCameraSession source, String message, Throwable cause) {
                if (!current(epoch)) return;
                failCamera(message, cause);
            }
            @Override public void onFailure(DualCameraSession source, DualCameraSession.Role role, CameraFailure failure) {
                if (!current(epoch)) return;
                int hint = UvcCameraFailureUi.message(failure.code);
                String message = getString(hint);
                if (role != null) {
                    int camera = role == DualCameraSession.Role.RGB
                            ? R.string.uvc_search_rgb_camera : R.string.uvc_search_ir_camera;
                    message = getString(R.string.uvc_search_camera_failure, getString(camera), message);
                }
                failCapture(message, true);
                // Log technical codes only, without images, identities or scores.
                Log.w(TAG, "UVC " + role + ": " + failure.code + ", native=" + failure.nativeStatus);
            }
            @Override public void onClosed(DualCameraSession source) {
                if (cameras != source) return;
                cameras = null;
                // USB/native resources and in-flight pair consumers have drained at this callback.
                surfaces.release();
                updateButtons();
                closeBarrier.closed();
                flushDeviceChanges();
            }
        };
    }

    /** Borrow pixels synchronously on UVC-pairs; never post pair/ByteBuffer to main. 中文：回调返回后像素失效。 */
    private void processPair(FramePair pair, long epoch, UvcSearchIdlePolicy idle) {
        if (!current(epoch)) return;
        long startedNanos = SystemClock.elapsedRealtimeNanos();
        long now = startedNanos / 1_000_000L;
        lastPairAt = now; // Include intentionally skipped pairs in the stream watchdog.
        boolean wasIdle = idle.isIdle();
        if (!idle.shouldAnalyze(now)) {
            stats.pair(epoch, pair.rgb.arrivalTimeNanos, pair.ir.arrivalTimeNanos, startedNanos,
                    -1, RgbIrSearchStats.Outcome.IDLE_SKIPPED);
            return;
        }

        HiFaceResult<FaceDetectionResult> processed = analyzePair(pair);
        HiFaceError error = processed.isFailure() ? processed.requireError() : null;
        if (error == null) idle.onDetection(now, !processed.requireValue().getFaces().isEmpty());
        if (wasIdle != idle.isIdle()) postIdleDisplay(epoch, idle.isIdle());
        boolean transientError = error != null && (error.getCode() == HiFaceErrorCode.NOT_READY
                || error.getCode() == HiFaceErrorCode.BUSY);
        RgbIrSearchStats.Outcome outcome = error == null ? RgbIrSearchStats.Outcome.ACCEPTED
                : transientError ? RgbIrSearchStats.Outcome.SKIPPED : RgbIrSearchStats.Outcome.ERROR;
        stats.pair(epoch, pair.rgb.arrivalTimeNanos, pair.ir.arrivalTimeNanos, startedNanos,
                SystemClock.elapsedRealtimeNanos() - startedNanos, outcome);
        // Initialization/throttling skip this pair; technical errors stop the session on main.
        if (outcome == RgbIrSearchStats.Outcome.ERROR)
            main.post(() -> { if (current(epoch)) failSearch(error); });
    }

    /** UVC rotates both streams; SDK borrows NV21/GRAY8 with the original UVC arrival timestamps. */
    private HiFaceResult<FaceDetectionResult> analyzePair(FramePair pair) {
        Nv21Planes rgb = pair.rgbPlanes();
        Yuv420Frame frame = new Yuv420Frame(rgb.y(), rgb.u(), rgb.v(), rgb.width, rgb.height,
                rgb.yRowStride, rgb.uRowStride, rgb.vRowStride, rgb.uvPixelStride,
                YuvColorRange.VIDEO, YuvColorMatrix.BT601, 0, false);
        return sdk.processFrame(new RgbIrFrame(frame,
                pair.ir.luma(), pair.ir.width, pair.ir.height, pair.ir.width,
                pair.sessionId, pair.pairId, pair.rgb.sequence, pair.ir.sequence,
                pair.rgb.arrivalTimeNanos / 1_000_000L, pair.ir.arrivalTimeNanos / 1_000_000L));
    }

    /** Update brightness on idle transitions; reject notifications from old or stalled streams. */
    private void postIdleDisplay(long epoch, boolean idle) {
        main.post(() -> {
            if (current(epoch)) displayPolicy.setIdle(idle
                    && SystemClock.elapsedRealtime() - lastPairAt <= UvcSearchIdlePolicy.PAIR_GAP_MS);
        });
    }

    private void failSearch(HiFaceError error) {
        HiFaceErrorCode code = error.getCode();
        failCapture(DemoErrorUi.messageFor(this, error), code == HiFaceErrorCode.NOT_READY
                || code == HiFaceErrorCode.PROCESSING_FAILED || code == HiFaceErrorCode.DATABASE_ERROR);
    }

    private void failCamera(String message, Throwable cause) {
        Log.w(TAG, message, cause);
        failCapture(getString(R.string.uvc_search_camera_unavailable), true);
    }

    private void failCapture(CharSequence message, boolean retry) {
        stopCapture();
        status.setText(message);
        offerRetry(retry);
    }

    private boolean current(long epoch) { return running && generation == epoch; }

    private Matrix analysisToPreview(int width, int height) {
        if (width <= 0 || height <= 0) return null;
        float scale = Math.min((float) preview.getWidth() / width, (float) preview.getHeight() / height);
        Matrix matrix = new Matrix();
        matrix.setScale(scale, scale);
        matrix.postTranslate((preview.getWidth() - width * scale) / 2, (preview.getHeight() - height * scale) / 2);
        return matrix;
    }

    private void updatePreviewTransform() {
        if (capture == null) return;
        DualCameraConfig config = actualConfig == null ? capture.config : actualConfig;
        transformPreview(preview, config.rgb.width, config.rgb.height, config.rgbRotationDegrees);
        transformPreview(irPreview, config.ir.width, config.ir.height, config.irRotationDegrees);
    }

    private void transformPreview(TextureView view, int width, int height, int rotation) {
        if (view.getWidth() > 0 && view.getHeight() > 0)
            view.setTransform(PreviewTransform.fitCenter(view.getWidth(), view.getHeight(), width, height, rotation));
    }

    private void updateDebugPreview() {
        boolean enabled = cameraSettings.debugEnabled();
        findViewById(R.id.uvcDebugPanel).setVisibility(enabled ? View.VISIBLE : View.GONE);
        if (enabled) renderDiagnostics(); else irOverlay.show(null);
    }

    /** Record current-generation IR diagnostics on main; the debug toggle changes display only. */
    private void renderInfrared(long epoch, InfraredSearchInfo info) {
        stats.core(epoch, info);
        if (cameraSettings.debugEnabled()) irOverlay.show(info);
    }

    private void clearResults() {
        overlay.clear();
        irOverlay.show(null);
        statusUi.clear();
    }

    private void renderDiagnostics() {
        if (cameraSettings.debugEnabled()) diagnostics.setText(RgbIrDiagnosticsFormatter.format(this,
                stats.snapshot(SystemClock.elapsedRealtimeNanos()),
                cameras == null ? null : cameras.pairingDiagnostics()));
    }

    /** Stop/errors cancel user intent; backgrounding preserves it until old cameras drain. 中文：离页后先排空再恢复。 */
    private void stopCapture() { stopCapture(true); }

    private void stopCapture(boolean cancelRequest) {
        if (cancelRequest) requested = false;
        // Invalidate callbacks before closing SDK/UVC; never join the frame thread on main.
        running = false;
        stats.stop(generation);
        ++generation;
        main.removeCallbacks(watchdog);
        main.removeCallbacks(diagnosticsTicker);
        clearResults();
        displayPolicy.stop();
        offerRetry(false);
        renderDiagnostics();
        FaceSearchSession previous = search;
        search = null;
        try {
            if (previous != null) previous.close();
        } finally {
            if (cameras == null) {
                surfaces.release();
            } else if (!closeBarrier.isOwnerClosing()) {
                closeBarrier.closing();
                cameras.close();
            }
            updateButtons();
            flushDeviceChanges();
        }
    }

    private boolean camerasIdle() { return cameras == null && !closeBarrier.isClosing(); }

    private boolean canEditCameras() { return camerasIdle() && !requested && !permissionPending; }

    private void updateButtons() {
        boolean editable = canEditCameras();
        findViewById(R.id.uvcStart).setEnabled(editable);
        cameraSettings.setEditable(editable);
        findViewById(R.id.uvcStop).setEnabled(requested || running);
        findViewById(R.id.uvcRetry).setEnabled(camerasIdle() && !permissionPending);
    }

    private void show(int text) { status.setText(text); }
    private void offerRetry(boolean enabled) {
        findViewById(R.id.uvcRetry).setVisibility(enabled ? View.VISIBLE : View.GONE);
    }
}
