import { DemoL10n } from './DemoL10n';
import { FaceAction, FaceFlowProgress, FaceFlowStage, FaceFlowOutcome } from 'hiface';

const ACTION_TIMEOUT_MILLIS: number = 3000;
const FACE_ACQUISITION_TIMEOUT_MILLIS: number = 10000;

export interface FaceFlowGuidance {
  title: string;
  speech?: string;
}

/**
 * Flow guidance corresponding to Android FaceFlowUi / CaptureStatusUi.
 *
 * 与 Android FaceFlowUi / CaptureStatusUi 对应的流程提示。
 */
export class FaceFlowUi {
  static guidance(progress: FaceFlowProgress, capture: boolean): FaceFlowGuidance {
    let title: string;
    switch (progress.stage) {
      case FaceFlowStage.WAITING_FOR_FACE:
        title = DemoL10n.text("请将人脸移入圆框");
        break;
      case FaceFlowStage.MULTIPLE_FACES:
        title = DemoL10n.text("请确保仅一人入镜");
        break;
      case FaceFlowStage.FACE_TOO_SMALL:
        title = DemoL10n.text("请靠近一点");
        break;
      case FaceFlowStage.FACE_NOT_FRONTAL:
      case FaceFlowStage.FACE_FORWARD:
        title = DemoL10n.text(capture ? "请摆正人脸" : "请正对屏幕");
        break;
      case FaceFlowStage.HOLD_STILL:
        title = DemoL10n.text(capture ? "请保持不动" : "请正对屏幕");
        break;
      case FaceFlowStage.FACE_UNSTABLE:
        return { title: DemoL10n.text("请保持人脸稳定") };
      case FaceFlowStage.PERFORM_ACTION:
        return FaceFlowUi.actionGuidance(progress, capture);
      default:
        return { title: DemoL10n.text("请按提示完成动作") };
    }
    return { title, speech: capture ? undefined : title };
  }

  private static actionGuidance(progress: FaceFlowProgress, capture: boolean): FaceFlowGuidance {
    let titleKey: string;
    let nameKey: string;
    switch (progress.action) {
      case FaceAction.SHAKE_HEAD:
        titleKey = "请摇头（{0}/{1}）";
        nameKey = "摇头";
        break;
      case FaceAction.NOD_HEAD:
        titleKey = "请点头（{0}/{1}）";
        nameKey = "点头";
        break;
      case FaceAction.BLINK:
        titleKey = "请眨眼（{0}/{1}）";
        nameKey = "眨眼";
        break;
      case FaceAction.MOUTH_OPEN:
        titleKey = "请张嘴（{0}/{1}）";
        nameKey = "张嘴";
        break;
      default:
        return { title: DemoL10n.text("请按提示完成动作") };
    }
    return {
      title: DemoL10n.text(titleKey, [String(progress.stepNumber), String(progress.stepCount)]),
      speech: capture ? undefined : DemoL10n.text(nameKey)
    };
  }

  static progressDetail(capture: boolean, progress: FaceFlowProgress): string {
    if (progress.stage === FaceFlowStage.PERFORM_ACTION && progress.stepCount > 0) {
      const totalSeconds: number = ACTION_TIMEOUT_MILLIS * progress.stepCount / 1000;
      return DemoL10n.text("安全随机动作 {0}/{1} · ", [String(progress.stepNumber), String(progress.stepCount)]) +
        DemoL10n.text("整组动作总时限 {0} 秒", [String(totalSeconds.toFixed(0))]);
    }
    if (progress.stage === FaceFlowStage.HOLD_STILL) {
      return capture ? DemoL10n.text("正脸合格，请保持稳定") :
        DemoL10n.text("动作完成，请保持正脸稳定");
    }
    if (progress.stage === FaceFlowStage.FACE_UNSTABLE) {
      return DemoL10n.text("保持稳定，随后倒计时 0.7 秒抓拍");
    }
    if (progress.stage === FaceFlowStage.FACE_FORWARD ||
      progress.stage === FaceFlowStage.FACE_NOT_FRONTAL) {
      return capture ? DemoL10n.text("需要正脸才能生成可复用的验证基准") :
        DemoL10n.text("请回正并保持稳定，等待验证完成");
    }
    if (progress.stage === FaceFlowStage.MULTIPLE_FACES) {
      return DemoL10n.text("请确保画面中只有一张人脸");
    }
    if (progress.stage === FaceFlowStage.FACE_TOO_SMALL) {
      return DemoL10n.text("人脸区域过小，请靠近镜头后保持完整面部可见");
    }
    if (progress.action !== undefined) {
      return DemoL10n.text("计时继续，请将同一人脸移回画面");
    }
    return DemoL10n.text("等待合格人脸，首次取脸最长 {0} 秒", [String(FACE_ACQUISITION_TIMEOUT_MILLIS / 1000)]);
  }

  static outcomeTitle(outcome: FaceFlowOutcome): string {
    if (outcome === FaceFlowOutcome.PASSED) {
      return DemoL10n.text("通过");
    }
    if (outcome === FaceFlowOutcome.NOT_MATCHED) {
      return DemoL10n.text("非同一人");
    }
    if (outcome === FaceFlowOutcome.SPOOF_DETECTED) {
      return DemoL10n.text("疑似非真人");
    }
    if (outcome === FaceFlowOutcome.NO_FACE_TIMEOUT) {
      return DemoL10n.text("等待人脸超时");
    }
    if (outcome === FaceFlowOutcome.FACE_LOST) {
      return DemoL10n.text("人脸离开画面");
    }
    if (outcome === FaceFlowOutcome.MULTIPLE_FACES) {
      return DemoL10n.text("出现多张人脸");
    }
    if (outcome === FaceFlowOutcome.ACTION_TIMEOUT) {
      return DemoL10n.text("动作超时");
    }
    return DemoL10n.text("最终采样超时");
  }
}
