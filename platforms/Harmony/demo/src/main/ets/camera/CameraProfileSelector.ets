import { DemoL10n } from '../ui/DemoL10n';
import { camera } from '@kit.CameraKit';
import { Yuv420Frame } from 'hiface';
import { CameraAnalysisResolution, CameraResolutionPreset, cameraResolutionPreset } from './CameraDemoSettings';

/**
 * Use the same profile for both outputs and bound restart cost to preferred, near-standard, and
 * minimum-size attempts.
 *
 * 双路使用相同规格；最多尝试首选、标准附近和最小规格，限制重启成本。
 */
export class CameraProfileSelector {
  static select(profiles: Array<camera.Profile>, resolution: CameraAnalysisResolution | undefined): camera.Profile[] {
    const standard: CameraResolutionPreset = cameraResolutionPreset(CameraAnalysisResolution.LOW);
    const target: CameraResolutionPreset = cameraResolutionPreset(resolution);
    const valid: camera.Profile[] = [];
    for (const profile of profiles) {
      const width: number = profile.size.width;
      const height: number = profile.size.height;
      if (profile.format !== camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP ||
        !Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0 ||
        width % 2 !== 0 || height % 2 !== 0 ||
        Math.max(width, height) > Yuv420Frame.MAX_LONG_SIDE_PIXELS ||
        Math.min(width, height) > Yuv420Frame.MAX_SHORT_SIDE_PIXELS) continue;
      if (!valid.some((item: camera.Profile): boolean =>
        item.size.width === width && item.size.height === height)) valid.push(profile);
    }
    if (valid.length === 0) throw new Error(DemoL10n.text("没有符合 1080p 上限的 YUV_420_SP 预览规格"));
    const pixels = (profile: camera.Profile): number => profile.size.width * profile.size.height;
    const score = (profile: camera.Profile, preset: CameraResolutionPreset): number =>
      Math.abs(pixels(profile) - preset.width * preset.height) +
        Math.abs(profile.size.width / profile.size.height - preset.width / preset.height) * 100000;
    // Treat the tier as a pixel budget with a soft 4:3 preference. When nothing fits, allow a
    // larger profile that still satisfies the SDK limits above.
    const inBudget: camera.Profile[] = valid.filter((item: camera.Profile): boolean =>
      pixels(item) <= target.width * target.height);
    const candidates: camera.Profile[] = inBudget.length > 0 ? inBudget : valid;
    candidates.sort((a: camera.Profile, b: camera.Profile): number =>
      score(a, target) - score(b, target));
    const preferred: camera.Profile = candidates[0];
    const smaller: camera.Profile[] = valid.filter((item: camera.Profile): boolean =>
      pixels(item) < pixels(preferred));
    smaller.sort((a: camera.Profile, b: camera.Profile): number =>
      score(a, standard) - score(b, standard));
    const result: camera.Profile[] = [preferred];
    if (smaller.length > 0) {
      const standardFallback: camera.Profile = smaller[0];
      const smallest: camera.Profile = smaller.reduce((best: camera.Profile, item: camera.Profile): camera.Profile =>
        pixels(item) < pixels(best) ? item : best, standardFallback);
      result.push(standardFallback);
      if (smallest !== standardFallback) result.push(smallest);
    }
    return result;
  }
}
