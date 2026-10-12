import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/** 非搜索相机页每次进入前台设为 90% 亮度，离开前台时恢复当次进入前的窗口值。 */
export class CameraScreenPresentation {
  private static readonly ACTIVE_BRIGHTNESS: number = 0.90;
  private operation: Promise<void> = Promise.resolve();
  private generation: number = 0;
  private visible: boolean = false;
  private activeWindow: window.Window | undefined = undefined;
  private previousBrightness: number = -1;

  enter(context: common.UIAbilityContext): void {
    if (this.visible && this.activeWindow !== undefined) return;
    const generation: number = ++this.generation;
    this.visible = true;
    this.operation = this.operation.then(async (): Promise<void> => {
      if (!this.visible || generation !== this.generation) return;
      let target: window.Window;
      try {
        target = await window.getLastWindow(context);
      } catch (_) {
        return;
      }
      if (!this.visible || generation !== this.generation) return;
      this.activeWindow = target;
      this.previousBrightness = target.getWindowProperties().brightness;
      try {
        await target.setWindowBrightness(CameraScreenPresentation.ACTIVE_BRIGHTNESS);
      } catch (_) {
      }
    }).catch((): void => {});
  }

  leave(): void {
    this.visible = false;
    ++this.generation;
    this.operation = this.operation.then(async (): Promise<void> => {
      const target: window.Window | undefined = this.activeWindow;
      if (target === undefined) return;
      const brightness: number = this.previousBrightness;
      this.activeWindow = undefined;
      this.previousBrightness = -1;
      try {
        await target.setWindowBrightness(brightness);
      } catch (_) {
      }
    }).catch((): void => {});
  }
}
