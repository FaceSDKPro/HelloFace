export interface CameraPreviewBounds {
  readonly width: number;
  readonly height: number;
}

/**
 * Preserve the negotiated frame aspect ratio inside the available viewfinder.
 */
export class CameraPreviewLayout {
  static centeredBounds(contentAspect: number,
    viewportWidth: number, viewportHeight: number): CameraPreviewBounds {
    if (!Number.isFinite(contentAspect) || !Number.isFinite(viewportWidth) ||
      !Number.isFinite(viewportHeight) || contentAspect <= 0 ||
      viewportWidth <= 0 || viewportHeight <= 0) {
      throw new Error('Preview layout dimensions must be positive finite numbers');
    }
    const height: number = Math.min(viewportWidth / contentAspect, viewportHeight);
    return { width: contentAspect * height, height: height };
  }
}
