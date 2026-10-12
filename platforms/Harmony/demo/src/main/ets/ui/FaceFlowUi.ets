import { FaceAction, FaceFlowProgress, FaceFlowStage, FaceFlowOutcome } from 'hiface';

const ACTION_TIMEOUT_MILLIS: number = 3000;
const FACE_ACQUISITION_TIMEOUT_MILLIS: number = 10000;

/** 与 Android FaceFlowUi / CaptureStatusUi 对应的流程提示。 */
export class FaceFlowUi {
  static progressTitle(progress: FaceFlowProgress, capture: boolean): string {
    if (progress.stage === FaceFlowStage.WAITING_FOR_FACE) {
      return '请将人脸移入圆框';
    }
    if (progress.stage === FaceFlowStage.MULTIPLE_FACES) {
      return '请确保仅一人入镜';
    }
    if (progress.stage === FaceFlowStage.FACE_TOO_SMALL) {
      return '请靠近一点';
    }
    if (progress.stage === FaceFlowStage.FACE_NOT_FRONTAL ||
      progress.stage === FaceFlowStage.FACE_FORWARD) {
      return capture ? '请摆正人脸' : '请正对屏幕';
    }
    if (progress.stage === FaceFlowStage.HOLD_STILL) {
      return capture ? '请保持不动' : '请正对屏幕';
    }
    if (progress.stage === FaceFlowStage.FACE_UNSTABLE) {
      return '请保持人脸稳定';
    }
    if (progress.action === FaceAction.SHAKE_HEAD) {
      return `请摇头（${progress.stepNumber}/${progress.stepCount}）`;
    }
    if (progress.action === FaceAction.NOD_HEAD) {
      return `请点头（${progress.stepNumber}/${progress.stepCount}）`;
    }
    if (progress.action === FaceAction.BLINK) {
      return `请眨眼（${progress.stepNumber}/${progress.stepCount}）`;
    }
    if (progress.action === FaceAction.MOUTH_OPEN) {
      return `请张嘴（${progress.stepNumber}/${progress.stepCount}）`;
    }
    return '请按提示完成动作';
  }

  static progressDetail(capture: boolean, progress: FaceFlowProgress): string {
    if (progress.stage === FaceFlowStage.PERFORM_ACTION && progress.stepCount > 0) {
      const totalSeconds: number = ACTION_TIMEOUT_MILLIS * progress.stepCount / 1000;
      return `安全随机动作 ${progress.stepNumber}/${progress.stepCount} · ` +
        `整组动作总时限 ${totalSeconds.toFixed(0)} 秒`;
    }
    if (progress.stage === FaceFlowStage.HOLD_STILL) {
      return capture ? '正脸质量已达标，保持稳定以提取 HF1 特征' :
        '动作已完成，正在稳定正脸并采集七帧双模型静默活体';
    }
    if (progress.stage === FaceFlowStage.FACE_UNSTABLE) {
      return '正在确认人脸框稳定，稳定后开始 0.7 秒抓拍倒计时';
    }
    if (progress.stage === FaceFlowStage.FACE_FORWARD ||
      progress.stage === FaceFlowStage.FACE_NOT_FRONTAL) {
      return capture ? '需要正脸才能生成可复用的验证基准' :
        '请回正后保持稳定；当前不会提前给出身份通过结论';
    }
    if (progress.stage === FaceFlowStage.MULTIPLE_FACES) {
      return '安全策略默认拒绝多人画面，请确保取景框中只有一张人脸';
    }
    if (progress.stage === FaceFlowStage.FACE_TOO_SMALL) {
      return '人脸区域过小，请靠近镜头后保持完整面部可见';
    }
    if (progress.action !== undefined) {
      return '动作阶段仍在计时，请重新将同一张人脸移入画面';
    }
    return `等待合格人脸，首次取脸最长 ${FACE_ACQUISITION_TIMEOUT_MILLIS / 1000} 秒`;
  }

  static outcomeTitle(outcome: FaceFlowOutcome): string {
    if (outcome === FaceFlowOutcome.PASSED) {
      return '通过';
    }
    if (outcome === FaceFlowOutcome.NOT_MATCHED) {
      return '非同一人';
    }
    if (outcome === FaceFlowOutcome.SPOOF_DETECTED) {
      return '疑似非真人';
    }
    if (outcome === FaceFlowOutcome.NO_FACE_TIMEOUT) {
      return '等待人脸超时';
    }
    if (outcome === FaceFlowOutcome.FACE_LOST) {
      return '人脸离开画面';
    }
    if (outcome === FaceFlowOutcome.MULTIPLE_FACES) {
      return '出现多张人脸';
    }
    if (outcome === FaceFlowOutcome.ACTION_TIMEOUT) {
      return '动作超时';
    }
    return '最终采样超时';
  }
}
