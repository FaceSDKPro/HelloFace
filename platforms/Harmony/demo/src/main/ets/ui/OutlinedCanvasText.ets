/** 相机 Overlay 共用的高对比文字：白色字形配深灰描边，不遮挡人脸画面。 */
export class OutlinedCanvasText {
  static draw(context: CanvasRenderingContext2D, text: string, x: number, baseline: number): void {
    if (text.length === 0) return;
    context.save();
    context.lineWidth = 3;
    context.lineJoin = 'round';
    context.strokeStyle = 'rgba(24,24,24,0.92)';
    context.fillStyle = '#FFFFFF';
    context.strokeText(text, x, baseline);
    context.fillText(text, x, baseline);
    context.restore();
  }
}
