package com.hiface.sdk.demo.search.uvc;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Matrix;
import android.graphics.SurfaceTexture;
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
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.widget.PopupMenu;
import androidx.core.content.ContextCompat;
import com.facesdkpro.uvccamera.CameraFailure;
import com.facesdkpro.uvccamera.DualCameraConfig;
import com.facesdkpro.uvccamera.DualCameraSession;
import com.facesdkpro.uvccamera.FramePair;
import com.facesdkpro.uvccamera.Nv21Planes;
import com.facesdkpro.uvccamera.PreviewTransform;
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
import java.util.ArrayList;
import java.util.List;

/**
 * 双目搜索接入页：管理采集和搜索会话；设备表单、结果展示及亮度策略各自独立。
 * 普通 FaceSearchActivity 不依赖本页。身份与 IR 活体的最终结论由 SDK 对同一采样作出。
 *
 * <p>界面和会话生命周期由主线程管理。UVC-pairs 线程负责送帧、分析节流和同步借用像素。
 * generation 使停止后的旧回调失效；日志不记录图像、人脸特征、身份或评分。</p>
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
    private TextureView preview, irPreview;
    private Surface previewSurface, irPreviewSurface;
    // TextureView 销毁时仍可能有 native 帧在途，等 UVC onClosed 后再释放对应纹理。
    private final List<SurfaceTexture> retiredTextures = new ArrayList<>();
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
    // requested 是用户运行意图，退到后台仍保留；running 表示当前会话允许接收回调。
    private boolean started, requested, permissionPending, closing;
    private volatile boolean running;
    private volatile long generation, lastPairAt;

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
            // 两路各自有帧也可能配不成对；这时及时清掉旧身份/框，不能一直显示上次通过。
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

    private void bindViews(Bundle state) {
        preview = findViewById(R.id.uvcPreview);
        irPreview = findViewById(R.id.uvcIrPreview);
        irOverlay = findViewById(R.id.uvcIrOverlay);
        diagnostics = findViewById(R.id.uvcDiagnostics);
        overlay = findViewById(R.id.uvcOverlay);
        overlay.setAssociationEnabled(false); // 双目身份和 IR 结论不跨采样关联。
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
        findViewById(R.id.uvcLibrary).setOnClickListener(v -> openPage(FaceSearchLibraryActivity.class));
        findViewById(R.id.uvcEnroll).setOnClickListener(v -> openPage(UVCCameraFaceEnrollmentActivity.intent(
                this, cameraSettings.selectedRgbDevice(), cameraSettings.rgbRotationDegrees(), searchOptions.getGroup())));
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
                    retiredTextures.add(texture);
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
        // 授权可能在停止或离开后返回，不能借此重新启动采集。
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
        menu.getMenu().findItem(R.id.uvcCameraSettings).setEnabled(canEditCameras());
        menu.setOnMenuItemClickListener(item -> {
            if (item.getItemId() == R.id.uvcSearchSettings) showSearchSettings();
            else if (item.getItemId() == R.id.uvcCameraSettings) showCameraSettings();
            return true;
        });
        menu.show();
    }

    /** 设备与预览参数只在空闲时修改，运行中的搜索参数可单独应用。 */
    private void showCameraSettings() {
        if (canEditCameras()) cameraSettings.show(() -> {
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

    private void openPage(Class<?> page) { openPage(new Intent(this, page)); }

    private void openPage(Intent page) {
        // 先停止准入并登记 USB 关闭，再切换页面；录入页只在排空完成后打开同一 RGB 相机。
        started = false;
        stopCapture(false);
        startActivity(page);
    }

    private void refreshDevices() {
        if (cameras != null || closing) return;
        try {
            show(cameraSettings.refreshDevices());
        } catch (RuntimeException error) {
            failCamera("Cannot enumerate UVC cameras", error);
        }
    }

    /** 先校验设备和 IR 配置，再等待权限与 Surface；每次继续启动都重新检查用户意图。 */
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
            return; // 由 onSurfaceTextureAvailable 继续，停止操作可撤销本次 requested。
        }

        capture = selection;
        final long epoch = ++generation;
        stats.start(epoch, SystemClock.elapsedRealtimeNanos());
        statusUi.clear();
        try {
            // IR 是显式模式。SDK 不通过关闭 RGB 活体来隐式放行，也不会使用旧 IR 通过结果。
            search = sdk.search().startCameraSearch(
                    UvcSearchSettingsDialog.withInfrared(searchOptions, capture.infrared), searchListener(epoch));
            previewSurface = new Surface(preview.getSurfaceTexture());
            if (cameraSettings.debugEnabled()) irPreviewSurface = new Surface(irPreview.getSurfaceTexture());
            running = true;
            displayPolicy.start();
            lastPairAt = SystemClock.elapsedRealtime();
            UvcSearchIdlePolicy idle = new UvcSearchIdlePolicy();
            // 先保存句柄再启动：失败回调也能沿统一关闭路径释放相机与 Surface。
            cameras = DualCameraSession.create(this, capture.rgb, capture.ir, capture.config,
                    previewSurface, irPreviewSurface, cameraListener(epoch), pair -> processPair(pair, epoch, idle));
            cameras.start();
            updatePreviewTransform();
            show(R.string.uvc_search_opening);
            main.post(diagnosticsTicker);
        } catch (RuntimeException error) {
            // 搜索启动和 Surface 创建也包含在清理范围内，不能留下占用相机槽位的半启动会话。
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
                lastPairAt = SystemClock.elapsedRealtime();
                statusUi.camerasReady();
                // 两路 USB 授权可先后弹窗，配对看门狗只能在两路真正打开后启动。
                main.postDelayed(watchdog, 500);
            }
            @Override public void onError(DualCameraSession source, String message, Throwable cause) {
                if (!current(epoch)) return;
                failCamera(message, cause);
            }
            @Override public void onFailure(DualCameraSession source, DualCameraSession.Role role, CameraFailure failure) {
                if (!current(epoch)) return;
                int hint;
                switch (failure.code) {
                    case USB_PERMISSION_DENIED:
                    case USB_PERMISSION_TIMEOUT: hint = R.string.uvc_search_usb_permission; break;
                    case CAMERA_CLOSED:
                    case DEVICE_DETACHED: hint = R.string.uvc_search_usb_detached; break;
                    case STREAM_TIMEOUT: hint = R.string.uvc_search_stream_timeout; break;
                    case PAIR_TIMEOUT: hint = R.string.uvc_search_pair_timeout; break;
                    default: hint = R.string.uvc_search_camera_unavailable;
                }
                String message = getString(hint);
                if (role != null) {
                    int camera = role == DualCameraSession.Role.RGB
                            ? R.string.uvc_search_rgb_camera : R.string.uvc_search_ir_camera;
                    message = getString(R.string.uvc_search_camera_failure, getString(camera), message);
                }
                failCapture(message, true);
                // 只记录技术代码，不在日志输出图像、身份或评分。
                Log.w(TAG, "UVC " + role + ": " + failure.code + ", native=" + failure.nativeStatus);
            }
            @Override public void onClosed(DualCameraSession source) {
                if (cameras != source) return;
                cameras = null;
                closing = false;
                // 此回调保证 USB/native 和在途 pair 消费均已排空。
                releasePreview();
                updateButtons();
                closeBarrier.closed();
            }
        };
    }

    /** UVC-pairs 线程同步借用像素；回调返回即失效，不能把 pair/ByteBuffer post 到主线程。 */
    private void processPair(FramePair pair, long epoch, UvcSearchIdlePolicy idle) {
        if (!current(epoch)) return;
        long startedNanos = SystemClock.elapsedRealtimeNanos();
        long now = startedNanos / 1_000_000L;
        lastPairAt = now; // 看门狗观察实际配对流量，包括主动跳过的帧对。
        boolean wasIdle = idle.isIdle();
        if (!idle.shouldAnalyze(now)) {
            stats.pair(epoch, pair.rgb.arrivalTimeNanos, pair.ir.arrivalTimeNanos, startedNanos,
                    -1, RgbIrSearchStats.Outcome.IDLE_SKIPPED);
            return;
        }

        Nv21Planes rgb = pair.rgbPlanes();
        Yuv420Frame frame = new Yuv420Frame(rgb.y(), rgb.u(), rgb.v(), rgb.width, rgb.height,
                rgb.yRowStride, rgb.uRowStride, rgb.vRowStride, rgb.uvPixelStride,
                YuvColorRange.VIDEO, YuvColorMatrix.BT601, 0, false);
        // UVC 已完成独立旋转。调试预览使用 Surface，算法仍直接借用 GRAY8，不截图或转 Bitmap。
        HiFaceResult<FaceDetectionResult> processed = sdk.processFrame(new RgbIrFrame(frame,
                pair.ir.luma(), pair.ir.width, pair.ir.height, pair.ir.width,
                pair.sessionId, pair.pairId, pair.rgb.sequence, pair.ir.sequence,
                pair.rgb.arrivalTimeNanos / 1_000_000L, pair.ir.arrivalTimeNanos / 1_000_000L));
        HiFaceError error = processed.isFailure() ? processed.requireError() : null;
        if (error == null) idle.onDetection(now, !processed.requireValue().getFaces().isEmpty());
        if (wasIdle != idle.isIdle()) postIdleDisplay(epoch, idle.isIdle());
        boolean transientError = error != null && (error.getCode() == HiFaceErrorCode.NOT_READY
                || error.getCode() == HiFaceErrorCode.BUSY);
        RgbIrSearchStats.Outcome outcome = error == null ? RgbIrSearchStats.Outcome.ACCEPTED
                : transientError ? RgbIrSearchStats.Outcome.SKIPPED : RgbIrSearchStats.Outcome.ERROR;
        stats.pair(epoch, pair.rgb.arrivalTimeNanos, pair.ir.arrivalTimeNanos, startedNanos,
                SystemClock.elapsedRealtimeNanos() - startedNanos, outcome);
        // 初始化、节流和背压只跳过本对帧；技术错误切回主线程停止整个会话。
        if (outcome == RgbIrSearchStats.Outcome.ERROR)
            main.post(() -> { if (current(epoch)) failSearch(error); });
    }

    /** 只在待机状态变化时刷新亮度，旧会话或已断流的通知不会再把页面调暗。 */
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
        DualCameraConfig config = capture.config;
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

    /** 主动停止/错误会撤销运行意图；页面暂时离开则保留，返回后等待旧相机排空再恢复。 */
    private void stopCapture() { stopCapture(true); }

    private void stopCapture(boolean cancelRequest) {
        if (cancelRequest) requested = false;
        // 先作废回调，再关 SDK/UVC；主线程不等待帧线程退出。
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
            if (cameras != null && !closing) {
                closing = true;
                closeBarrier.closing();
                cameras.close();
            } else if (cameras == null) {
                releasePreview(); // 未创建相机句柄时，Surface 可以直接释放。
            }
            updateButtons();
        }
    }

    private void releasePreview() {
        if (previewSurface != null) {
            previewSurface.release();
            previewSurface = null;
        }
        if (irPreviewSurface != null) { irPreviewSurface.release(); irPreviewSurface = null; }
        for (SurfaceTexture texture : retiredTextures) texture.release();
        retiredTextures.clear();
    }

    private boolean camerasIdle() { return cameras == null && !closing && !closeBarrier.isClosing(); }

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

    @Override protected void onStart() {
        super.onStart();
        started = true;
        closeBarrier.listen(() -> {
            updateButtons();
            startCapture();
        });
        updateButtons();
        startCapture();
    }

    @Override protected void onStop() {
        started = false;
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
}
