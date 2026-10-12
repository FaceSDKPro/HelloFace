import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/**
 * 搜索页在前台时始终常亮，离开时恢复亮度并释放常亮。
 * 所有异步操作串行执行，避免快速进入/退出时迟到的亮度覆盖恢复值。
 */
export class SearchScreenPresentation {
  private static readonly ACTIVE_BRIGHTNESS: number = 0.90;
  private static readonly IDLE_BRIGHTNESS: number = 0.10;
  private static readonly NO_FACE_IDLE_DELAY_MILLIS: number = 10000;
  private operation: Promise<void> = Promise.resolve();
  private generation: number = 0;
  private visible: boolean = false; // 页面显示策略是否生效，停止后忽略迟到回调
  private activeWindow: window.Window | undefined = undefined;
  private previousBrightness: number = -1;
  private appliedBrightness: number = -1;
  private desiredBrightness: number = -1;
  private facePresent: boolean = false; // 检测状态变化用于启动或取消连续无人脸倒计时
  private idleTimer: number = -1;
  onIdleStateChanged: (idle: boolean) => void = (_idle: boolean): void => {};

  enter(context: common.UIAbilityContext): void {
    if (this.visible && this.activeWindow !== undefined) return;
    const generation: number = ++this.generation;
    this.visible = true;
    this.facePresent = false;
    this.clearIdleTimer();
    this.operation = this.operation.then(async (): Promise<void> => {
      if (!this.visible || generation !== this.generation) return;
      let target: window.Window;
      try {
        target = await window.getLastWindow(context);
      } catch (_) {
        return;
      }
      if (!this.visible || generation !== this.generation) return;
      const properties: window.WindowProperties = target.getWindowProperties();
      this.activeWindow = target;
      this.previousBrightness = properties.brightness;
      try {
        await target.setWindowBrightness(SearchScreenPresentation.ACTIVE_BRIGHTNESS);
        this.appliedBrightness = SearchScreenPresentation.ACTIVE_BRIGHTNESS;
        this.desiredBrightness = SearchScreenPresentation.ACTIVE_BRIGHTNESS;
      } catch (_) {
      }
      this.onIdleStateChanged(false);
      if (!this.visible || generation !== this.generation) return;
      try {
        await target.setWindowKeepScreenOn(true);
      } catch (_) {
      }
      if (this.visible && generation === this.generation && !this.facePresent) {
        this.scheduleNoFaceIdle();
      }
    }).catch((): void => {});
  }

  /** 逐帧和人数进度均可校正人脸状态；仅状态变化时切换策略，避免逐帧写窗口亮度。 */
  updateFacePresence(hasFace: boolean): void {
    if (!this.visible || this.facePresent === hasFace) return;
    this.facePresent = hasFace;
    this.clearIdleTimer();
    if (hasFace) {
      this.queueBrightness(SearchScreenPresentation.ACTIVE_BRIGHTNESS);
      this.onIdleStateChanged(false);
    } else {
      this.scheduleNoFaceIdle();
    }
  }

  leave(): void {
    this.visible = false;
    ++this.generation;
    this.facePresent = false;
    this.clearIdleTimer();
    this.onIdleStateChanged(false);
    this.operation = this.operation.then(async (): Promise<void> => {
      const target: window.Window | undefined = this.activeWindow;
      if (target === undefined) return;
      const brightness: number = this.previousBrightness;
      this.activeWindow = undefined;
      this.appliedBrightness = -1;
      this.desiredBrightness = -1;
      try {
        await target.setWindowBrightness(brightness);
      } catch (_) {
      }
      try {
        // 页面共用 Ability 窗口，离开搜索页后释放常亮。
        await target.setWindowKeepScreenOn(false);
      } catch (_) {
      }
    }).catch((): void => {});
  }

  private scheduleNoFaceIdle(): void {
    if (!this.visible || this.facePresent || this.activeWindow === undefined) return;
    this.clearIdleTimer();
    this.idleTimer = setTimeout((): void => {
      this.idleTimer = -1;
      if (this.visible && !this.facePresent) {
        // 与 Android/iOS 一致：确认连续 10 秒无人脸后再同时降低背光与相机会话帧率。
        this.queueBrightness(SearchScreenPresentation.IDLE_BRIGHTNESS);
        this.onIdleStateChanged(true);
      }
    }, SearchScreenPresentation.NO_FACE_IDLE_DELAY_MILLIS);
  }

  private clearIdleTimer(): void {
    if (this.idleTimer === -1) return;
    clearTimeout(this.idleTimer);
    this.idleTimer = -1;
  }

  /** 串行设置窗口亮度，避免快速进入/退出时迟到的异步写入覆盖恢复值。 */
  private queueBrightness(brightness: number): void {
    this.desiredBrightness = brightness;
    if (!this.visible || this.activeWindow === undefined || this.appliedBrightness === brightness) return;
    const generation: number = this.generation;
    this.operation = this.operation.then(async (): Promise<void> => {
      const target: window.Window | undefined = this.activeWindow;
      if (!this.visible || generation !== this.generation || target === undefined ||
        this.desiredBrightness !== brightness || this.appliedBrightness === brightness) return;
      try {
        await target.setWindowBrightness(brightness);
        this.appliedBrightness = brightness;
      } catch (_) {
      }
    }).catch((): void => {});
  }
}
