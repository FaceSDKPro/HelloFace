import { FaceSearchListener, FaceSearchFrame, FaceSearchProgress, FaceSearchResult, HiFaceError } from 'hiface';

/** 将 SDK 搜索监听器适配为页面闭包，与 Android Activity 直接实现监听器的职责相同。 */
export class DemoSearchListener implements FaceSearchListener {
  private readonly frameHandler: (frame: FaceSearchFrame) => void;
  private readonly progressHandler: (progress: FaceSearchProgress) => void;
  private readonly resultHandler: (result: FaceSearchResult) => void;
  private readonly errorHandler: (error: HiFaceError) => void;

  constructor(frameHandler: (frame: FaceSearchFrame) => void,
    progressHandler: (progress: FaceSearchProgress) => void,
    resultHandler: (result: FaceSearchResult) => void,
    errorHandler: (error: HiFaceError) => void) {
    this.frameHandler = frameHandler;
    this.progressHandler = progressHandler;
    this.resultHandler = resultHandler;
    this.errorHandler = errorHandler;
  }

  onFrame(frame: FaceSearchFrame): void {
    this.frameHandler(frame);
  }

  onProgress(progress: FaceSearchProgress): void {
    this.progressHandler(progress);
  }

  onResult(result: FaceSearchResult): void {
    this.resultHandler(result);
  }

  onError(error: HiFaceError): void {
    this.errorHandler(error);
  }
}
