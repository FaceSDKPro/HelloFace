package com.hiface.sdk.demo.camera;

import android.Manifest;
import android.annotation.SuppressLint;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Matrix;
import android.graphics.Rect;
import android.hardware.camera2.CaptureRequest;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.util.Range;
import android.util.Size;
import android.view.LayoutInflater;
import android.view.Surface;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Toast;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.MainThread;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.StringRes;
import androidx.camera.camera2.interop.Camera2CameraControl;
import androidx.camera.camera2.interop.CaptureRequestOptions;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraInfo;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.CameraState;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.core.ResolutionInfo;
import androidx.camera.core.UseCaseGroup;
import androidx.camera.core.ViewPort;
import androidx.camera.core.ZoomState;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.camera.view.transform.CoordinateTransform;
import androidx.camera.view.transform.ImageProxyTransformFactory;
import androidx.camera.view.transform.OutputTransform;
import androidx.core.content.ContextCompat;
import androidx.core.math.MathUtils;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentManager;
import androidx.lifecycle.Observer;
import com.google.common.util.concurrent.ListenableFuture;
import com.hiface.sdk.demo.BuildConfig;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.frame.Yuv420Frame;
import com.hiface.sdk.frame.YuvColorMatrix;
import com.hiface.sdk.frame.YuvColorRange;
import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * CameraX adapter for permissions, preview, synchronous frame delivery, and coordinate mapping; the
 * SDK performs face analysis.
 * The camera must produce clear images; for face search, a camera with a wide dynamic range above
 * 105 dB is recommended.
 *
 * CameraX 采集适配器：权限、预览、同步送帧与坐标映射；人脸算法由 SDK 负责。
 * 摄像头需成像清晰，人脸搜索建议相机宽动态大于105DB。
 */
@SuppressLint("UnsafeOptInUsageError")
public final class CameraPreviewFragment extends Fragment {
    private static final String TAG = "CameraPreviewFragment";
    private static final long STARTUP_TIMEOUT_MS = 4000;
    private final Handler main = new Handler(Looper.getMainLooper());
    private ProcessCameraProvider provider;
    private PreviewView previewView;
    private ExecutorService analysisExecutor;
    private CameraResolutions.Tier defaultResolution = CameraResolutions.Tier.LOW;
    private CameraSettings settings = new CameraSettings(null, false);
    private CameraInfo selectedCamera;
    private List<Size> analysisSizes;
    private int resolutionIndex;
    // started tracks the view lifecycle. cameraRequested tracks the caller’s intent, and analysisPaused gates SDK
    // input.
    private boolean started, cameraRequested, analysisPaused, permissionPending, providerLoading;
    private boolean overlayEnabled;
    // Zero leaves the capture rate at the CameraX default.
    private int targetSessionFrameRate;
    private FrameListener frameListener;
    // The analyzer reads this snapshot of the main thread's frame delivery decision.
    private volatile FrameListener activeFrameListener;
    private Runnable cameraReadyListener;
    // Object identity identifies this binding; unbinding invalidates its old camera callbacks, analysis
    // tasks, and timeouts.
    // 对象身份就是本次绑定的凭据；解绑后旧相机回调、分析任务和超时任务自然失效。
    private volatile Binding binding;
    private final View.OnLayoutChangeListener previewLayoutListener =
            (v, l, t, r, b, ol, ot, or, ob) -> bindIfReady();

    private final ActivityResultLauncher<String> cameraPermission = registerForActivityResult(
            new ActivityResultContracts.RequestPermission(), granted -> {
                permissionPending = false;
                if (granted) {
                    bindIfReady();
                } else {
                    fail(R.string.camera_permission_required);
                }
            });

    /**
     * Consume YUV buffers synchronously on the analysis thread; ImageProxy closes after the callback, so
     * never retain the frame asynchronously.
     *
     * 在分析线程同步消费 YUV Buffer，回调返回后 ImageProxy 会被关闭，不可异步持有帧。
     */
    @FunctionalInterface
    public interface FrameListener {
        void onFrame(@NonNull Yuv420Frame frame);
    }

    @NonNull
    public static CameraPreviewFragment require(FragmentManager manager, int containerId) {
        Fragment fragment = manager.findFragmentById(containerId);
        if (!(fragment instanceof CameraPreviewFragment)) {
            throw new IllegalStateException("CameraPreviewFragment is missing for " + containerId);
        }
        return (CameraPreviewFragment) fragment;
    }

    /** Enable CameraX viewport mapping for overlays before registering the frame listener. */
    @MainThread
    public void enableOverlayPreview() {
        overlayEnabled = true;
        if (previewView != null) {
            previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        }
    }

    /** Request a capture rate without rebinding. The SDK controls search analysis cadence. */
    @MainThread
    public void setPreviewFrameRate(int fps) {
        if (fps <= 0) {
            throw new IllegalArgumentException("Frame rate must be positive");
        }
        if (targetSessionFrameRate == fps) {
            return;
        }
        targetSessionFrameRate = fps;
        Binding current = binding;
        if (current != null) {
            current.updateFrameRate(fps);
        }
    }

    @MainThread
    @Nullable
    public Matrix analysisToPreview(int width, int height) {
        Binding current = binding;
        FrameMapping source = current == null ? null : current.mapping;
        if (source == null || previewView == null || source.width != width || source.height != height) {
            return null;
        }
        OutputTransform target = previewView.getOutputTransform();
        if (target == null) {
            return null;
        }
        Matrix matrix = new Matrix();
        new CoordinateTransform(source.transform, target).transform(matrix);
        if (settings.mirrorCoordinates) {
            matrix.postScale(-1f, 1f, previewView.getWidth() * .5f, previewView.getHeight() * .5f);
        }
        return matrix;
    }

    @MainThread
    public boolean isFrontCamera() {
        return selectedCamera == null || lensFacing(selectedCamera) == CameraSelector.LENS_FACING_FRONT;
    }

    @MainThread
    public boolean switchCamera() {
        int facing = binding == null ? CameraSelector.LENS_FACING_UNKNOWN : lensFacing(selectedCamera);
        CameraInfo next = null;
        if (facing == CameraSelector.LENS_FACING_FRONT || facing == CameraSelector.LENS_FACING_BACK) {
            next = findCamera(provider.getAvailableCameraInfos(), facing == CameraSelector.LENS_FACING_FRONT
                    ? CameraSelector.LENS_FACING_BACK : CameraSelector.LENS_FACING_FRONT);
        }
        if (next == null) {
            if (isAdded()) {
                Toast.makeText(requireContext(), R.string.camera_switch_unavailable, Toast.LENGTH_SHORT).show();
            }
            return false;
        }
        unbind();
        selectedCamera = next;
        resetResolutions();
        bindIfReady();
        return true;
    }

    /**
     * Notify the host on the main thread after the first frame, excluding permission and camera-start
     * delays from the challenge timeout.
     *
     * 首帧到达后在主线程通知宿主，避免权限申请和相机启动耗时占用挑战时限。
     */
    @MainThread
    public void setCameraReadyListener(@NonNull Runnable listener) {
        cameraReadyListener = Objects.requireNonNull(listener);
    }

    @MainThread
    public boolean isCameraReady() {
        Binding current = binding;
        return started && current != null && current.hasFrame;
    }

    /**
     * Start automatically after listener registration. Stop admitting new SDK frames when the View stops,
     * but let in-flight synchronous callbacks finish.
     *
     * 设置监听器后自动启动；View 停止时禁止新帧进入 SDK，已经开始的同步回调允许自然返回。
     */
    @MainThread
    public void setFrameListener(@NonNull FrameListener listener) {
        setFrameListener(listener, true);
    }

    @MainThread
    void setFrameListener(@NonNull FrameListener listener, boolean analysisEnabled) {
        frameListener = Objects.requireNonNull(listener);
        activeFrameListener = null;
        analysisPaused = !analysisEnabled;
        cameraRequested = true;
        updateFrameDelivery();
        bindIfReady();
    }

    private void stopCamera() {
        cameraRequested = false;
        updateFrameDelivery();
        unbind();
    }

    /**
     * Pause only SDK analysis; keep the preview and camera use cases bound.
     *
     * 只暂停送入 SDK 的分析，预览和相机用例保持绑定。
     */
    @MainThread
    public void pauseAnalysis() {
        analysisPaused = true;
        updateFrameDelivery();
    }

    @MainThread
    public void resumeAnalysis() {
        Objects.requireNonNull(frameListener, "Set frame listener before resuming analysis");
        analysisPaused = false;
        updateFrameDelivery();
    }

    private void updateFrameDelivery() {
        FrameListener registered = frameListener;
        if (!started || !cameraRequested || analysisPaused || registered == null) {
            activeFrameListener = null;
        } else if (activeFrameListener == null) {
            // A new identity rejects queued frames that reach the delivery check after pause and resume.
            activeFrameListener = new FrameListener() {
                @Override
                public void onFrame(@NonNull Yuv420Frame frame) {
                    registered.onFrame(frame);
                }
            };
        }
    }

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup container,
            @Nullable Bundle state) {
        View view = inflater.inflate(R.layout.fragment_camera_preview, container, false);
        previewView = view.findViewById(R.id.previewView);
        previewView.setImplementationMode(overlayEnabled
                ? PreviewView.ImplementationMode.COMPATIBLE : PreviewView.ImplementationMode.PERFORMANCE);
        previewView.setScaleType(PreviewView.ScaleType.FIT_CENTER);
        // Wait for actual layout events instead of repeatedly posting tasks to wait for ViewPort.
        // 等待真实布局事件，不循环 post 等待 ViewPort。
        previewView.addOnLayoutChangeListener(previewLayoutListener);
        analysisExecutor = Executors.newSingleThreadExecutor(r -> new Thread(r, "HiFaceDemo-CameraAnalysis"));
        return view;
    }

    private void loadProvider() {
        if (providerLoading) {
            return;
        }
        providerLoading = true;
        Context context = requireContext().getApplicationContext();
        ListenableFuture<ProcessCameraProvider> future = ProcessCameraProvider.getInstance(context);
        // CameraProvider initialization belongs to the process; leaving the screen neither cancels it nor
        // allows it to retain the Fragment strongly.
        // CameraProvider 初始化属于进程级任务，页面退出不取消它，也不能让它强持有 Fragment。
        WeakReference<CameraPreviewFragment> owner = new WeakReference<>(this);
        future.addListener(() -> {
            CameraPreviewFragment fragment = owner.get();
            if (fragment != null) {
                fragment.onProviderReady(future);
            }
        }, ContextCompat.getMainExecutor(context));
    }

    private void onProviderReady(ListenableFuture<ProcessCameraProvider> future) {
        providerLoading = false;
        try {
            provider = future.get();
            bindIfReady();
        } catch (Exception error) {
            Log.e(TAG, "CameraProvider init failed", error);
            if (previewView != null) {
                fail(R.string.camera_start_failed);
            }
        }
    }

    @Override
    public void onStart() {
        super.onStart();
        started = true;
        CameraSettings next = CameraSettings.load();
        if (next.resolutionOr(defaultResolution) != settings.resolutionOr(defaultResolution)) {
            unbind();
            resetResolutions();
        }
        settings = next;
        updateFrameDelivery();
        if (binding == null) {
            bindIfReady();
        } else {
            binding.hasFrame = false;
            binding.opened = false;
            watchStartup(binding);
        }
    }

    public void useSearchResolutionByDefault() {
        defaultResolution = CameraResolutions.Tier.HIGH;
    }

    @Override
    public void onStop() {
        started = false;
        updateFrameDelivery();
        if (binding != null) {
            main.removeCallbacks(binding.startupCheck);
        }
        super.onStop();
    }

    @Override
    public void onDestroyView() {
        stopCamera();
        frameListener = null;
        cameraReadyListener = null;
        main.removeCallbacksAndMessages(null);
        if (previewView != null) {
            previewView.removeOnLayoutChangeListener(previewLayoutListener);
        }
        previewView = null;
        if (analysisExecutor != null) {
            analysisExecutor.shutdown();
        }
        analysisExecutor = null;
        super.onDestroyView();
    }

    /**
     * Single binding entry point: wait for the screen, permissions, CameraProvider, and layout to be
     * ready.
     *
     * 唯一绑定入口：等待页面、权限、CameraProvider 和布局全部就绪。
     */
    @SuppressLint("MissingPermission")
    private void bindIfReady() {
        if (!started || !cameraRequested || binding != null || previewView == null) {
            return;
        }
        if (ContextCompat.checkSelfPermission(requireContext(), Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) {
            if (!permissionPending) {
                permissionPending = true;
                cameraPermission.launch(Manifest.permission.CAMERA);
            }
            return;
        }
        if (provider == null) {
            loadProvider();
            return;
        }
        if (previewView.getWidth() == 0 || previewView.getHeight() == 0) {
            return;
        }
        ViewPort viewport = overlayEnabled ? previewView.getViewPort() : null;
        if (overlayEnabled && viewport == null) {
            return;
        }
        Binding next = null;
        try {
            if (selectedCamera == null) {
                selectedCamera = chooseCamera();
                if (selectedCamera == null) {
                    Log.w(TAG, "No available camera");
                    fail(R.string.camera_start_failed);
                    return;
                }
            }
            if (analysisSizes == null) {
                analysisSizes = CameraResolutions.analysisCandidates(selectedCamera,
                        settings.resolutionOr(defaultResolution));
                Log.i(TAG, "Analysis resolution candidates: " + analysisSizes);
            }
            int rotation = previewView.getDisplay() == null
                    ? Surface.ROTATION_0 : previewView.getDisplay().getRotation();
            next = new Binding(analysisSizes.get(resolutionIndex), rotation);
            binding = next;
            next.preview.setSurfaceProvider(previewView.getSurfaceProvider());
            UseCaseGroup.Builder group = new UseCaseGroup.Builder().addUseCase(next.preview).addUseCase(next.analysis);
            if (viewport != null) {
                group.setViewPort(viewport);
            }
            next.camera = provider.bindToLifecycle(getViewLifecycleOwner(), selectedCamera.getCameraSelector(),
                    group.build());
            if (targetSessionFrameRate > 0) {
                next.updateFrameRate(targetSessionFrameRate);
            }
            next.camera.getCameraInfo().getCameraState().observe(getViewLifecycleOwner(), next.observer);
            ResolutionInfo previewInfo = next.preview.getResolutionInfo();
            ResolutionInfo analysisInfo = next.analysis.getResolutionInfo();
            Log.i(TAG, "Camera bound; actualPreview=" + (previewInfo == null ? "pending" : previewInfo.getResolution())
                    + "; actualAnalysis=" + (analysisInfo == null ? "pending" : analysisInfo.getResolution())
                    + "; lensFacing=" + lensFacing(next.camera.getCameraInfo())
                    + "; mirrorCoordinates=" + settings.mirrorCoordinates);
            watchStartup(next);
        } catch (RuntimeException error) {
            Log.e(TAG, "Camera bind failed", error);
            if (next == null) {
                fail(R.string.camera_start_failed);
            } else {
                handleFailure(next, true);
            }
        }
    }

    private void watchStartup(Binding current) {
        main.removeCallbacks(current.startupCheck);
        main.postAtTime(current.startupCheck, current, SystemClock.uptimeMillis() + STARTUP_TIMEOUT_MS);
    }

    private void onCameraState(Binding current, CameraState state) {
        if (binding != current || !started) {
            return;
        }
        CameraState.StateError error = state.getError();
        if (state.getType() == CameraState.Type.OPEN && error == null) {
            current.opened = true;
        }
        if (error == null || error.getCode() == CameraState.ERROR_CAMERA_IN_USE
                || error.getCode() == CameraState.ERROR_MAX_CAMERAS_IN_USE) {
            return;
        }
        boolean retry = isResolutionError(error);
        // CameraInfo can replay an earlier error; use the startup timeout until the newly bound camera
        // actually opens.
        // CameraInfo 会重放上一轮错误；新绑定实际打开前，交给启动超时处理。
        if (retry && !current.opened) {
            return;
        }
        Log.w(TAG, "CameraState error=" + error.getCode());
        current.post(() -> handleFailure(current, retry));
    }


    private static boolean isResolutionError(CameraState.StateError error) {
        return error != null && (error.getCode() == CameraState.ERROR_STREAM_CONFIG
                || error.getCode() == CameraState.ERROR_OTHER_RECOVERABLE_ERROR);
    }

    private void checkStartup(Binding current) {
        if (binding != current || !started) {
            return;
        }
        if (current.hasFrame && previewView.getPreviewStreamState().getValue() == PreviewView.StreamState.STREAMING) {
            Log.i(TAG, "Camera streaming; resolutionAttempt=" + (resolutionIndex + 1));
            return;
        }
        CameraState state = current.camera.getCameraInfo().getCameraState().getValue();
        boolean retry = state != null && (state.getType() == CameraState.Type.OPEN || isResolutionError(
                state.getError()));
        Log.w(TAG, "Camera startup timeout");
        handleFailure(current, retry);
    }

    private void handleFailure(Binding current, boolean retry) {
        if (binding != current || !started) {
            return;
        }
        if (retry && resolutionIndex + 1 < analysisSizes.size()) {
            unbind();
            resolutionIndex++;
            showToast(R.string.camera_resolution_downgrade);
            main.post(this::bindIfReady);
        } else {
            fail(R.string.camera_start_failed);
        }
    }

    private void resetResolutions() {
        analysisSizes = null;
        resolutionIndex = 0;
    }

    @Nullable
    private CameraInfo chooseCamera() {
        int preferred = CameraSelector.LENS_FACING_FRONT;
        List<CameraInfo> cameras = provider.getAvailableCameraInfos();
        CameraInfo camera = findCamera(cameras, preferred);
        if (camera == null) {
            int alternate = preferred == CameraSelector.LENS_FACING_FRONT
                    ? CameraSelector.LENS_FACING_BACK : CameraSelector.LENS_FACING_FRONT;
            camera = findCamera(cameras, alternate);
        }
        return camera == null && !cameras.isEmpty() ? cameras.get(0) : camera;
    }

    @Nullable
    private static CameraInfo findCamera(List<CameraInfo> cameras, int facing) {
        for (CameraInfo camera : cameras) {
            if (lensFacing(camera) == facing) {
                return camera;
            }
        }
        return null;
    }

    private static int lensFacing(CameraInfo camera) {
        try {
            return camera.getLensFacing();
        } catch (IllegalArgumentException ignored) {
            return CameraSelector.LENS_FACING_UNKNOWN;
        }
    }

    private void fail(@StringRes int message) {
        stopCamera();
        showToast(message);
    }

    private void showToast(@StringRes int message) {
        if (isAdded()) {
            Toast.makeText(requireContext(), message, Toast.LENGTH_LONG).show();
        }
    }

    // Invalidate the binding first, then detach its callbacks and CameraX use cases.
    private void unbind() {
        Binding old = binding;
        binding = null;
        if (old == null) {
            return;
        }
        old.releaseCallbacks();
        if (old.camera != null) {
            old.camera.getCameraInfo().getCameraState().removeObserver(old.observer);
        }
        old.analysis.clearAnalyzer();
        old.preview.setSurfaceProvider(null);
        provider.unbind(old.preview, old.analysis);
    }

    /**
     * Create and release all resources for a binding together; share only frame markers and immutable
     * coordinate snapshots across threads.
     *
     * 同一绑定的资源一起创建、一起释放；线程间只共享帧标记和不可变的坐标快照。
     */
    private final class Binding {
        final Preview preview;
        final ImageAnalysis analysis;
        final ImageProxyTransformFactory transforms = new ImageProxyTransformFactory();
        final Observer<CameraState> observer = state -> onCameraState(this, state);
        final Runnable startupCheck = () -> checkStartup(this);
        final boolean mirrored = isFrontCamera();
        Camera camera;
        boolean opened;
        // The first valid analysis frame marks camera readiness, even while SDK delivery is paused.
        volatile boolean hasFrame;
        volatile FrameMapping mapping;

        /**
         * Synchronize with unbinding so analysis cannot enqueue callbacks for an old View after the main queue
         * is cleared.
         *
         * 与解绑互斥，防止分析线程在清空主队列后才投递旧 View 的回调。
         */
        synchronized void post(Runnable action) {
            if (binding == this) {
                main.postAtTime(action, this, SystemClock.uptimeMillis());
            }
        }

        synchronized void releaseCallbacks() {
            main.removeCallbacksAndMessages(this);
        }

        Binding(Size size, int rotation) {
            transforms.setUsingRotationDegrees(true);
            transforms.setUsingCropRect(false);
            Preview.Builder previewBuilder = new Preview.Builder().setTargetRotation(rotation)
                    .setResolutionSelector(CameraResolutions.preview());
            if (targetSessionFrameRate > 0) {
                previewBuilder.setTargetFrameRate(
                        new Range<>(targetSessionFrameRate, targetSessionFrameRate));
            }
            preview = previewBuilder.build();
            analysis = new ImageAnalysis.Builder().setTargetRotation(rotation)
                    .setResolutionSelector(CameraResolutions.analysis(size))
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build();
            analysis.setAnalyzer(analysisExecutor, this::analyze);
        }

        /** Update capture without rebinding the camera. */
        void updateFrameRate(int framesPerSecond) {
            try {
                Range<Integer> range = selectFrameRateRange(camera.getCameraInfo(), framesPerSecond);
                if (range == null) {
                    Log.w(TAG, "No usable AE range for " + framesPerSecond + " fps");
                    return;
                }
                Log.i(TAG, "Camera frame-rate request=" + framesPerSecond + " fps; supported AE range=" + range);
                CaptureRequestOptions options = new CaptureRequestOptions.Builder()
                        .setCaptureRequestOption(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, range).build();
                Camera2CameraControl.from(camera.getCameraControl()).addCaptureRequestOptions(options);
            } catch (RuntimeException error) {
                Log.w(TAG, "Unable to apply AE frame rate", error);
            }
        }

        void analyze(ImageProxy image) {
            try {
                if (binding != this) {
                    return;
                }
                FrameListener listener = activeFrameListener;
                boolean firstFrame = !hasFrame;
                if (listener == null && !firstFrame) {
                    return;
                }
                ImageProxy.PlaneProxy[] planes = image.getPlanes();
                if (planes.length < 3) {
                    return;
                }
                int width = image.getWidth();
                int height = image.getHeight();
                if (firstFrame) {
                    hasFrame = true;
                    Log.i(TAG, "First analysis frame: " + width + "x" + height);
                    post(() -> {
                        if (binding == this && started && cameraReadyListener != null) {
                            cameraReadyListener.run();
                        }
                    });
                }
                if (listener == null) {
                    return;
                }
                int rotation = image.getImageInfo().getRotationDegrees();
                if (overlayEnabled) {
                    Rect crop = image.getCropRect();
                    if (mapping == null || !mapping.matches(width, height, rotation, crop)) {
                        mapping = new FrameMapping(width, height, rotation, crop, transforms.getOutputTransform(image));
                    }
                }
                Yuv420Frame frame = new Yuv420Frame(planes[0].getBuffer(), planes[1].getBuffer(), planes[2].getBuffer(),
                        width, height, planes[0].getRowStride(), planes[1].getRowStride(),
                        planes[2].getRowStride(), planes[1].getPixelStride(), YuvColorRange.VIDEO, YuvColorMatrix.BT601,
                        rotation, mirrored);
                if (binding == this && activeFrameListener == listener) {
                    listener.onFrame(frame);
                }
            } catch (RuntimeException error) {
                Log.e(TAG, "Frame analysis failed", error);
            } finally {
                image.close();
            }
        }
    }

    /** Select from the AE ranges advertised by the bound camera. */
    @Nullable
    private static Range<Integer> selectFrameRateRange(CameraInfo cameraInfo, int framesPerSecond) {
        List<Range<Integer>> supported = new ArrayList<>(cameraInfo.getSupportedFrameRateRanges());
        int[][] ranges = new int[supported.size()][2];
        for (int i = 0; i < supported.size(); i++) {
            ranges[i][0] = supported.get(i).getLower();
            ranges[i][1] = supported.get(i).getUpper();
        }
        int index = CameraFrameRatePolicy.selectIndex(framesPerSecond, ranges);
        return index < 0 ? null : supported.get(index);
    }

    /**
     * Reuse the transform while dimensions, rotation, and crop stay unchanged; apply extra mirroring after
     * mapping into the View on the main thread.
     *
     * 输入尺寸、旋转和裁剪不变时复用映射；额外镜像在主线程映射到 View 后处理。
     */
    private static final class FrameMapping {
        final int inputWidth, inputHeight, rotation, width, height;
        final Rect crop;
        final OutputTransform transform;

        FrameMapping(int inputWidth, int inputHeight, int rotation, Rect crop, OutputTransform transform) {
            this.inputWidth = inputWidth;
            this.inputHeight = inputHeight;
            this.rotation = rotation;
            width = rotation % 180 == 0 ? inputWidth : inputHeight;
            height = rotation % 180 == 0 ? inputHeight : inputWidth;
            this.crop = new Rect(crop);
            this.transform = transform;
        }

        boolean matches(int inputWidth, int inputHeight, int rotation, Rect crop) {
            return this.inputWidth == inputWidth && this.inputHeight == inputHeight
                    && this.rotation == rotation && this.crop.equals(crop);
        }
    }
}
