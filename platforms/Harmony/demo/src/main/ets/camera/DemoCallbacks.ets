import { FaceFlowListener, FaceFlowProgress, FaceFlowResult, FaceSearchFrame,
  FaceSearchListener, FaceSearchProgress, FaceSearchResult, HiFaceError, Yuv420Frame } from 'hiface';
import { CameraPreviewCallbacks, CameraPreviewState } from './CameraPreviewCallbacks';

// ArkTS 不支持用对象字面量实现带方法的接口；具体类型只保存回调，不包装 SDK 或业务状态。
export class DemoFlowListener implements FaceFlowListener {
  readonly onProgress: (progress: FaceFlowProgress) => void;
  readonly onResult: (result: FaceFlowResult) => void;
  readonly onError: (error: HiFaceError) => void;

  constructor(onProgress: (progress: FaceFlowProgress) => void,
    onResult: (result: FaceFlowResult) => void, onError: (error: HiFaceError) => void) {
    this.onProgress = onProgress;
    this.onResult = onResult;
    this.onError = onError;
  }
}

export class DemoSearchListener implements FaceSearchListener {
  readonly onFrame: (frame: FaceSearchFrame) => void;
  readonly onProgress: (progress: FaceSearchProgress) => void;
  readonly onResult: (result: FaceSearchResult) => void;
  readonly onError: (error: HiFaceError) => void;

  constructor(onFrame: (frame: FaceSearchFrame) => void,
    onProgress: (progress: FaceSearchProgress) => void,
    onResult: (result: FaceSearchResult) => void, onError: (error: HiFaceError) => void) {
    this.onFrame = onFrame;
    this.onProgress = onProgress;
    this.onResult = onResult;
    this.onError = onError;
  }
}

export class DemoCameraCallbacks implements CameraPreviewCallbacks {
  readonly onCameraState: (state: CameraPreviewState, frontCamera: boolean, profile: string) => void;
  readonly onFrame: (frame: Yuv420Frame) => Promise<void>;
  readonly onFrameDropped: (total: number) => void;
  readonly onFrameError: (message: string) => void;
  readonly onCameraError: (message: string) => void;

  constructor(onCameraState: (state: CameraPreviewState, frontCamera: boolean, profile: string) => void,
    onFrame: (frame: Yuv420Frame) => Promise<void>, onFrameDropped: (total: number) => void,
    onFrameError: (message: string) => void, onCameraError: (message: string) => void) {
    this.onCameraState = onCameraState;
    this.onFrame = onFrame;
    this.onFrameDropped = onFrameDropped;
    this.onFrameError = onFrameError;
    this.onCameraError = onCameraError;
  }
}
