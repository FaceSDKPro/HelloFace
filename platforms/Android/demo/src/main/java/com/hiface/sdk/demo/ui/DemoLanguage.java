package com.hiface.sdk.demo.ui;

import java.util.Locale;

/** Demo 按系统地区选语言；SDK 的日志和错误消息不参与本地化。 */
public final class DemoLanguage {
    private DemoLanguage() {}

    public static String forRegion(String region) {
        String normalized = region == null ? "" : region.toUpperCase(Locale.ROOT);
        switch (normalized) {
            case "CN": case "HK": case "MO": case "TW": return "zh-Hans";
            default: return "en";
        }
    }
}
