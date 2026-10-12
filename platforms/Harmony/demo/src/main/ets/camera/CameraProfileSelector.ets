import { camera } from '@kit.CameraKit';
import { Yuv420Frame } from 'hiface';

const STANDARD_WIDTH: number = 640;
const STANDARD_HEIGHT: number = 480;
const HIGH_WIDTH: number = 1280;
const HIGH_HEIGHT: number = 720;

/** 双路使用相同规格；最多尝试首选、标准附近和最小规格，限制重启成本。 */
export class CameraProfileSelector {
  static select(profiles: Array<camera.Profile>, highResolution: boolean): camera.Profile[] {
    const targetWidth: number = highResolution ? HIGH_WIDTH : STANDARD_WIDTH;
    const targetHeight: number = highResolution ? HIGH_HEIGHT : STANDARD_HEIGHT;
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
    if (valid.length === 0) throw new Error('没有符合 1080p 上限的 YUV_420_SP 预览规格');
    const score = (profile: camera.Profile, width: number, height: number): number =>
      Math.abs(profile.size.width * profile.size.height - width * height) +
        Math.abs(profile.size.width / profile.size.height - width / height) * 100000;
    valid.sort((a: camera.Profile, b: camera.Profile): number =>
      score(a, targetWidth, targetHeight) - score(b, targetWidth, targetHeight));
    const preferred: camera.Profile = valid[0];
    const smaller: camera.Profile[] = valid.filter((item: camera.Profile): boolean =>
      item.size.width * item.size.height < preferred.size.width * preferred.size.height);
    smaller.sort((a: camera.Profile, b: camera.Profile): number =>
      score(a, STANDARD_WIDTH, STANDARD_HEIGHT) - score(b, STANDARD_WIDTH, STANDARD_HEIGHT));
    const result: camera.Profile[] = [preferred];
    if (smaller.length > 0) {
      result.push(smaller[0]);
      smaller.sort((a: camera.Profile, b: camera.Profile): number =>
        a.size.width * a.size.height - b.size.width * b.size.height);
      if (smaller[0] !== result[1]) result.push(smaller[0]);
    }
    return result;
  }
}
