import { DemoTheme } from './DemoTheme';

const STATUS_TEXT_SIZE_VP: number = 19;
const STATUS_TEXT_GAP_VP: number = 12;
const STATUS_TEXT_HORIZONTAL_MARGIN_VP: number = 24;
/** 与 Android FaceCaptureOverlayView 一致的圆孔、引导和倒计时。 */
export class FaceCaptureOverlay {
  static draw(context: CanvasRenderingContext2D, width: number, height: number,
    guide: string, countdownRemaining: number): void {
    const portrait: boolean = height >= width;
    const radius: number = Math.min(width, height) * (portrait ? 0.8 : 0.7) / 2;
    const centerX: number = width / 2;
    const centerY: number = height * (portrait ? 0.43 : 0.5);
    context.save();
    context.fillStyle = '#FFFFFF';
    context.fillRect(0, 0, width, height);
    context.globalCompositeOperation = 'destination-out';
    context.beginPath();
    context.arc(centerX, centerY, radius, 0, Math.PI * 2);
    context.fill();
    context.globalCompositeOperation = 'source-over';
    context.strokeStyle = 'rgba(255,255,255,0.4)';
    context.lineWidth = 1.95;
    context.beginPath();
    context.arc(centerX, centerY, radius - 3, 0, Math.PI * 2);
    context.stroke();
    context.strokeStyle = '#F7F7F7';
    context.lineWidth = 2.4;
    context.lineCap = 'round';
    context.beginPath();
    context.arc(centerX, centerY, radius - 3, -Math.PI / 2,
      -Math.PI / 2 + Math.PI * 2 * countdownRemaining);
    context.stroke();
    // Android 使用 19sp。Canvas 的 px 是物理像素，在高密度设备上会显得明显偏小；
    // 鸿蒙使用 vp 保持与 Android 逻辑尺寸一致。
    context.font = `bold ${STATUS_TEXT_SIZE_VP}vp sans-serif`;
    context.fillStyle = DemoTheme.primary;
    context.textAlign = 'center';
    context.textBaseline = 'bottom';
    context.fillText(guide, centerX, centerY - radius - STATUS_TEXT_GAP_VP,
      width - STATUS_TEXT_HORIZONTAL_MARGIN_VP * 2);
    context.restore();
  }
}
