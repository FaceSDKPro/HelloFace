/** 将旋转后的分析图坐标映射到居中的相机预览；与 XComponent 的 FIT/FILL 布局共用。 */
export class PreviewCoordinateTransform {
  readonly scale: number;
  readonly offsetX: number;
  readonly offsetY: number;
  private readonly sourceWidth: number;
  private readonly mirrored: boolean;

  private constructor(sourceWidth: number, sourceHeight: number, viewportWidth: number,
    viewportHeight: number, fill: boolean, mirrored: boolean) {
    if (sourceWidth <= 0 || sourceHeight <= 0 || viewportWidth <= 0 || viewportHeight <= 0) {
      throw new Error('Preview transform dimensions must be positive');
    }
    this.scale = fill ? Math.max(viewportWidth / sourceWidth, viewportHeight / sourceHeight) :
      Math.min(viewportWidth / sourceWidth, viewportHeight / sourceHeight);
    this.offsetX = (viewportWidth - sourceWidth * this.scale) / 2;
    this.offsetY = (viewportHeight - sourceHeight * this.scale) / 2;
    this.sourceWidth = sourceWidth;
    this.mirrored = mirrored;
  }

  static fit(sourceWidth: number, sourceHeight: number, viewportWidth: number,
    viewportHeight: number, mirrored: boolean): PreviewCoordinateTransform {
    return new PreviewCoordinateTransform(sourceWidth, sourceHeight, viewportWidth,
      viewportHeight, false, mirrored);
  }

  static fill(sourceWidth: number, sourceHeight: number, viewportWidth: number,
    viewportHeight: number, mirrored: boolean): PreviewCoordinateTransform {
    return new PreviewCoordinateTransform(sourceWidth, sourceHeight, viewportWidth,
      viewportHeight, true, mirrored);
  }

  x(sourceX: number): number {
    return this.offsetX + (this.mirrored ? this.sourceWidth - sourceX : sourceX) * this.scale;
  }

  rectX(sourceX: number, sourceWidth: number): number {
    return this.offsetX + (this.mirrored ? this.sourceWidth - sourceX - sourceWidth : sourceX) * this.scale;
  }

  y(sourceY: number): number {
    return this.offsetY + sourceY * this.scale;
  }
}
