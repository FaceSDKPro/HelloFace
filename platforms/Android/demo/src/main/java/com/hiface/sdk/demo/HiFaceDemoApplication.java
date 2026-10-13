package com.hiface.sdk.demo;

import android.app.Application;
import android.content.res.Resources;
import androidx.appcompat.app.AppCompatDelegate;
import androidx.core.os.LocaleListCompat;
import androidx.core.os.ConfigurationCompat;
import com.hiface.sdk.demo.ui.DemoLanguage;

import com.tencent.mmkv.MMKV;

import java.util.Objects;
import java.util.Locale;

/** Demo 的相机设置和 1:1 人脸特征共用一个 MMKV；SDK 不依赖此存储。 */
public final class HiFaceDemoApplication extends Application {
    private static MMKV mmkv;

    public static MMKV getMMKV() {
        return mmkv;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        Locale primary = ConfigurationCompat.getLocales(Resources.getSystem().getConfiguration()).get(0);
        String region = primary == null ? null : primary.getCountry();
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(DemoLanguage.forRegion(region)));
        MMKV.initialize(this);
        // 固定密钥仅演示加密 API；生产应用应从 Keystore 或业务密钥系统获取。
        mmkv = Objects.requireNonNull(MMKV.mmkvWithID(
                "hiface_demo_faces", MMKV.SINGLE_PROCESS_MODE, "HiFaceDemoKey_16"));
    }
}
