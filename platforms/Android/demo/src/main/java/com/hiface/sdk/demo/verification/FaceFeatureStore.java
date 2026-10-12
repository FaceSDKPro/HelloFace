package com.hiface.sdk.demo.verification;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.hiface.sdk.demo.HiFaceDemoApplication;
import com.hiface.sdk.search.FaceFeatureFormat;
import com.tencent.mmkv.MMKV;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/** Demo 专用的1:1 加密 Face ID/特征 Key-Value 存储；不属于 SDK API。 */
final class FaceFeatureStore {
    // HF1 本身不携带模型身份；按特征空间分开保存，换模型后只展示当前空间的参考特征。
    private static final String KEY_PREFIX = "face:" + FaceFeatureFormat.FEATURE_SPACE_ID + ":";
    private final MMKV mmkv = HiFaceDemoApplication.getMMKV();

    boolean save(@NonNull String faceId, @NonNull String feature) {
        String normalizedId = normalize(faceId);
        if (normalizedId.isEmpty() || feature.trim().isEmpty()) {
            return false;
        }
        return mmkv.encode(KEY_PREFIX + normalizedId, feature);
    }

    @Nullable
    String getFeature(@NonNull String faceId) {
        String normalizedId = normalize(faceId);
        return normalizedId.isEmpty()
                ? null
                : mmkv.decodeString(KEY_PREFIX + normalizedId, null);
    }

    @NonNull
    List<String> getFaceIds() {
        String[] keys = mmkv.allKeys();
        if (keys == null || keys.length == 0) {
            return Collections.emptyList();
        }
        List<String> ids = new ArrayList<>();
        for (String key : keys) {
            if (key != null && key.startsWith(KEY_PREFIX)) {
                ids.add(key.substring(KEY_PREFIX.length()));
            }
        }
        Collections.sort(ids);
        return ids;
    }

    private static String normalize(String faceId) {
        return Objects.requireNonNull(faceId, "faceId").trim();
    }
}
