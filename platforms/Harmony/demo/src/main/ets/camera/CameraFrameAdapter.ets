import { image } from '@kit.ImageKit';
import { Yuv420Frame, YuvColorMatrix, YuvColorRange, YuvPlane } from 'hiface';

// 系统 NativeBuffer 格式 OH_NativeBuffer_Format::NATIVEBUFFER_PIXEL_FMT_YCRCB_420_SP（NV21）。
const NV21_BUFFER_FORMAT: number = 25;

/** ImageReceiver 只支持 JPEG 分量入口；预览输出决定实际内容为 NV21，并非 JPEG 编码。 */
export class CameraFrameAdapter {
  static async read(source: image.Image, rotation: number, mirrored: boolean): Promise<Yuv420Frame> {
    if (source.format !== NV21_BUFFER_FORMAT) {
      throw new Error(`Unsupported preview buffer format: ${source.format}`);
    }
    const component: image.Component = await source.getComponent(image.ComponentType.JPEG);
    return CameraFrameAdapter.fromNv21(component.byteBuffer, source.size.width, source.size.height,
      component.rowStride, rotation, mirrored);
  }

  static fromNv21(buffer: ArrayBuffer, width: number, height: number, rowStride: number,
    rotation: number, mirrored: boolean): Yuv420Frame {
    if (!Number.isInteger(width) || !Number.isInteger(height) || width < 2 || height < 2 ||
      width % 2 !== 0 || height % 2 !== 0 ||
      Math.max(width, height) > Yuv420Frame.MAX_LONG_SIDE_PIXELS ||
      Math.min(width, height) > Yuv420Frame.MAX_SHORT_SIDE_PIXELS ||
      !Number.isInteger(rowStride) || rowStride < width) {
      throw new Error('Invalid NV21 dimensions or row stride');
    }
    const yBytes: number = rowStride * height;
    const chromaBytes: number = rowStride * (height / 2 - 1) + width;
    if (!Number.isSafeInteger(yBytes + chromaBytes) || buffer.byteLength < yBytes + chromaBytes) {
      throw new Error('NV21 buffer is shorter than its plane layout');
    }
    // HAR 接收 ArrayBuffer 而非带 offset 的视图；明确分离 Y、VU 的偏移，保留 padding 和 pixelStride。
    const frame = new Yuv420Frame(new YuvPlane(buffer.slice(0, yBytes), rowStride, 1),
      new YuvPlane(buffer.slice(yBytes + 1, yBytes + chromaBytes), rowStride, 2),
      new YuvPlane(buffer.slice(yBytes, yBytes + chromaBytes), rowStride, 2),
      width, height, YuvColorRange.VIDEO, YuvColorMatrix.BT709, rotation, mirrored);
    frame.validate();
    return frame;
  }
}
