import { DemoL10n } from '../ui/DemoL10n';
import { FaceSearchProgress, FaceSearchStage, HiFaceError, HiFaceErrorCode } from 'hiface';

/** SDK 搜索阶段到 Demo 标题/说明的唯一映射，页面不重复解释枚举。 */
export class FaceSearchStatusUi {
  /** 与 Android 一致：仅恢复暂时失败的有效会话。 */
  static canResumeSearch(error: HiFaceError): boolean {
    return error.code === HiFaceErrorCode.NOT_READY || error.code === HiFaceErrorCode.PROCESSING_FAILED ||
      error.code === HiFaceErrorCode.DATABASE_ERROR;
  }

  static progressTitle(progress: FaceSearchProgress): string {
    if (progress.stage === FaceSearchStage.WAITING_FOR_FACE) return DemoL10n.text("等待人脸入镜");
    if (progress.stage === FaceSearchStage.FACE_TOO_SMALL) return DemoL10n.text("请靠近摄像头");
    if (progress.stage === FaceSearchStage.EMPTY_GALLERY) return DemoL10n.text("当前范围内暂无已录入人脸");
    if (progress.stage === FaceSearchStage.SUCCESS_INTERVAL) return DemoL10n.text("等待下一次搜索");
    return DemoL10n.text("正在搜索");
  }

  static progressDetail(progress: FaceSearchProgress): string {
    if (progress.stage === FaceSearchStage.EMPTY_GALLERY) return DemoL10n.text("请录入人脸或调整搜索设置");
    if (progress.stage === FaceSearchStage.FACE_TOO_SMALL) return DemoL10n.text("人脸太小，请靠近一些");
    if (progress.stage === FaceSearchStage.SEARCHING) return DemoL10n.text("正在匹配人脸库");
    if (progress.stage === FaceSearchStage.SUCCESS_INTERVAL) return DemoL10n.text("间隔结束后自动继续");
    return DemoL10n.text("面向镜头，入镜后自动识别");
  }
}
