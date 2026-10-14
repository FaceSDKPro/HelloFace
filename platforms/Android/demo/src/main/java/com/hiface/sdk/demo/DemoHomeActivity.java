package com.hiface.sdk.demo;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.DrawableRes;
import androidx.annotation.IdRes;
import androidx.annotation.NonNull;
import androidx.annotation.StringRes;
import androidx.appcompat.app.AppCompatActivity;

import com.hiface.sdk.demo.comparison.FaceComparisonActivity;
import com.hiface.sdk.demo.camera.CameraSettingsActivity;
import com.hiface.sdk.demo.detection.FaceDetectionActivity;
import com.hiface.sdk.demo.liveness.FaceLivenessActivity;
import com.hiface.sdk.demo.search.FaceSearchActivity;
import com.hiface.sdk.demo.verification.FaceEnrollmentActivity;
import com.hiface.sdk.demo.verification.FaceVerificationActivity;

/** Demo 首页：SDK 功能与相机设置入口。 */
public final class DemoHomeActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_demo_home);
        TextView deviceInfo = findViewById(R.id.deviceInfoText);
        String deviceInfoText = Build.VERSION.RELEASE + "/" + Build.MODEL + "/" + Build.BOARD;
        deviceInfo.setText(deviceInfoText);
        deviceInfo.setOnLongClickListener(view -> {
            Log.i("DeviceInfo", deviceInfoText);
            ClipboardManager clipboard = getSystemService(ClipboardManager.class);
            if (clipboard != null) {
                clipboard.setPrimaryClip(ClipData.newPlainText("DeviceInfo", deviceInfoText));
                // Android 13+ already shows the system clipboard confirmation.
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    Toast.makeText(this, R.string.device_info_copied, Toast.LENGTH_SHORT).show();
                }
            }
            return true;
        });

        //Log.d("DeviceInfo","设备信息： "+Build.VERSION.RELEASE+","+Build.MODEL+","+Build.BOARD);
        bindFeatureCard(R.id.featureFaceDetection, android.R.drawable.ic_menu_camera,
                R.string.feature_face_detection, R.string.feature_face_detection_desc,
                FaceDetectionActivity.class);
        bindFeatureCard(R.id.featureFaceEnroll, android.R.drawable.ic_input_add,
                R.string.feature_face_enroll, R.string.feature_face_enroll_desc,
                FaceEnrollmentActivity.class);
        bindFeatureCard(R.id.featureFaceVerification, R.drawable.ic_api_verified,
                R.string.feature_face_verification, R.string.feature_face_verification_desc,
                FaceVerificationActivity.class);
        bindFeatureCard(R.id.featureFaceLiveness, android.R.drawable.ic_menu_view,
                R.string.feature_face_liveness, R.string.feature_face_liveness_desc,
                FaceLivenessActivity.class);
        bindFeatureCard(R.id.featureFaceSearch, android.R.drawable.ic_menu_search,
                R.string.feature_face_search, R.string.feature_face_search_desc, FaceSearchActivity.class);
        bindFeatureCard(R.id.featureFaceCompare, android.R.drawable.ic_menu_gallery,
                R.string.feature_face_compare, R.string.feature_face_compare_desc,
                FaceComparisonActivity.class);
        bindFeatureCard(R.id.featureCameraSettings, android.R.drawable.ic_menu_manage,
                R.string.feature_camera_settings, R.string.feature_camera_settings_desc, CameraSettingsActivity.class);

        View.OnClickListener showAbout = ignored -> Toast.makeText(
                getApplicationContext(), R.string.api_about_message, Toast.LENGTH_SHORT).show();
        findViewById(R.id.aboutButton).setOnClickListener(showAbout);
        findViewById(R.id.aboutText).setOnClickListener(showAbout);
    }

    /** 绑定功能卡片与页面。 */
    private void bindFeatureCard(
            @IdRes int viewId,
            @DrawableRes int icon,
            @StringRes int title,
            @StringRes int description,
            @NonNull Class<?> destination) {
        View feature = findViewById(viewId);
        ImageView featureIcon = feature.findViewById(R.id.featureIcon);
        featureIcon.setImageResource(icon);
        // 系统菜单图标自带约 60% 的透明度；实色图标仅调整图像，保持底框亮度一致。
        featureIcon.setImageAlpha(
                icon == android.R.drawable.ic_input_add || icon == R.drawable.ic_api_verified
                        ? 153 : 255);
        ((TextView) feature.findViewById(R.id.featureTitle)).setText(title);
        ((TextView) feature.findViewById(R.id.featureDescription)).setText(description);
        feature.setOnClickListener(v -> startActivity(new Intent(this, destination)));
    }
}
