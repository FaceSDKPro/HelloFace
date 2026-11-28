package com.hiface.sdk.demo.camera;

import androidx.annotation.Nullable;
import com.hiface.sdk.demo.HiFaceDemoApplication;
import com.tencent.mmkv.MMKV;

/**
 * Demo device-capture and overlay preferences, outside SDK inference configuration.
 *
 * Demo 的相机采集与叠加层偏好，不属于 SDK 推理配置。
 */
final class CameraSettings {
    static final float[] ZOOM_PRESETS = {0.8f, 1f, 2f, 3f};
    private static final float DEFAULT_ZOOM_RATIO = 1f;
    private static final String LEGACY_HIGH_RESOLUTION = "camera:high_resolution";
    private static final String RESOLUTION_TIER = "camera:resolution_tier";
    private static final String MIRROR_COORDINATES = "camera:mirror_coordinates";
    private static final String ZOOM_RATIO = "camera:zoom_ratio";
    private static final String PREFER_BACK_CAMERA = "camera:prefer_back_camera";

    // An unset tier lets live search use High and the other camera features use Low.
    @Nullable final CameraResolutions.Tier resolution;
    final boolean mirrorCoordinates;

    CameraSettings(@Nullable CameraResolutions.Tier resolution, boolean mirrorCoordinates) {
        this.resolution = resolution;
        this.mirrorCoordinates = mirrorCoordinates;
    }

    CameraResolutions.Tier resolutionOr(CameraResolutions.Tier fallback) {
        return resolution == null ? fallback : resolution;
    }

    static CameraSettings load() {
        MMKV mmkv = HiFaceDemoApplication.getMMKV();
        String stored = mmkv.decodeString(RESOLUTION_TIER);
        CameraResolutions.Tier selected = null;
        for (CameraResolutions.Tier tier : CameraResolutions.Tier.values()) {
            if (tier.name().equals(stored)) {
                selected = tier;
                break;
            }
        }
        // The old switch selected VGA or 720p. Read it only if the tier key is absent.
        if (stored == null && mmkv.containsKey(LEGACY_HIGH_RESOLUTION)) {
            selected = mmkv.decodeBool(LEGACY_HIGH_RESOLUTION)
                    ? CameraResolutions.Tier.MEDIUM : CameraResolutions.Tier.LOW;
        }
        return new CameraSettings(selected, mmkv.decodeBool(MIRROR_COORDINATES, false));
    }

    static void setResolution(CameraResolutions.Tier tier) {
        HiFaceDemoApplication.getMMKV().encode(RESOLUTION_TIER, tier.name());
    }

    static void setMirrorCoordinates(boolean enabled) {
        HiFaceDemoApplication.getMMKV().encode(MIRROR_COORDINATES, enabled);
    }

    static int zoomPresetIndex() {
        float ratio = HiFaceDemoApplication.getMMKV().decodeFloat(ZOOM_RATIO, DEFAULT_ZOOM_RATIO);
        return nearestZoomPresetIndex(ratio);
    }

    static int nearestZoomPresetIndex(float ratio) {
        if (!(ratio > 0f) || Float.isInfinite(ratio)) {
            ratio = DEFAULT_ZOOM_RATIO;
        }
        // Existing installs may have a value from the old continuous slider.
        for (int i = 1; i < ZOOM_PRESETS.length; i++) {
            if (ratio < (ZOOM_PRESETS[i - 1] + ZOOM_PRESETS[i]) / 2f) {
                return i - 1;
            }
        }
        return ZOOM_PRESETS.length - 1;
    }

    static float zoomRatio() {
        return ZOOM_PRESETS[zoomPresetIndex()];
    }

    static void setZoomPreset(int position) {
        HiFaceDemoApplication.getMMKV().encode(ZOOM_RATIO, ZOOM_PRESETS[position]);
    }

    static boolean prefersBackCamera() {
        return HiFaceDemoApplication.getMMKV().decodeBool(PREFER_BACK_CAMERA, false);
    }

    static void setPrefersBackCamera(boolean back) {
        HiFaceDemoApplication.getMMKV().encode(PREFER_BACK_CAMERA, back);
    }
}
