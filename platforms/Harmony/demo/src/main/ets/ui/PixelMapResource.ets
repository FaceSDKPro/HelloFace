import { image } from '@kit.ImageKit';

/** Demo PixelMap 资源工具：集中创建 RGBA 预览，并吞掉清理阶段的系统资源异常。 */
export class PixelMapResource {
  static async createRgba(rgba: ArrayBuffer, width: number,
    height: number): Promise<image.PixelMap | undefined> {
    try {
      const options: image.InitializationOptions = {
        size: { width: width, height: height },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: false
      };
      return await image.createPixelMap(rgba, options);
    } catch (_) {
      return undefined;
    }
  }

  static async release(pixelMap: image.PixelMap | undefined): Promise<void> {
    if (pixelMap === undefined) {
      return;
    }
    try {
      await pixelMap.release();
    } catch (_) {
    }
  }
}
