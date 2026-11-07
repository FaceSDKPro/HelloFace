package com.hiface.sdk.demo.search.uvc;

import android.graphics.SurfaceTexture;
import android.view.Surface;
import android.view.TextureView;
import java.util.ArrayList;
import java.util.List;

/** 主线程持有预览 Surface，等相机关闭回调确认 native 排空后再释放。 */
final class UvcPreviewSurfaces {
    private final List<Surface> surfaces = new ArrayList<>(2);
    private final List<SurfaceTexture> detachedTextures = new ArrayList<>(2);

    Surface open(TextureView preview) {
        Surface surface = new Surface(preview.getSurfaceTexture());
        surfaces.add(surface);
        return surface;
    }

    /** TextureView 销毁时接管纹理，监听器需返回 false 以推迟系统释放。 */
    void retain(SurfaceTexture texture) { detachedTextures.add(texture); }

    void release() {
        for (Surface surface : surfaces) surface.release();
        surfaces.clear();
        for (SurfaceTexture texture : detachedTextures) texture.release();
        detachedTextures.clear();
    }
}
