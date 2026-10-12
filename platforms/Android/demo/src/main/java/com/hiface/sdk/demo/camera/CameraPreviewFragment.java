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
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.camera.view.transform.CoordinateTransform;
import androidx.camera.view.transform.ImageProxyTransformFactory;
import androidx.camera.view.transform.OutputTransform;
import androidx.core.content.ContextCompat;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentManager;
import androidx.lifecycle.Observer;

import com.google.common.util.concurrent.ListenableFuture;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.frame.Yuv420Frame;
import com.hiface.sdk.frame.YuvColorMatrix;
import com.hiface.sdk.frame.YuvColorRange;

import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** CameraX 采集适配器：权限、预览、同步送帧与坐标映射；人脸算法由 SDK 负责。 */
@SuppressLint("UnsafeOptInUsageError")
public final class CameraPreviewFragment extends Fragment {
    private static final String TAG = "CameraPreviewFragment";
    private static final long STARTUP_TIMEOUT_MS = 4000;
    private final Handler main = new Handler(Looper.getMainLooper());
    private ProcessCameraProvider provider;
    private PreviewView previewView;
    private ExecutorService analysisExecutor;
    private CameraSettings settings = new CameraSettings(false, false);
    private CameraInfo selectedCamera;
    private List<Size> analysisSizes;
    private int resolutionIndex;
    private boolean started, cameraRequested, analysisPaused, permissionPending, providerLoading;
    private boolean overlayEnabled;
    // 0 表示沿用设备默认；搜索页会在活跃 15 FPS 与无人脸待机 5 FPS 之间动态切换。
    private volatile int targetSessionFrameRate;
    private PreviewView.ScaleType scaleType = PreviewView.ScaleType.FIT_CENTER;
    private volatile boolean deliverFrames;
    private volatile FrameListener frameListener;
    private Runnable cameraReadyListener;
    // 对象身份就是本次绑定的凭据；解绑后旧相机回调、分析任务和超时任务自然失效。
    private volatile Binding binding;
    private final View.OnLayoutChangeListener previewLayoutListener =
            (v, l, t, r, b, ol, ot, or, ob) -> bindIfReady();

    private final ActivityResultLauncher<String> cameraPermission = registerForActivityResult(
            new ActivityResultContracts.RequestPermission(), granted -> {
                permissionPending = false;
                if (granted) bindIfReady();
                else fail(R.string.camera_permission_required);
            });

    /** 在分析线程同步消费 YUV Buffer，回调返回后 ImageProxy 会被关闭，不可异步持有帧。 */
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

    /** 检测用 FIT_CENTER，搜索用 FILL_CENTER；Overlay 共用 CameraX 裁剪、旋转和镜像映射。 */
    @MainThread
    public void configureOverlayPreview(PreviewView.ScaleType scaleType) {
        overlayEnabled = true;
        this.scaleType = Objects.requireNonNull(scaleType);
        if (previewView != null) {
            previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
            previewView.setScaleType(scaleType);
        }
        if (binding != null) {
            unbind();
            bindIfReady();
        }
    }

    /** 更新相机与分析的目标帧率，不重建用例；硬件不支持时由 Analyzer 时间戳门禁兜底。 */
    @MainThread
    public void configureSessionFrameRate(int framesPerSecond) {
        if (framesPerSecond <= 0) {
            throw new IllegalArgumentException("framesPerSecond must be positive");
        }
        if (targetSessionFrameRate == framesPerSecond) return;
        targetSessionFrameRate = framesPerSecond;
        Binding current = binding;
        if (current != null) current.updateFrameRate(framesPerSecond);
    }

    @MainThread
    @Nullable
    public Matrix analysisToPreview(int width, int height) {
        Binding current = binding;
        FrameMapping source = current == null ? null : current.mapping;
        OutputTransform target = previewView == null ? null : previewView.getOutputTransform();
        if (source == null || target == null || source.width != width || source.height != height) return null;
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
        if (binding == null || selectedCamera == null) return false;
        int facing = lensFacing(selectedCamera);
        if (facing != CameraSelector.LENS_FACING_FRONT && facing != CameraSelector.LENS_FACING_BACK) return false;
        CameraInfo next = findCamera(facing == CameraSelector.LENS_FACING_FRONT
                ? CameraSelector.LENS_FACING_BACK : CameraSelector.LENS_FACING_FRONT);
        if (next == null) return false;
        unbind();
        selectedCamera = next;
        resetResolutions();
        bindIfReady();
        return true;
    }

    /** 首帧到达后在主线程通知宿主，避免权限申请和相机启动耗时占用挑战时限。 */
    @MainThread
    public void setCameraReadyListener(@NonNull Runnable listener) {
        cameraReadyListener = Objects.requireNonNull(listener);
    }

    @MainThread
    public boolean isCameraReady() {
        Binding current = binding;
        return started && current != null && current.hasFrame;
    }

    /** 设置监听器后自动启动；View 停止时禁止新帧进入 SDK，已经开始的同步回调允许自然返回。 */
    @MainThread
    public void setFrameListener(@NonNull FrameListener listener) {
        frameListener = Objects.requireNonNull(listener);
        analysisPaused = false;
        startCamera();
    }

    @MainThread
    public void startCamera() {
        Objects.requireNonNull(frameListener, "Set frame listener before starting camera");
        cameraRequested = true;
        updateFrameDelivery();
        bindIfReady();
    }

    @MainThread
    public void stopCamera() {
        cameraRequested = false;
        updateFrameDelivery();
        unbind();
    }

    /** 只暂停送入 SDK 的分析，预览和相机用例保持绑定。 */
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
        deliverFrames = started && cameraRequested && !analysisPaused && frameListener != null;
    }

    @Override
    public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup container,
                             @Nullable Bundle state) {
        View view = inflater.inflate(R.layout.fragment_camera_preview, container, false);
        previewView = view.findViewById(R.id.previewView);
        previewView.setImplementationMode(overlayEnabled
                ? PreviewView.ImplementationMode.COMPATIBLE : PreviewView.ImplementationMode.PERFORMANCE);
        previewView.setScaleType(scaleType);
        // 等待真实布局事件，不循环 post 等待 ViewPort。
        previewView.addOnLayoutChangeListener(previewLayoutListener);
        analysisExecutor = Executors.newSingleThreadExecutor(r -> new Thread(r, "HiFaceDemo-CameraAnalysis"));
        return view;
    }

    private void loadProvider() {
        if (providerLoading) return;
        providerLoading = true;
        Context context = requireContext().getApplicationContext();
        ListenableFuture<ProcessCameraProvider> future = ProcessCameraProvider.getInstance(context);
        // CameraProvider 初始化属于进程级任务，页面退出不取消它，也不能让它强持有 Fragment。
        WeakReference<CameraPreviewFragment> owner = new WeakReference<>(this);
        future.addListener(() -> {
            CameraPreviewFragment fragment = owner.get();
            if (fragment != null) fragment.onProviderReady(future);
        }, ContextCompat.getMainExecutor(context));
    }

    private void onProviderReady(ListenableFuture<ProcessCameraProvider> future) {
        providerLoading = false;
        try {
            provider = future.get();
            bindIfReady();
        } catch (Exception error) {
            Log.e(TAG, "CameraProvider init failed", error);
            if (previewView != null) fail(R.string.camera_start_failed);
        }
    }

    @Override
    public void onStart() {
        super.onStart();
        started = true;
        CameraSettings next = CameraSettings.load();
        if (next.highResolution != settings.highResolution) {
            unbind();
            resetResolutions();
        }
        settings = next;
        updateFrameDelivery();
        if (binding == null) bindIfReady();
        else {
            binding.hasFrame = false;
            binding.opened = false;
            watchStartup(binding);
        }
    }

    @Override
    public void onStop() {
        started = false;
        updateFrameDelivery();
        if (binding != null) main.removeCallbacks(binding.startupCheck);
        super.onStop();
    }

    @Override
    public void onDestroyView() {
        stopCamera();
        frameListener = null;
        cameraReadyListener = null;
        main.removeCallbacksAndMessages(null);
        if (previewView != null) previewView.removeOnLayoutChangeListener(previewLayoutListener);
        previewView = null;
        if (analysisExecutor != null) analysisExecutor.shutdown();
        analysisExecutor = null;
        super.onDestroyView();
    }

    /** 唯一绑定入口：等待页面、权限、CameraProvider 和布局全部就绪。 */
    @SuppressLint("MissingPermission")
    private void bindIfReady() {
        if (!started || !cameraRequested || binding != null || previewView == null) return;
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
        if (previewView.getWidth() == 0 || previewView.getHeight() == 0
                || (overlayEnabled && previewView.getViewPort() == null)) return;
        Binding next = null;
        try {
            if (selectedCamera == null) selectedCamera = chooseCamera();
            if (analysisSizes == null) {
                analysisSizes = CameraResolutions.analysisCandidates(selectedCamera, settings.highResolution);
                Log.i(TAG, "Analysis resolution candidates: " + analysisSizes);
            }
            int rotation = previewView.getDisplay() == null
                    ? Surface.ROTATION_0 : previewView.getDisplay().getRotation();
            next = new Binding(analysisSizes.get(resolutionIndex), rotation);
            binding = next;
            next.preview.setSurfaceProvider(previewView.getSurfaceProvider());
            UseCaseGroup.Builder group = new UseCaseGroup.Builder().addUseCase(next.preview).addUseCase(next.analysis);
            if (overlayEnabled) group.setViewPort(previewView.getViewPort());
            next.camera = provider.bindToLifecycle(getViewLifecycleOwner(), selectedCamera.getCameraSelector(), group.build());
            // 初次绑定/切镜头也下发实际支持的档位，不能只在 15/5 FPS 切换时更新。
            if (targetSessionFrameRate > 0) next.updateFrameRate(targetSessionFrameRate);
            next.camera.getCameraInfo().getCameraState().observe(getViewLifecycleOwner(), next.observer);
            ResolutionInfo previewInfo = next.preview.getResolutionInfo();
            ResolutionInfo analysisInfo = next.analysis.getResolutionInfo();
            Log.i(TAG, "Camera bound; actualPreview=" + (previewInfo == null ? "pending" : previewInfo.getResolution())
                    + "; actualAnalysis=" + (analysisInfo == null ? "pending" : analysisInfo.getResolution())
                    + "; mirrorCoordinates=" + settings.mirrorCoordinates);
            watchStartup(next);
        } catch (RuntimeException error) {
            Log.e(TAG, "Camera bind failed", error);
            if (next == null) fail(R.string.camera_start_failed);
            else handleFailure(next, true);
        }
    }

    private void watchStartup(Binding current) {
        main.removeCallbacks(current.startupCheck);
        main.postAtTime(current.startupCheck, current, SystemClock.uptimeMillis() + STARTUP_TIMEOUT_MS);
    }

    private void onCameraState(Binding current, CameraState state) {
        if (binding != current || !started) return;
        CameraState.StateError error = state.getError();
        if (state.getType() == CameraState.Type.OPEN && error == null) current.opened = true;
        if (error == null || error.getCode() == CameraState.ERROR_CAMERA_IN_USE
                || error.getCode() == CameraState.ERROR_MAX_CAMERAS_IN_USE) return;
        boolean retry = isResolutionError(error);
        // CameraInfo 会重放上一轮错误；新绑定实际打开前，交给启动超时处理。
        if (retry && !current.opened) return;
        Log.w(TAG, "CameraState error=" + error.getCode());
        current.post(() -> handleFailure(current, retry));
    }

    private static boolean isResolutionError(CameraState.StateError error) {
        return error != null && (error.getCode() == CameraState.ERROR_STREAM_CONFIG
                || error.getCode() == CameraState.ERROR_OTHER_RECOVERABLE_ERROR);
    }

    private void checkStartup(Binding current) {
        if (binding != current || !started) return;
        if (current.hasFrame && previewView.getPreviewStreamState().getValue() == PreviewView.StreamState.STREAMING) {
            Log.i(TAG, "Camera streaming; resolutionAttempt=" + (resolutionIndex + 1));
            return;
        }
        CameraState state = current.camera.getCameraInfo().getCameraState().getValue();
        boolean retry = state != null && (state.getType() == CameraState.Type.OPEN || isResolutionError(state.getError()));
        Log.w(TAG, "Camera startup timeout");
        handleFailure(current, retry);
    }

    private void handleFailure(Binding current, boolean retry) {
        if (binding != current || !started) return;
        unbind();
        if (retry && resolutionIndex + 1 < analysisSizes.size()) {
            resolutionIndex++;
            if (resolutionIndex == 1) showToast(R.string.camera_resolution_downgrade);
            main.post(this::bindIfReady);
        } else fail(R.string.camera_start_failed);
    }

    private void resetResolutions() {
        analysisSizes = null;
        resolutionIndex = 0;
    }

    private CameraInfo chooseCamera() {
        CameraInfo camera = findCamera(CameraSelector.LENS_FACING_FRONT);
        if (camera == null) camera = findCamera(CameraSelector.LENS_FACING_BACK);
        if (camera == null) camera = provider.getAvailableCameraInfos().get(0);
        return camera;
    }

    private CameraInfo findCamera(int facing) {
        if (provider != null) {
            for (CameraInfo camera : provider.getAvailableCameraInfos()) {
                if (lensFacing(camera) == facing) return camera;
            }
        }
        return null;
    }

    private static int lensFacing(CameraInfo camera) {
        try { return camera.getLensFacing(); }
        catch (IllegalArgumentException ignored) { return CameraSelector.LENS_FACING_UNKNOWN; }
    }

    private void fail(@StringRes int message) {
        stopCamera();
        showToast(message);
    }

    private void showToast(@StringRes int message) {
        if (isAdded()) Toast.makeText(requireContext(), message, Toast.LENGTH_LONG).show();
    }

    private void unbind() {
        Binding old = binding;
        binding = null;
        if (old == null) return;
        old.releaseCallbacks();
        if (old.camera != null) old.camera.getCameraInfo().getCameraState().removeObserver(old.observer);
        old.analysis.clearAnalyzer();
        old.preview.setSurfaceProvider(null);
        provider.unbind(old.preview, old.analysis);
    }

    /** 同一绑定的资源一起创建、一起释放；线程间只共享帧标记和不可变的坐标快照。 */
    private final class Binding {
        final Preview preview;
        final ImageAnalysis analysis;
        final ImageProxyTransformFactory transforms = new ImageProxyTransformFactory();
        final Observer<CameraState> observer = state -> onCameraState(this, state);
        final Runnable startupCheck = () -> checkStartup(this);
        final boolean mirrored = isFrontCamera();
        Camera camera;
        boolean opened;
        private boolean released;
        volatile boolean hasFrame;
        volatile FrameMapping mapping;
        volatile long lastDeliveredTimestampNanos = Long.MIN_VALUE;

        /** 与解绑互斥，防止分析线程在清空主队列后才投递旧 View 的回调。 */
        synchronized void post(Runnable action) {
            if (!released) main.postAtTime(action, this, SystemClock.uptimeMillis());
        }

        synchronized void releaseCallbacks() {
            released = true;
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

        /** 只更新已有会话的 AE 请求；没有合适硬件档位时由 analyze() 的时间戳门禁兜底。 */
        void updateFrameRate(int framesPerSecond) {
            lastDeliveredTimestampNanos = Long.MIN_VALUE;
            if (camera == null) return;
            try {
                requestFrameRate(framesPerSecond);
            } catch (RuntimeException error) {
                // AE 调整是尽力而为的省电策略；厂商不支持时不能打断预览或触发分辨率回退。
                Log.w(TAG, "Unable to apply AE frame rate; throttling Analyzer only", error);
            }
        }

        private void requestFrameRate(int framesPerSecond) {
            Range<Integer> range = selectFrameRateRange(camera.getCameraInfo(), framesPerSecond);
            if (range == null) {
                Log.w(TAG, "Camera has no usable AE frame-rate range for " + framesPerSecond
                        + " fps; keeping preview continuous and throttling Analyzer only");
                return;
            }
            Log.i(TAG, "Camera frame-rate request=" + framesPerSecond + " fps; supported AE range=" + range);
            CaptureRequestOptions options = new CaptureRequestOptions.Builder()
                    .setCaptureRequestOption(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, range)
                    .build();
            Camera2CameraControl.from(camera.getCameraControl()).addCaptureRequestOptions(options);
        }

        void analyze(ImageProxy image) {
            try {
                if (binding != this) return;
                ImageProxy.PlaneProxy[] planes = null;
                if (!hasFrame) {
                    planes = image.getPlanes();
                    if (planes.length < 3) return;
                    hasFrame = true;
                    Log.i(TAG, "First analysis frame: " + image.getWidth() + "x" + image.getHeight());
                    post(() -> {
                        if (binding == this && started && cameraReadyListener != null) {
                            cameraReadyListener.run();
                        }
                    });
                }
                FrameListener listener = frameListener;
                if (!deliverFrames || listener == null) return;
                int analysisFrameRate = targetSessionFrameRate;
                if (analysisFrameRate > 0) {
                    long timestamp = image.getImageInfo().getTimestamp();
                    long minimumInterval = Math.max(0L,
                            1_000_000_000L / analysisFrameRate - 2_000_000L);
                    if (lastDeliveredTimestampNanos != Long.MIN_VALUE
                            && timestamp >= lastDeliveredTimestampNanos
                            && timestamp - lastDeliveredTimestampNanos < minimumInterval) {
                        return;
                    }
                    lastDeliveredTimestampNanos = timestamp;
                }
                // 待机/暂停丢弃的帧不必创建 PlaneProxy/ByteBuffer 包装或做坐标映射。
                if (planes == null) planes = image.getPlanes();
                if (planes.length < 3) return;
                if (overlayEnabled && (mapping == null || !mapping.matches(image))) {
                    mapping = new FrameMapping(image, transforms);
                }
                Yuv420Frame frame = new Yuv420Frame(planes[0].getBuffer(), planes[1].getBuffer(), planes[2].getBuffer(),
                        image.getWidth(), image.getHeight(), planes[0].getRowStride(), planes[1].getRowStride(),
                        planes[2].getRowStride(), planes[1].getPixelStride(), YuvColorRange.VIDEO, YuvColorMatrix.BT601,
                        image.getImageInfo().getRotationDegrees(), mirrored);
                if (deliverFrames && binding == this && frameListener == listener) listener.onFrame(frame);
            } catch (RuntimeException error) {
                Log.e(TAG, "Frame analysis failed", error);
            } finally {
                image.close();
            }
        }
    }

    /** 只下发 HAL 声明的取值；不支持 5 FPS 时也选择可用的最低采集上限。 */
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

    /** 输入尺寸、旋转和裁剪不变时复用映射；额外镜像在主线程映射到 View 后处理。 */
    private static final class FrameMapping {
        final int inputWidth, inputHeight, rotation, width, height;
        final Rect crop;
        final OutputTransform transform;

        FrameMapping(ImageProxy image, ImageProxyTransformFactory factory) {
            inputWidth = image.getWidth();
            inputHeight = image.getHeight();
            rotation = image.getImageInfo().getRotationDegrees();
            width = rotation % 180 == 0 ? inputWidth : inputHeight;
            height = rotation % 180 == 0 ? inputHeight : inputWidth;
            crop = new Rect(image.getCropRect());
            transform = factory.getOutputTransform(image);
        }

        boolean matches(ImageProxy image) {
            return inputWidth == image.getWidth() && inputHeight == image.getHeight()
                    && rotation == image.getImageInfo().getRotationDegrees() && crop.equals(image.getCropRect());
        }
    }
}
