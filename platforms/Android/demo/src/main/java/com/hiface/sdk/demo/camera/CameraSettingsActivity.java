package com.hiface.sdk.demo.camera;

import android.os.Bundle;
import android.widget.RadioGroup;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.SwitchCompat;

import com.hiface.sdk.demo.R;

/** 所有 Demo 相机页面共用的两项设备设置，修改后自动保存。 */
public final class CameraSettingsActivity extends AppCompatActivity {
    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_camera_settings);
        findViewById(R.id.backButton).setOnClickListener(view -> finish());

        CameraSettings settings = CameraSettings.load();
        RadioGroup resolution = findViewById(R.id.cameraResolution);
        SwitchCompat mirror = findViewById(R.id.cameraMirrorCoordinates);
        resolution.check(settings.highResolution
                ? R.id.cameraResolutionHigh : R.id.cameraResolutionDefault);
        mirror.setChecked(settings.mirrorCoordinates);

        resolution.setOnCheckedChangeListener((group, checkedId) ->
                CameraSettings.setHighResolution(checkedId == R.id.cameraResolutionHigh));
        mirror.setOnCheckedChangeListener((button, checked) -> CameraSettings.setMirrorCoordinates(checked));
    }
}
