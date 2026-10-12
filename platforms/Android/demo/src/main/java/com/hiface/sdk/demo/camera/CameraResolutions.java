package com.hiface.sdk.demo.camera;

import android.annotation.SuppressLint;
import android.graphics.ImageFormat;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.util.Size;

import androidx.camera.camera2.interop.Camera2CameraInfo;
import androidx.camera.core.CameraInfo;
import androidx.camera.core.resolutionselector.ResolutionSelector;
import androidx.camera.core.resolutionselector.ResolutionStrategy;

import com.hiface.sdk.frame.Yuv420Frame;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** 预览优先 VGA；分析最多尝试三个接近 720P 的实际尺寸，最后使用默认尺寸。 */
final class CameraResolutions {
    static final Size DEFAULT = new Size(640, 480);
    private static final long HIGH_PIXELS = 1280L * 720;

    private CameraResolutions() {}

    static ResolutionSelector preview() {
        return selector(DEFAULT, ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER);
    }

    static ResolutionSelector analysis(Size size) {
        return selector(size, ResolutionStrategy.FALLBACK_RULE_NONE);
    }

    private static ResolutionSelector selector(Size size, int fallback) {
        return new ResolutionSelector.Builder()
                .setResolutionStrategy(new ResolutionStrategy(size, fallback)).build();
    }

    @SuppressLint("UnsafeOptInUsageError")
    static List<Size> analysisCandidates(CameraInfo camera, boolean highResolution) {
        StreamConfigurationMap map = Camera2CameraInfo.from(camera)
                .getCameraCharacteristic(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
        Size[] supported = map == null ? null : map.getOutputSizes(ImageFormat.YUV_420_888);
        List<Size> sizes = new ArrayList<>();
        if (supported != null) {
            for (Size size : supported) {
                if (Math.max(size.getWidth(), size.getHeight()) <= Yuv420Frame.MAX_LONG_SIDE_PIXELS
                        && Math.min(size.getWidth(), size.getHeight()) <= Yuv420Frame.MAX_SHORT_SIDE_PIXELS
                        && !sizes.contains(size)) sizes.add(size);
            }
        }
        if (sizes.isEmpty()) return Collections.singletonList(DEFAULT);
        sortByPixels(sizes, pixels(DEFAULT));
        Size normal = sizes.contains(DEFAULT) ? DEFAULT : sizes.get(0);
        List<Size> candidates = new ArrayList<>();
        if (highResolution) {
            sortByPixels(sizes, HIGH_PIXELS);
            for (Size size : sizes) {
                if (pixels(size) > pixels(DEFAULT) && pixels(size) <= HIGH_PIXELS * 3 / 2
                        && !size.equals(normal)) candidates.add(size);
                if (candidates.size() == 3) break;
            }
        }
        candidates.add(normal);
        return candidates;
    }

    private static void sortByPixels(List<Size> sizes, long target) {
        Collections.sort(sizes, (a, b) -> Long.compare(
                Math.abs(pixels(a) - target), Math.abs(pixels(b) - target)));
    }

    private static long pixels(Size size) {
        return (long) size.getWidth() * size.getHeight();
    }
}
