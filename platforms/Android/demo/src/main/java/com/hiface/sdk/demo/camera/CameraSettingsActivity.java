package com.hiface.sdk.demo.camera;

import android.os.Bundle;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.SwitchCompat;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.ui.DemoWindowInsets;

/**
 * Two device settings shared by all Demo camera screens; changes save automatically.
 *
 * 所有 Demo 相机页面共用的两项设备设置，修改后自动保存。
 */
public final class CameraSettingsActivity extends AppCompatActivity {
    private static final int[] RESOLUTION_IDS = {
            R.id.cameraResolutionDefault, R.id.cameraResolutionMedium, R.id.cameraResolutionHigh
    };
    private static final int[] RESOLUTION_LABELS = {
            R.string.camera_settings_default, R.string.camera_settings_medium, R.string.camera_settings_high
    };

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_camera_settings);
        DemoWindowInsets.applyToContent(this);
        findViewById(R.id.backButton).setOnClickListener(view -> finish());

        CameraSettings settings = CameraSettings.load();
        RadioGroup resolution = findViewById(R.id.cameraResolution);
        SwitchCompat mirror = findViewById(R.id.cameraMirrorCoordinates);
        for (CameraResolutions.Tier tier : CameraResolutions.Tier.values()) {
            int index = tier.ordinal();
            RadioButton option = resolution.findViewById(RESOLUTION_IDS[index]);
            option.setText(getString(RESOLUTION_LABELS[index], tier.size.getWidth(), tier.size.getHeight()));
        }
        // Leave the radio group unchecked until the user has a saved override.
        if (settings.resolution != null) {
            resolution.check(RESOLUTION_IDS[settings.resolution.ordinal()]);
        }
        mirror.setChecked(settings.mirrorCoordinates);

        resolution.setOnCheckedChangeListener((group, checkedId) -> {
            for (CameraResolutions.Tier tier : CameraResolutions.Tier.values()) {
                if (checkedId == RESOLUTION_IDS[tier.ordinal()]) {
                    CameraSettings.setResolution(tier);
                    break;
                }
            }
        });
        mirror.setOnCheckedChangeListener((button, checked) -> CameraSettings.setMirrorCoordinates(checked));
    }
}
