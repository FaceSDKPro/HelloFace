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
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Target VGA for preview. The selected tier controls the separate analysis stream.
 */
final class CameraResolutions {
    private static final int MAX_TIER_CANDIDATES = 3;

    enum Tier {
        LOW(640, 480), MEDIUM(1280, 960), HIGH(1440, 1080);

        final Size size;

        Tier(int width, int height) {
            size = new Size(width, height);
        }
    }

    private CameraResolutions() {
    }

    static ResolutionSelector preview() {
        return selector(Tier.LOW.size, ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER);
    }

    static ResolutionSelector analysis(Size size) {
        // The fragment retries the next analysis size if CameraX cannot bind this stream pair.
        return selector(size, ResolutionStrategy.FALLBACK_RULE_NONE);
    }

    private static ResolutionSelector selector(Size size, int fallback) {
        return new ResolutionSelector.Builder()
                .setResolutionStrategy(new ResolutionStrategy(size, fallback)).build();
    }

    @SuppressLint("UnsafeOptInUsageError")
    static List<Size> analysisCandidates(CameraInfo camera, Tier tier) {
        StreamConfigurationMap map = Camera2CameraInfo.from(camera)
                .getCameraCharacteristic(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
        Size[] supported = map == null ? null : map.getOutputSizes(ImageFormat.YUV_420_888);
        Size standard = Tier.LOW.size;
        List<Size> sizes = new ArrayList<>();
        if (supported != null) {
            for (Size size : supported) {
                if (Math.max(size.getWidth(), size.getHeight()) <= Yuv420Frame.MAX_LONG_SIDE_PIXELS
                        && Math.min(size.getWidth(), size.getHeight()) <= Yuv420Frame.MAX_SHORT_SIDE_PIXELS
                        && (size.getWidth() & 1) == 0 && (size.getHeight() & 1) == 0
                        && size.getWidth() > 0 && size.getHeight() > 0 && !sizes.contains(size)) {
                    sizes.add(size);
                }
            }
        }
        if (sizes.isEmpty()) {
            // CameraX can still try the nominal sizes when Camera2 reports no usable sizes.
            return tier == Tier.LOW ? Collections.singletonList(standard) : Arrays.asList(tier.size, standard);
        }
        Comparator<Size> nearestStandard = (a, b) -> Double.compare(score(a, standard), score(b, standard));
        Size standardFallback = sizes.contains(standard) ? standard : Collections.min(sizes, nearestStandard);
        List<Size> candidates = new ArrayList<>();
        // Bound retries above VGA, then fall back to the size closest to VGA.
        if (tier != Tier.LOW) {
            Collections.sort(sizes, (a, b) -> {
                int byTier = Double.compare(score(a, tier.size), score(b, tier.size));
                return byTier != 0 ? byTier : nearestStandard.compare(a, b);
            });
            for (Size size : sizes) {
                if (pixels(size) > pixels(standard) && pixels(size) <= pixels(tier.size)
                        && !size.equals(standardFallback)) {
                    candidates.add(size);
                    if (candidates.size() == MAX_TIER_CANDIDATES) break;
                }
            }
        }
        candidates.add(standardFallback);
        return candidates;
    }

    private static double score(Size size, Size target) {
        double ratio = (double) Math.max(size.getWidth(), size.getHeight())
                / Math.min(size.getWidth(), size.getHeight());
        // Use pixel-count distance with a soft preference for 4:3 in either orientation.
        return Math.abs(pixels(size) - pixels(target)) + 100_000 * Math.abs(ratio - 4.0 / 3.0);
    }

    private static long pixels(Size size) {
        return (long) size.getWidth() * size.getHeight();
    }
}
