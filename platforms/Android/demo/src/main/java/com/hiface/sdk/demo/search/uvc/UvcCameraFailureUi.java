package com.hiface.sdk.demo.search.uvc;

import com.facesdkpro.uvccamera.CameraFailure;
import com.hiface.sdk.demo.R;

/** Shared actionable camera failures; technical/native details stay in diagnostic logs. */
final class UvcCameraFailureUi {
    private UvcCameraFailureUi() {}

    static int message(CameraFailure.Code code) {
        switch (code) {
            case USB_PERMISSION_DENIED:
            case USB_PERMISSION_TIMEOUT: return R.string.uvc_search_usb_permission;
            case CAMERA_CLOSED:
            case DEVICE_DETACHED: return R.string.uvc_search_usb_detached;
            case STREAM_TIMEOUT: return R.string.uvc_search_stream_timeout;
            case PAIR_TIMEOUT: return R.string.uvc_search_pair_timeout;
            case UNSUPPORTED_MODE: return R.string.uvc_camera_unsupported_mode;
            case DEVICE_BUSY: return R.string.uvc_camera_busy;
            case OPEN_TIMEOUT: return R.string.uvc_camera_open_timeout;
            default: return R.string.uvc_search_camera_unavailable;
        }
    }
}
