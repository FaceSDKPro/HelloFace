import { FaceSearchFace, FaceSearchFrame } from 'hiface';
import { OutlinedCanvasText } from '../ui/OutlinedCanvasText';
import { PreviewCoordinateTransform } from '../ui/PreviewCoordinateTransform';
import { FaceSearchOverlayState, FaceSearchOverlayVisual } from './FaceSearchOverlayState';

/** 搜索框坐标与 Android 一致；标签使用不遮挡预览画面的白字深灰描边。 */
export class FaceSearchOverlay {
  static draw(context: CanvasRenderingContext2D, state: FaceSearchOverlayState,
    width: number, height: number, mirrored: boolean, now: number): void {
    state.expire(now);
    const frame: FaceSearchFrame | undefined = state.frame();
    if (frame === undefined || frame.faces.length === 0) return;
    const transform: PreviewCoordinateTransform = PreviewCoordinateTransform.fill(
      frame.imageWidth, frame.imageHeight, width, height, mirrored);
    context.save();
    // 对齐 Android 的 14 * density，避免物理像素字号在高密度屏幕上缩小。
    context.font = '14vp sans-serif';
    context.lineWidth = 2;
    for (let index: number = 0; index < frame.faces.length; index += 1) {
      const face: FaceSearchFace = frame.faces[index];
      const bounds = face.bounds;
      // Android 只在映射完成后左右各扩 10%，不改变框的上下边界。
      const sourceX: number = bounds.x - bounds.width * 0.1;
      const sourceWidth: number = bounds.width * 1.2;
      const x: number = transform.rectX(sourceX, sourceWidth);
      const y: number = transform.y(bounds.y);
      const faceWidth: number = sourceWidth * transform.scale;
      const faceHeight: number = bounds.height * transform.scale;
      if (x >= width || y >= height || x + faceWidth <= 0 || y + faceHeight <= 0) continue;

      const visual: FaceSearchOverlayVisual = state.visual(index);
      context.strokeStyle = visual.color;
      context.strokeRect(x, y, faceWidth, faceHeight);

      if (visual.label.length === 0) continue;
      FaceSearchOverlay.drawLabel(context, visual.label, visual.details, x, y, width, height);
    }
    context.restore();
  }

  private static drawLabel(context: CanvasRenderingContext2D, rawLabel: string,
    rawDetails: string, rectX: number, rectY: number, width: number, height: number): void {
    const maxTextWidth: number = Math.max(0, width - 12);
    const label: string = FaceSearchOverlay.fitLabel(context, rawLabel, maxTextWidth);
    const details: string = FaceSearchOverlay.fitLabel(context, rawDetails, maxTextWidth);
    const textWidth: number = Math.max(context.measureText(label).width,
      context.measureText(details).width);
    const x: number = Math.max(6, Math.min(rectX, width - textWidth - 6));
    const lineHeight: number = details.length === 0 ? 0 : 18;
    const baseline: number = Math.max(15 + lineHeight, Math.min(rectY - 6, height - 6));
    OutlinedCanvasText.draw(context, label, x, baseline - lineHeight);
    OutlinedCanvasText.draw(context, details, x, baseline);
  }

  private static fitLabel(context: CanvasRenderingContext2D, label: string,
    maxWidth: number): string {
    if (label.length === 0 || context.measureText(label).width <= maxWidth) return label;
    let end: number = label.length;
    while (end > 0 && context.measureText(`${label.substring(0, end)}…`).width > maxWidth) end -= 1;
    return end === 0 ? '' : `${label.substring(0, end)}…`;
  }
}
