import { RealtimeMode } from './RealtimeMode';

export interface CameraPreviewBounds {
  readonly width: number;
  readonly height: number;
}

/** 与 Android PreviewView 一致：只有实时搜索裁剪填满，其余相机业务完整显示画面。 */
export class CameraPreviewLayout {
  static fillsViewport(mode: RealtimeMode): boolean {
    return mode === RealtimeMode.SEARCH_SINGLE || mode === RealtimeMode.SEARCH_MULTI;
  }

  static centeredBounds(mode: RealtimeMode, contentAspect: number,
    viewportWidth: number, viewportHeight: number): CameraPreviewBounds {
    if (!Number.isFinite(contentAspect) || !Number.isFinite(viewportWidth) ||
      !Number.isFinite(viewportHeight) || contentAspect <= 0 ||
      viewportWidth <= 0 || viewportHeight <= 0) {
      throw new Error('Preview layout dimensions must be positive finite numbers');
    }
    const height: number = CameraPreviewLayout.fillsViewport(mode) ?
      Math.max(viewportWidth / contentAspect, viewportHeight) :
      Math.min(viewportWidth / contentAspect, viewportHeight);
    return { width: contentAspect * height, height: height };
  }
}
