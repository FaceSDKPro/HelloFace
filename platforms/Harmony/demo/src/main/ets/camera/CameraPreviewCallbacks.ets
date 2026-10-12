import { Yuv420Frame } from 'hiface';

/** 状态与文案集中管理，页面按枚举判断就绪状态。 */
export enum CameraPreviewState {
  REQUESTING_PERMISSION = '正在请求相机权限…',
  OPENING = '正在打开相机…',
  TRYING_PROFILE = '正在尝试兼容相机规格…',
  RUNNING = '相机运行中'
}

export interface CameraPreviewCallbacks {
  onCameraState(state: CameraPreviewState, frontCamera: boolean, profile: string): void;
  /** 帧的平面数据独立于 ImageReceiver；Promise 未完成时仍排空相机缓冲，但不再投递 Native。 */
  onFrame(frame: Yuv420Frame): Promise<void>;
  onFrameDropped(total: number): void;
  onFrameError(message: string): void;
  onCameraError(message: string): void;
}
