import { Yuv420Frame } from 'hiface';

/** 状态与文案集中管理，页面按枚举判断就绪状态。 */
export enum CameraPreviewState {
  REQUESTING_PERMISSION = 'requesting_permission',
  OPENING = 'opening',
  TRYING_PROFILE = 'trying_profile',
  RUNNING = 'running'
}

export interface CameraPreviewCallbacks {
  onCameraState(state: CameraPreviewState, frontCamera: boolean, profile: string): void;
  /** 帧的平面数据独立于 ImageReceiver；Promise 未完成时仍排空相机缓冲，但不再投递 Native。 */
  onFrame(frame: Yuv420Frame): Promise<void>;
  onFrameDropped(total: number): void;
  onFrameError(message: string): void;
  onCameraError(message: string): void;
}
