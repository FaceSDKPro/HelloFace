package com.hiface.sdk.demo.camera;

import com.hiface.sdk.demo.HiFaceDemoApplication;
import com.tencent.mmkv.MMKV;

/** Demo 的相机偏好；仅保存分辨率档位和叠加层镜像校正，不属于 SDK 推理配置。 */
final class CameraSettings {
    private static final String HIGH_RESOLUTION = "camera:high_resolution";
    private static final String MIRROR_COORDINATES = "camera:mirror_coordinates";

    final boolean highResolution;
    final boolean mirrorCoordinates;

    CameraSettings(boolean highResolution, boolean mirrorCoordinates) {
        this.highResolution = highResolution;
        this.mirrorCoordinates = mirrorCoordinates;
    }

    static CameraSettings load() {
        MMKV mmkv = HiFaceDemoApplication.getMMKV();
        return new CameraSettings(mmkv.decodeBool(HIGH_RESOLUTION, false),
                mmkv.decodeBool(MIRROR_COORDINATES, false));
    }

    static void setHighResolution(boolean enabled) {
        HiFaceDemoApplication.getMMKV().encode(HIGH_RESOLUTION, enabled);
    }

    static void setMirrorCoordinates(boolean enabled) {
        HiFaceDemoApplication.getMMKV().encode(MIRROR_COORDINATES, enabled);
    }
}
