import { FaceFlowListener, FaceFlowProgress, FaceFlowResult, HiFaceError } from 'hiface';

/** 将 SDK 流程监听器适配为页面闭包；仅属于 Demo 展示层。 */
export class DemoFlowListener implements FaceFlowListener {
  private readonly progressHandler: (progress: FaceFlowProgress) => void;
  private readonly resultHandler: (result: FaceFlowResult) => void;
  private readonly errorHandler: (error: HiFaceError) => void;

  constructor(progressHandler: (progress: FaceFlowProgress) => void,
    resultHandler: (result: FaceFlowResult) => void,
    errorHandler: (error: HiFaceError) => void) {
    this.progressHandler = progressHandler;
    this.resultHandler = resultHandler;
    this.errorHandler = errorHandler;
  }

  onProgress(progress: FaceFlowProgress): void {
    this.progressHandler(progress);
  }

  onResult(result: FaceFlowResult): void {
    this.resultHandler(result);
  }

  onError(error: HiFaceError): void {
    this.errorHandler(error);
  }
}
