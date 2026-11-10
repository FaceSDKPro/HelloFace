package com.hiface.sdk.demo.search.uvc;

import android.os.Bundle;
import android.view.View;
import android.widget.Spinner;
import com.facesdkpro.uvccamera.DualCameraSession;
import com.facesdkpro.uvccamera.StreamConfig;
import com.hiface.sdk.demo.R;
import java.util.Arrays;

/** Capture preferences, independent for each role; negotiated metadata comes from actualConfig(). */
final class UvcStreamSettings {
    private final Spinner resolution, fps;
    private final String key;

    UvcStreamSettings(View root, String key, boolean default30Fps) {
        this.key = key;
        resolution = root.findViewById(R.id.uvcStreamResolution);
        fps = root.findViewById(R.id.uvcStreamFps);
        UvcCameraChoices.bind(resolution, Arrays.asList("640 × 480", "1280 × 720"), 0);
        UvcCameraChoices.bind(fps, Arrays.asList("15 FPS", "30 FPS"), default30Fps ? 1 : 0);
    }

    static StreamConfig config(DualCameraSession.Role role, int resolution, int fps) {
        // Keep MJPEG explicit: HiFace's NV21 input contract uses video-range BT.601.
        return StreamConfig.preferred(role, resolution == 1 ? StreamConfig.Resolution.HIGH
                : StreamConfig.Resolution.MIDDLE, fps == 1 ? 30 : 15, StreamConfig.Transport.MJPEG);
    }

    StreamConfig read(DualCameraSession.Role role) {
        return config(role, resolution.getSelectedItemPosition(), fps.getSelectedItemPosition());
    }

    void restore(Bundle saved) {
        if (saved == null) return;
        resolution.setSelection(saved.getInt(key + "Resolution") == 1 ? 1 : 0);
        if (saved.containsKey(key + "Fps")) fps.setSelection(saved.getInt(key + "Fps") == 1 ? 1 : 0);
    }

    void save(Bundle out) {
        save(out, key);
    }

    /** Transfer the requested preferences, rather than a device-specific negotiated mode. */
    void save(Bundle out, String destinationKey) {
        out.putInt(destinationKey + "Resolution", resolution.getSelectedItemPosition());
        out.putInt(destinationKey + "Fps", fps.getSelectedItemPosition());
    }
}
