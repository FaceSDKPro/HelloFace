import { FaceAction, FaceVerificationConfig } from 'hiface';

/**
 * Challenge and verification policy matching Android FaceVerificationActivity.
 *
 * Android FaceVerificationActivity 的挑战和验证策略。
 */
export class FaceVerificationFlow {
  static readonly VERIFICATION_ACTION_COUNT: number = 2;

  static config(referenceFeature: string, actions: ReadonlyArray<FaceAction>, silent: boolean = true): FaceVerificationConfig {
    return new FaceVerificationConfig(referenceFeature,
      FaceVerificationConfig.DEFAULT_THRESHOLD, silent, actions, 3000, 10000, true);
  }
}
