package com.hiface.sdk.demo.camera;

import androidx.annotation.Nullable;
import com.hiface.sdk.demo.HiFaceDemoApplication;
import com.tencent.mmkv.MMKV;

/**
 * Demo camera preferences store only the resolution preset and overlay mirror correction, outside SDK
 * inference configuration.
 *
 * Demo 的相机偏好；仅保存分辨率档位和叠加层镜像校正，不属于 SDK 推理配置。
 */
final class CameraSettings {
    private static final String LEGACY_HIGH_RESOLUTION = "camera:high_resolution";
    private static final String RESOLUTION_TIER = "camera:resolution_tier";
    private static final String MIRROR_COORDINATES = "camera:mirror_coordinates";

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
}
