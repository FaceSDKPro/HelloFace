package com.hiface.sdk.demo.comparison;

import org.junit.Test;
import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertThrows;

public final class FacePhotoPickerResolutionTest {
    @Test
    public void imageSearchPreservesPhotosWithinSdkLimit() {
        int limit = FacePhotoPicker.IMAGE_SEARCH_MAX_DIMENSION_PX;
        assertArrayEquals(new int[]{4032, 3024}, FacePhotoPicker.decodeSize(4032, 3024, limit));
        assertArrayEquals(new int[]{3024, 4032}, FacePhotoPicker.decodeSize(3024, 4032, limit));
        assertArrayEquals(new int[]{4096, 4096}, FacePhotoPicker.decodeSize(4096, 4096, limit));
        assertArrayEquals(new int[]{333, 335}, FacePhotoPicker.decodeSize(333, 335, limit));
        assertArrayEquals(new int[]{100, 100}, FacePhotoPicker.decodeSize(100, 100, limit));
    }

    @Test
    public void onlyOversizedSearchPhotosAreReducedWithoutUpscaling() {
        assertArrayEquals(new int[]{4096, 2048}, FacePhotoPicker.decodeSize(6000, 3000, 4096));
        assertArrayEquals(new int[]{2048, 4096}, FacePhotoPicker.decodeSize(3000, 6000, 4096));
        assertArrayEquals(new int[]{1080, 810}, FacePhotoPicker.decodeSize(4032, 3024, 1080));
    }

    @Test
    public void invalidOrDegeneratePhotosAreRejectedRatherThanEnlarged() {
        assertThrows(IllegalArgumentException.class, () -> FacePhotoPicker.decodeSize(1, 100, 4096));
        assertThrows(IllegalArgumentException.class, () -> FacePhotoPicker.decodeSize(10000, 2, 4096));
        assertThrows(IllegalArgumentException.class, () -> FacePhotoPicker.decodeSize(100, 100, 5000));
    }
}
