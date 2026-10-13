package com.hiface.sdk.demo.ui;

import org.junit.Test;
import static org.junit.Assert.assertEquals;

public class DemoLanguageTest {
    @Test public void greaterChinaUsesChineseRegardlessOfSystemLanguage() {
        for (String region : new String[]{"CN", "HK", "MO", "TW", "cn", "hk"})
            assertEquals("zh-Hans", DemoLanguage.forRegion(region));
    }
    @Test public void otherAndUnknownRegionsUseEnglish() {
        for (String region : new String[]{"US", "GB", "SG", "MY", "JP", "", null})
            assertEquals("en", DemoLanguage.forRegion(region));
    }
}
