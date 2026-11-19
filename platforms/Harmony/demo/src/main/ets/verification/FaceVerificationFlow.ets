import { DemoErrorUi } from '../ui/DemoErrorUi';
import { DemoL10n } from '../ui/DemoL10n';
import { FaceAction, FaceCaptureResult, FaceVerificationConfig, HiFaceSdk, RgbaImage } from 'hiface';

/**
 * Challenge and verification policy matching Android FaceVerificationActivity.
 *
 * Android FaceVerificationActivity 的挑战和验证策略。
 */
export class FaceVerificationFlow {
  static readonly VERIFICATION_ACTION_COUNT: number = 2;

  /** Count every detection, including a face that failed alignment or feature extraction. */
  static async referenceFromPhoto(sdk: HiFaceSdk, image: RgbaImage): Promise<FaceCaptureResult> {
    const result = await sdk.capture().facesFromRgba(image);
    if (result.isFailure()) throw new Error(DemoErrorUi.describe(result.requireError()));
    const faces = result.requireValue();
    if (faces.length !== 1) throw new Error(DemoL10n.text("请选择只有一张人脸的照片。"));
    const sample = faces[0].capture;
    if (sample.isFailure()) throw new Error(DemoErrorUi.describe(sample.requireError()));
    return sample.requireValue();
  }

  static config(referenceFeature: string, actions: ReadonlyArray<FaceAction>, silent: boolean = true): FaceVerificationConfig {
    return new FaceVerificationConfig(referenceFeature,
      FaceVerificationConfig.DEFAULT_THRESHOLD, silent, actions, 3000, 10000, true);
  }
}
