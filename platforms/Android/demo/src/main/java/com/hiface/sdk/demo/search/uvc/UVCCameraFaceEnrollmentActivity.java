package com.hiface.sdk.demo.search.uvc;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.SurfaceTexture;
import android.hardware.usb.UsbDevice;
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
import androidx.activity.OnBackPressedCallback;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.ViewModelProvider;
import com.facesdkpro.uvccamera.CameraFailure;
import com.facesdkpro.uvccamera.CameraFrame;
import com.facesdkpro.uvccamera.Nv21Planes;
import com.facesdkpro.uvccamera.PreviewTransform;
import com.facesdkpro.uvccamera.StreamConfig;
import com.facesdkpro.uvccamera.UvcCameraManager;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.capture.FaceCaptureListener;
import com.hiface.sdk.capture.FaceCaptureResult;
import com.hiface.sdk.common.FaceRequest;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.common.HiFaceResult;
import com.hiface.sdk.demo.ui.DemoWindowInsets;
import com.hiface.sdk.detection.FaceDetectionResult;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.search.FaceSearchStore;
import com.hiface.sdk.demo.ui.CaptureStatusUi;
import com.hiface.sdk.demo.ui.DemoErrorUi;
import com.hiface.sdk.demo.ui.FaceCaptureOverlayView;
import com.hiface.sdk.flow.FaceFlowProgress;
import com.hiface.sdk.frame.Yuv420Frame;
import com.hiface.sdk.frame.YuvColorMatrix;
import com.hiface.sdk.frame.YuvColorRange;

/**
 * 双目模组的 RGB UVC 录入：直接给 SDK 稳定采集送 YUV，不打开内置相机或截图提特征。
 * 录入不提供 IR 活体结论；IR 与身份的联合判定仍由搜索会话完成。
 */
public final class UVCCameraFaceEnrollmentActivity extends AppCompatActivity {
    private static final String GROUP = "uvcEnrollmentGroup";
    private final Handler main = new Handler(Looper.getMainLooper());
    private final UvcCameraCloseBarrier closeBarrier = new UvcCameraCloseBarrier();
    private final UvcPreviewSurfaces surfaces = new UvcPreviewSurfaces();
    private HiFaceSdk sdk;
    private UvcEnrollmentState state;
    private UvcEnrollmentCameraSettings settings;
    private UvcEnrollmentConfirmation confirmation;
    private AlertDialog overwrite;
    private FaceSearchStore store;
    private FaceSearchStore.Request<?> saveRequest;
    private FaceRequest captureRequest;
    private UvcCameraManager manager;
    private TextureView preview;
    private FaceCaptureOverlayView overlay;
    private TextView status;
    private boolean started, saving;
    private volatile boolean running;
    private volatile long generation, lastFrameAt;
    private int rotation;

    static Intent intent(Context context, UsbDevice rgb, int rotation, String group) {
        Bundle choice = new Bundle();
        UvcEnrollmentCameraSettings.putChoice(choice, rgb, rotation);
        return new Intent(context, UVCCameraFaceEnrollmentActivity.class).putExtras(choice).putExtra(GROUP, group);
    }

    private final ActivityResultLauncher<String> permission = registerForActivityResult(
            new ActivityResultContracts.RequestPermission(), granted -> {
                state.permissionPending = false;
                if (!started || !state.requested) return;
                if (granted) startCapture();
                else fail(getString(R.string.camera_permission_required), true);
            });

    private final Runnable watchdog = new Runnable() {
        @Override public void run() {
            if (!running) return;
            if (SystemClock.elapsedRealtime() - lastFrameAt > 5000) {
                failCamera(); return;
            }
            main.postDelayed(this, 1000);
        }
    };

    @Override protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        setContentView(R.layout.activity_uvc_face_enrollment);
        DemoWindowInsets.applyToContent(this);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        state = new ViewModelProvider(this).get(UvcEnrollmentState.class);
        state.initialize(getIntent().getStringExtra(GROUP));
        sdk = HiFaceSdk.builder(this).lifecycleOwner(this).build();
        settings = new UvcEnrollmentCameraSettings(this, saved, getIntent().getExtras());
        preview = findViewById(R.id.uvcEnrollPreview);
        overlay = findViewById(R.id.uvcEnrollOverlay);
        status = findViewById(R.id.uvcEnrollStatus);
        findViewById(R.id.backButton).setOnClickListener(v -> finish());
        findViewById(R.id.uvcEnrollSettings).setOnClickListener(v -> showSettings());
        findViewById(R.id.uvcEnrollRetry).setOnClickListener(v -> {
            settings.refresh(); state.requested = true;
            if (settings.selected() == null) showSettings(); else startCapture();
        });
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override public void handleOnBackPressed() { finish(); }
        });
        preview.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
            @Override public void onSurfaceTextureAvailable(SurfaceTexture texture, int width, int height) { startCapture(); }
            @Override public void onSurfaceTextureSizeChanged(SurfaceTexture texture, int width, int height) { transformPreview(); }
            @Override public boolean onSurfaceTextureDestroyed(SurfaceTexture texture) {
                if (manager == null) return true;
                surfaces.retain(texture);
                stopCapture();
                return false;
            }
            @Override public void onSurfaceTextureUpdated(SurfaceTexture texture) {}
        });
    }

    private void showSettings() {
        if (state.pending != null) return;
        stopCapture();
        settings.show(() -> {
            if (!started || isFinishing()) return;
            state.requested = true; startCapture();
        });
    }

    private void startCapture() {
        if (!started || !state.requested || running || manager != null || closeBarrier.isClosing()
                || state.permissionPending || state.pending != null || settings.isShowing() || isFinishing() || isDestroyed()) return;
        UsbDevice rgb = settings.selected();
        if (rgb == null) { show(R.string.uvc_enroll_choose_rgb, true); return; }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            state.permissionPending = true; permission.launch(Manifest.permission.CAMERA); return;
        }
        if (!preview.isAvailable()) { show(R.string.uvc_enroll_opening, false); return; }
        final long epoch = ++generation;
        rotation = settings.rotation();
        state.errorText = null;
        running = true;
        overlay.resetCountdown();
        show(R.string.uvc_enroll_opening, false);
        try {
            captureRequest = sdk.capture().startCameraCapture(captureListener(epoch));
            Surface surface = surfaces.open(preview);
            manager = new UvcCameraManager(this, cameraListener(epoch));
            manager.open(rgb, StreamConfig.defaults(), surface, (camera, frame) -> processFrame(frame, epoch));
            transformPreview();
        } catch (RuntimeException | LinkageError error) { failCamera(); }
    }

    private FaceCaptureListener captureListener(long epoch) {
        return new FaceCaptureListener() {
            @Override public void onProgress(FaceFlowProgress progress) {
                if (current(epoch)) CaptureStatusUi.apply(overlay, progress.getStage());
            }
            @Override public void onResult(FaceCaptureResult result) {
                if (!current(epoch)) return;
                state.pending = result; state.requested = false;
                stopCapture();
                showConfirmation();
            }
            @Override public void onError(HiFaceError error) {
                if (!current(epoch)) return;
                failCapture(error);
            }
        };
    }

    private UvcCameraManager.Listener cameraListener(long epoch) {
        return new UvcCameraManager.Listener() {
            @Override public void onOpened(UvcCameraManager.Camera camera) {
                if (!current(epoch)) return;
                lastFrameAt = SystemClock.elapsedRealtime();
                show(R.string.uvc_enroll_guidance, false);
                main.postDelayed(watchdog, 1000);
            }
            @Override public void onFailure(CameraFailure failure) {
                if (!current(epoch)) return;
                Log.w("HiFaceUvcEnroll", "UVC " + failure.code + ", native=" + failure.nativeStatus);
                failCamera();
            }
            @Override public void onShutdown() {
                manager = null;
                surfaces.release();
                closeBarrier.closed();
            }
        };
    }

    /** native 帧只在本回调内同步借用；旋转交给 SDK，预览使用同角度的 GPU 变换。 */
    private void processFrame(CameraFrame frame, long epoch) {
        if (!current(epoch)) return;
        lastFrameAt = frame.callbackTimeNanos / 1_000_000L;
        Nv21Planes planes = Nv21Planes.from(frame.pixels(), frame.width, frame.height);
        HiFaceResult<FaceDetectionResult> result = sdk.processFrame(new Yuv420Frame(
                planes.y(), planes.u(), planes.v(), planes.width, planes.height,
                planes.yRowStride, planes.uRowStride, planes.vRowStride, planes.uvPixelStride,
                YuvColorRange.VIDEO, YuvColorMatrix.BT601, rotation, false));
        if (result.isFailure()) {
            HiFaceError error = result.requireError();
            if (error.getCode() != HiFaceErrorCode.NOT_READY && error.getCode() != HiFaceErrorCode.BUSY)
                main.post(() -> { if (current(epoch)) failCapture(error); });
        }
    }

    private boolean current(long epoch) { return running && generation == epoch; }

    private void showConfirmation() {
        if (!started || state.pending == null || confirmation != null) return;
        show(R.string.search_ui_confirm_title, false);
        confirmation = new UvcEnrollmentConfirmation(this, state, new UvcEnrollmentConfirmation.Listener() {
            @Override public void save(String id, String group) { saveCapture(id, group, false); }
            @Override public void retake() {
                confirmation = null; state.pending = null; state.requested = true; startCapture();
            }
            @Override public void cancel() { finish(); }
        });
        confirmation.show();
    }

    private void saveCapture(String id, String group, boolean replace) {
        if (saving || store == null || state.pending == null || confirmation == null) return;
        saving = true; confirmation.setSaving(true);
        long epoch = generation;
        saveRequest = store.save(id, state.pending.getFeature(), group, replace, saved -> {
            saveRequest = null; saving = false;
            if (!started || generation != epoch || confirmation == null || !confirmation.isShowing()) return;
            confirmation.setSaving(false);
            if (saved.isSuccess()) {
                state.pending = null;
                Toast.makeText(this, R.string.search_saved, Toast.LENGTH_SHORT).show();
                setResult(RESULT_OK); finish();
            } else if (saved.requireError().getCode() == HiFaceErrorCode.ALREADY_EXISTS) {
                overwrite = new MaterialAlertDialogBuilder(this).setTitle(R.string.search_exists)
                        .setMessage(getString(R.string.search_overwrite_message, id))
                        .setNegativeButton(android.R.string.cancel, null)
                        .setPositiveButton(R.string.search_overwrite, (d, w) -> saveCapture(id, group, true)).show();
            } else Toast.makeText(this, DemoErrorUi.messageFor(this, saved.requireError()), Toast.LENGTH_LONG).show();
        });
    }

    private void failCapture(HiFaceError error) {
        fail(DemoErrorUi.messageFor(this, error), DemoErrorUi.isRetryable(error));
    }

    private void failCamera() { fail(getString(R.string.uvc_enroll_camera_error), true); }

    private void fail(String message, boolean canRetry) {
        state.requested = false; stopCapture();
        state.errorText = message; state.retryError = canRetry;
        status.setText(message); retry(canRetry);
    }

    private void stopCapture() {
        // 先拒绝旧帧和异步结果，再释放采集请求、相机和预览。
        running = false;
        ++generation;
        main.removeCallbacks(watchdog);
        if (captureRequest != null) { captureRequest.cancel(); captureRequest = null; }
        if (overlay != null) overlay.resetCountdown();
        if (manager == null) {
            surfaces.release();
        } else if (!closeBarrier.isOwnerClosing()) {
            closeBarrier.closing();
            manager.close();
        }
    }

    private void transformPreview() {
        if (preview.getWidth() > 0 && preview.getHeight() > 0)
            preview.setTransform(PreviewTransform.centerCrop(preview.getWidth(), preview.getHeight(), 640, 480, rotation));
    }

    private void show(int message, boolean canRetry) { status.setText(message); retry(canRetry); }
    private void retry(boolean visible) { findViewById(R.id.uvcEnrollRetry).setVisibility(visible ? View.VISIBLE : View.GONE); }

    @Override protected void onStart() {
        super.onStart(); started = true;
        store = new FaceSearchStore(this);
        settings.refresh();
        closeBarrier.listen(this::startCapture);
        if (state.pending != null) showConfirmation();
        else if (state.requested) startCapture();
        else if (state.errorText != null) { status.setText(state.errorText); retry(state.retryError); }
    }

    @Override protected void onStop() {
        started = false; closeBarrier.listen(null);
        settings.dismiss();
        stopCapture();
        if (saveRequest != null) { saveRequest.cancel(); saveRequest = null; }
        saving = false;
        if (overwrite != null) { overwrite.dismiss(); overwrite = null; }
        if (confirmation != null) { confirmation.dismiss(); confirmation = null; }
        if (store != null) { store.close(); store = null; }
        super.onStop();
    }

    @Override public void finish() {
        // Back/保存完成都会先登记关闭；下层搜索页即使已 onStart 也不能抢开 USB。
        if (state != null) { state.requested = false; stopCapture(); }
        super.finish();
    }

    @Override protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        settings.save(out);
    }
}
