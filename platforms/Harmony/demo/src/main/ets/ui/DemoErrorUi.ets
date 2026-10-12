import { HiFaceError, HiFaceErrorCode } from 'hiface';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 将稳定 SDK 错误码转成用户提示，同时记录原始错误供开发者诊断。 */
export class DemoErrorUi {
  static describe(error: HiFaceError): string {
    hilog.error(0xFF00, 'HiFaceDemo', 'SDK error: code=%{public}d message=%{public}s',
      error.code, error.message);
    if (error.code === HiFaceErrorCode.NOT_READY) return '人脸引擎尚未就绪，请稍后重试';
    if (error.code === HiFaceErrorCode.CLOSED) return '当前人脸会话已关闭，请返回后重新进入';
    if (error.code === HiFaceErrorCode.BUSY) return '已有一个人脸请求正在处理，请稍后重试';
    if (error.code === HiFaceErrorCode.MODEL_LOAD_FAILED) return '人脸模型加载失败，请检查安装包和设备环境';
    if (error.code === HiFaceErrorCode.INVALID_ARGUMENT) return '输入数据无效，请检查后重试';
    if (error.code === HiFaceErrorCode.UNSUPPORTED_FORMAT) return '当前图片或相机帧格式不受支持';
    if (error.code === HiFaceErrorCode.IMAGE_NO_FACE) return '图片中没有检测到人脸';
    if (error.code === HiFaceErrorCode.IMAGE_FACE_TOO_SMALL) return '图片中的人脸过小，请选择更清晰的照片';
    if (error.code === HiFaceErrorCode.PROCESSING_FAILED) return '人脸处理未能完成，请重试';
    if (error.code === HiFaceErrorCode.RESOURCE_EXHAUSTED) return '设备资源不足，暂时无法完成人脸处理';
    return '人脸服务发生内部错误';
  }

  /** 与 Android Demo 一致：配置、模型、格式和关闭错误需要先修复原因，不显示无效重试。 */
  static isRetryable(error: HiFaceError): boolean {
    return error.code === HiFaceErrorCode.NOT_READY ||
      error.code === HiFaceErrorCode.IMAGE_NO_FACE ||
      error.code === HiFaceErrorCode.IMAGE_FACE_TOO_SMALL ||
      error.code === HiFaceErrorCode.BUSY ||
      error.code === HiFaceErrorCode.PROCESSING_FAILED;
  }

  /** 与 Android 一致：引导录入仅对偶发的帧处理失败自动创建下一次请求。 */
  static shouldRestartCapture(error: HiFaceError): boolean {
    return error.code === HiFaceErrorCode.PROCESSING_FAILED;
  }
}
