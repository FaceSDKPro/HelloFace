import photoAccessHelper from '@ohos.file.photoAccessHelper';
import image from '@ohos.multimedia.image';
import { fileIo } from '@kit.CoreFileKit';
import { RgbaImage } from 'hiface';
import { PixelMapResource } from '../ui/PixelMapResource';

/** Demo 图库适配器：把授权 URI 转成方向正确、无行填充的 RGBA8888 输入。 */
export class FacePhotoPicker {
  readonly rgba: RgbaImage;

  constructor(rgba: RgbaImage) {
    this.rgba = rgba;
  }

  static async select(): Promise<FacePhotoPicker | undefined> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const selected: photoAccessHelper.PhotoSelectResult =
        await new photoAccessHelper.PhotoViewPicker().select(options);
      if (selected.photoUris.length === 0) {
        return undefined;
      }
      const uri: string = selected.photoUris[0];
      // PhotoViewPicker 返回授权 URI；createImageSource(string) 只接受应用沙盒路径。
      const file: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      let source: image.ImageSource | undefined = undefined;
      try {
        source = image.createImageSource(file.fd);
        if (source === undefined) throw new Error('Unable to create image source');
        // 不把 PhotoViewPicker 的临时授权 URI 交给 ArkUI 再次解码。RGBA 数据已经完全
        // 复制到应用内存，选择器关闭后只使用这份数据，避免图库授权回收时的并发访问。
        return new FacePhotoPicker(await FacePhotoPicker.decodeSource(source));
      } finally {
        try { await source?.release(); } finally { await fileIo.close(file); }
      }
    } catch (error) {
      throw new Error(`Unable to select or decode photo: ${error}`);
    }
  }

  /** 把网络或 rawfile 中的编码图片转换成 SDK 使用的紧凑 RGBA 输入。 */
  static async decode(encoded: ArrayBuffer): Promise<RgbaImage> {
    const source: image.ImageSource = image.createImageSource(encoded);
    if (source === undefined) throw new Error('Unable to create image source');
    try {
      return await FacePhotoPicker.decodeSource(source);
    } finally {
      await source.release();
    }
  }

  private static async decodeSource(source: image.ImageSource): Promise<RgbaImage> {
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      const original: image.ImageInfo = await source.getImageInfo(0);
      const size: image.Size = FacePhotoPicker.fitEvenSize(original.size.width, original.size.height);
      const decoding: image.DecodingOptions = {
        desiredSize: size,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true
      };
      pixelMap = await source.createPixelMap(decoding);
      if (pixelMap === undefined) throw new Error('Unable to decode image');
      let orientation: string = '1';
      try { orientation = await source.getImageProperty(image.PropertyKey.ORIENTATION); } catch (_) {}
      await FacePhotoPicker.applyOrientation(pixelMap, orientation);
      const decoded: image.ImageInfo = await pixelMap.getImageInfo();
      const width: number = decoded.size.width;
      const height: number = decoded.size.height;
      const pixels: ArrayBuffer = await FacePhotoPicker.readPackedRgba(pixelMap, decoded);
      return new RgbaImage(pixels, width, height);
    } finally {
      await PixelMapResource.release(pixelMap);
    }
  }

  private static async applyOrientation(pixelMap: image.PixelMap, orientation: string): Promise<void> {
    const value: string = orientation.trim().toLowerCase();
    if (value === '2' || value === 'top-right') await pixelMap.flip(true, false);
    else if (value === '3' || value === 'bottom-right') await pixelMap.rotate(180);
    else if (value === '4' || value === 'bottom-left') await pixelMap.flip(false, true);
    else if (value === '5' || value === 'left-top') {
      await pixelMap.rotate(90); await pixelMap.flip(true, false);
    } else if (value === '6' || value === 'right-top') await pixelMap.rotate(90);
    else if (value === '7' || value === 'right-bottom') {
      await pixelMap.rotate(90); await pixelMap.flip(false, true);
    } else if (value === '8' || value === 'left-bottom') await pixelMap.rotate(270);
  }

  private static fitEvenSize(width: number, height: number): image.Size {
    if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1) {
      throw new Error('Decoded image has invalid dimensions');
    }
    // 与 Android Demo 一致；1080px 足够静态识别，也避免图库大图占用 UI 进程内存。
    const maximumSide: number = 1080;
    const scale: number = Math.min(1, maximumSide / Math.max(width, height));
    const evenWidth: number = Math.floor(width * scale / 2) * 2;
    const evenHeight: number = Math.floor(height * scale / 2) * 2;
    // Android 会裁掉奇数末边，裁剪后不足 2px 的退化图片应拒绝，不能人为放大补像素。
    if (evenWidth < 2 || evenHeight < 2) {
      throw new Error('Decoded image is too small after even-size cropping');
    }
    return { width: evenWidth, height: evenHeight };
  }

  private static async readPackedRgba(pixelMap: image.PixelMap,
    info: image.ImageInfo): Promise<ArrayBuffer> {
    const width: number = info.size.width;
    const height: number = info.size.height;
    const byteCount: number = width * height * 4;
    const pixels = new ArrayBuffer(byteCount);
    // readPixelsToBuffer 保留 PixelMap 自身格式。正常 RGBA 紧凑布局可直接交给 SDK，
    // 避免在 ArkUI 线程执行数百万次通道交换。
    if (info.pixelFormat === image.PixelMapFormat.RGBA_8888 &&
      info.stride === width * 4 && pixelMap.getPixelBytesNumber() === byteCount) {
      await pixelMap.readPixelsToBuffer(pixels);
      return pixels;
    }
    // 带 DMA 行填充等少数布局使用区域读取压紧；鸿蒙规定该接口输出 BGRA。
    const area: image.PositionArea = { pixels: pixels, offset: 0, stride: width * 4,
      region: { x: 0, y: 0, size: { width: width, height: height } } };
    await pixelMap.readPixels(area);
    const bytes = new Uint8Array(pixels);
    for (let i: number = 0; i < bytes.length; i += 4) {
      const blue: number = bytes[i]; bytes[i] = bytes[i + 2]; bytes[i + 2] = blue;
    }
    return pixels;
  }
}
