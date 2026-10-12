export interface CameraFrameRateRange {
  readonly min: number;
  readonly max: number;
}

/** 只请求上报范围内的固定帧率；硬件回退高于目标时仍需应用侧限流。 */
export class CameraFrameRatePolicy {
  static select(ranges: Array<CameraFrameRateRange>, targetFps: number): CameraFrameRateRange | undefined {
    if (!Number.isInteger(targetFps) || targetFps <= 0) {
      throw new Error('Target frame rate must be a positive integer');
    }
    let lowerFps: number = 0;
    let multipleFps: number = Number.POSITIVE_INFINITY;
    let upperFps: number = Number.POSITIVE_INFINITY;
    for (const range of ranges) {
      if (!Number.isInteger(range.min) || !Number.isInteger(range.max) ||
        range.min <= 0 || range.max < range.min) continue;
      if (range.min <= targetFps && range.max >= targetFps) {
        return { min: targetFps, max: targetFps };
      }
      if (range.max < targetFps) lowerFps = Math.max(lowerFps, range.max);
      if (range.min > targetFps) {
        // 整倍数可避免硬件与软件门禁错相，如 [7,12] 对 5 FPS 选 10 而非 7。
        const multiple: number = Math.ceil(range.min / targetFps) * targetFps;
        if (multiple <= range.max) multipleFps = Math.min(multipleFps, multiple);
        upperFps = Math.min(upperFps, range.max);
      }
    }
    const fallback: number = Number.isFinite(multipleFps) ? multipleFps : upperFps;
    if (Number.isFinite(fallback)) return { min: fallback, max: fallback };
    return lowerFps > 0 ? { min: lowerFps, max: lowerFps } : undefined;
  }
}
