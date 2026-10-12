package com.hiface.sdk.demo;

import android.app.Application;

import com.tencent.mmkv.MMKV;

import java.util.Objects;

/** Demo 的相机设置和 1:1 人脸特征共用一个 MMKV；SDK 不依赖此存储。 */
public final class HiFaceDemoApplication extends Application {
    private static MMKV mmkv;

    public static MMKV getMMKV() {
        return mmkv;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        MMKV.initialize(this);
        // 固定密钥仅演示加密 API；生产应用应从 Keystore 或业务密钥系统获取。
        mmkv = Objects.requireNonNull(MMKV.mmkvWithID(
                "hiface_demo_faces", MMKV.SINGLE_PROCESS_MODE, "HiFaceDemoKey_16"));
    }
}
