import { Yuv420Frame } from 'hiface';
import { CameraPreviewCallbacks, CameraPreviewState } from './CameraPreviewCallbacks';

/** 把 CameraPreviewController 的命名回调转交给页面，避免控制器反向依赖 ArkUI 组件。 */
export class DemoCameraCallbacks implements CameraPreviewCallbacks {
  private readonly stateHandler: (state: CameraPreviewState, frontCamera: boolean, profile: string) => void;
  private readonly frameHandler: (frame: Yuv420Frame) => Promise<void>;
  private readonly droppedHandler: (total: number) => void;
  private readonly frameErrorHandler: (message: string) => void;
  private readonly errorHandler: (message: string) => void;

  constructor(stateHandler: (state: CameraPreviewState, frontCamera: boolean, profile: string) => void,
    frameHandler: (frame: Yuv420Frame) => Promise<void>,
    droppedHandler: (total: number) => void, frameErrorHandler: (message: string) => void,
    errorHandler: (message: string) => void) {
    this.stateHandler = stateHandler;
    this.frameHandler = frameHandler;
    this.droppedHandler = droppedHandler;
    this.frameErrorHandler = frameErrorHandler;
    this.errorHandler = errorHandler;
  }

  onCameraState(state: CameraPreviewState, frontCamera: boolean, profile: string): void {
    this.stateHandler(state, frontCamera, profile);
  }

  onFrame(frame: Yuv420Frame): Promise<void> {
    return this.frameHandler(frame);
  }

  onFrameDropped(total: number): void {
    this.droppedHandler(total);
  }

  onFrameError(message: string): void {
    this.frameErrorHandler(message);
  }

  onCameraError(message: string): void {
    this.errorHandler(message);
  }
}
