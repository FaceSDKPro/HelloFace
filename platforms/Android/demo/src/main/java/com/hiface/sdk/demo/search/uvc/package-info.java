/**
 * UVC Demo capture and presentation: RGB/IR search and RGB-only guided enrollment.
 * Settings classes own forms/device choices; display classes own guidance and bounded diagnostics.
 *
 * <p>Activities and forms run on main. Frame callbacks borrow pixels synchronously and do not retain
 * camera buffers. Each capture has its own generation: stop rejects old callbacks before waiting for
 * native resources and in-flight frames to drain. {@link com.hiface.sdk.demo.search.uvc.UvcCameraCloseBarrier}
 * coordinates pages and recreation; {@link com.hiface.sdk.demo.search.uvc.UvcPreviewSurfaces} releases
 * surfaces/textures only after draining. Images and features never enter saved state or logs.</p>
 * 中文：主线程管理页面，帧回调同步借用像素；停止后先作废回调，再排空并释放资源。
 */
package com.hiface.sdk.demo.search.uvc;
