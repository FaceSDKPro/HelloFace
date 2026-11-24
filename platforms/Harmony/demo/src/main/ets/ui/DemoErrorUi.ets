import { DemoL10n } from './DemoL10n';
import { HiFaceError, HiFaceErrorCode } from 'hiface';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * Map stable SDK error codes to user guidance while recording the original error for developer
 * diagnosis.
 *
 * 将稳定 SDK 错误码转成用户提示，同时记录原始错误供开发者诊断。
 */
export class DemoErrorUi {
  static describe(error: HiFaceError): string {
    hilog.error(0xFF00, 'HiFaceDemo', 'SDK error: code=%{public}d message=%{public}s',
      error.code, error.message);
    if (error.code === HiFaceErrorCode.NOT_READY) return DemoL10n.text("引擎未就绪，请稍后重试");
    if (error.code === HiFaceErrorCode.CLOSED) return DemoL10n.text("会话已关闭，请重新进入");
    if (error.code === HiFaceErrorCode.BUSY) return DemoL10n.text("引擎正忙，请稍后重试");
    if (error.code === HiFaceErrorCode.MODEL_LOAD_FAILED) return DemoL10n.text("人脸模型加载失败");
    if (error.code === HiFaceErrorCode.INVALID_ARGUMENT) return DemoL10n.text("输入无效");
    if (error.code === HiFaceErrorCode.UNSUPPORTED_FORMAT) return DemoL10n.text("图片或视频帧格式不支持");
    if (error.code === HiFaceErrorCode.IMAGE_NO_FACE) return DemoL10n.text("未检测到人脸");
    if (error.code === HiFaceErrorCode.IMAGE_FACE_TOO_SMALL) return DemoL10n.text("人脸过小");
    if (error.code === HiFaceErrorCode.PROCESSING_FAILED) return DemoL10n.text("处理失败，请重试");
    if (error.code === HiFaceErrorCode.RESOURCE_EXHAUSTED) return DemoL10n.text("内存或存储空间不足");
    if (error.code === HiFaceErrorCode.NOT_FOUND) return DemoL10n.text("未找到人脸记录");
    if (error.code === HiFaceErrorCode.DATABASE_ERROR) return DemoL10n.text("无法访问人脸库");
    if (error.code === HiFaceErrorCode.ALREADY_EXISTS) return DemoL10n.text("人脸记录已存在");
    return DemoErrorUi.accessMessage(error) ?? DemoL10n.text("SDK 内部错误");
  }

  static accessMessage(error: HiFaceError): string | undefined {
    return DemoErrorUi.isAccessError(error) ? DemoL10n.text("功能不可用（错误码 {0}）", [String(error.code)]) : undefined;
  }

  static isAccessError(error: HiFaceError): boolean {
    return error.code === HiFaceErrorCode.LICENSE_MISSING || error.code === HiFaceErrorCode.LICENSE_INVALID ||
      error.code === HiFaceErrorCode.LICENSE_NOT_YET_VALID || error.code === HiFaceErrorCode.LICENSE_EXPIRED ||
      error.code === HiFaceErrorCode.LICENSE_FEATURE_DENIED || error.code === HiFaceErrorCode.LICENSE_CLOCK_INVALID;
  }

  /**
   * Configuration, model, format, and closed-state errors require fixing the cause, not repeated retries.
   *
   * 配置、模型、格式和关闭错误需要先修复原因，不提供无效重试。
   */
  static isRetryable(error: HiFaceError): boolean {
    return error.code === HiFaceErrorCode.NOT_READY ||
      error.code === HiFaceErrorCode.IMAGE_NO_FACE ||
      error.code === HiFaceErrorCode.IMAGE_FACE_TOO_SMALL ||
      error.code === HiFaceErrorCode.BUSY ||
      error.code === HiFaceErrorCode.PROCESSING_FAILED;
  }

  /**
   * Restart guided capture automatically only after a transient frame-processing failure.
   *
   * 仅在偶发帧处理失败后自动重启引导采集。
   */
  static shouldRestartCapture(error: HiFaceError): boolean {
    return error.code === HiFaceErrorCode.PROCESSING_FAILED;
  }
}
