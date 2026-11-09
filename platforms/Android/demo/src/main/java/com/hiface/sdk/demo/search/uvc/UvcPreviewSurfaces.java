package com.hiface.sdk.demo.search.uvc;

import android.graphics.SurfaceTexture;
import android.view.Surface;
import android.view.TextureView;
import java.util.ArrayList;
import java.util.List;

/** Owns preview surfaces on main until native cleanup completes. 中文：排空后才能释放预览资源。 */
final class UvcPreviewSurfaces {
    private final List<Surface> surfaces = new ArrayList<>(2);
    private final List<SurfaceTexture> detachedTextures = new ArrayList<>(2);

    Surface open(TextureView preview) {
        Surface surface = new Surface(preview.getSurfaceTexture());
        surfaces.add(surface);
        return surface;
    }

    /** Retain a destroyed TextureView texture; its listener returns false to defer system release. */
    void retain(SurfaceTexture texture) { detachedTextures.add(texture); }

    void release() {
        for (Surface surface : surfaces) surface.release();
        surfaces.clear();
        for (SurfaceTexture texture : detachedTextures) texture.release();
        detachedTextures.clear();
    }
}
