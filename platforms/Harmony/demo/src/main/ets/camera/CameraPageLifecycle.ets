/**
 * Forward @Entry foreground/background events directly to the camera screen, independent of background
 * UI redraws.
 *
 * @Entry 的前后台事件直接通知相机页，不依赖后台是否还有 UI 重绘。
 */
export class CameraPageLifecycle {
  private leaveHandler: (() => void) | undefined = undefined;
  private bindingSequence: number = 0;
  private backHandler: (() => boolean) | undefined = undefined;
  // Foreground state survives child-page rebinding so a new page can pause immediately.
  private active: boolean = true;
  private pauseHandler: (() => void) | undefined = undefined;
  private resumeHandler: (() => void) | undefined = undefined;

  // Return the binding ID the caller must use when unregistering its callbacks.
  bind(pause: () => void, resume: () => void, back?: () => boolean, leave?: () => void): number {
    const binding: number = ++this.bindingSequence;
    this.leaveHandler = leave;
    this.backHandler = back;
    this.pauseHandler = pause;
    this.resumeHandler = resume;
    if (!this.active) pause();
    return binding;
  }

  // A binding ID prevents an old screen from removing the current screen's callbacks.
  // 绑定编号防止旧页面移除当前页面的回调。
  unbind(binding?: number): void {
    if (binding !== undefined && binding !== this.bindingSequence) return;
    this.leaveHandler = undefined;
    this.backHandler = undefined;
    this.pauseHandler = undefined;
    this.resumeHandler = undefined;
  }

  leave(): void {
    const leave: (() => void) | undefined = this.leaveHandler;
    this.unbind();
    leave?.();
  }

  handleBack(): boolean { return this.backHandler?.() ?? false; }

  isActive(): boolean {
    return this.active;
  }

  pause(): void {
    if (!this.active) return;
    this.active = false;
    this.pauseHandler?.();
  }

  resume(): void {
    if (this.active) return;
    this.active = true;
    this.resumeHandler?.();
  }
}
