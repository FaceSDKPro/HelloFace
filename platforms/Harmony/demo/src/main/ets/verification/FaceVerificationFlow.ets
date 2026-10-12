import { FaceAction, FaceVerificationConfig } from 'hiface';

/** Android FaceVerificationActivity 的挑战和验证策略。 */
export class FaceVerificationFlow {
  static readonly VERIFICATION_ACTION_COUNT: number = 2;

  static config(referenceFeature: string, actions: ReadonlyArray<FaceAction>): FaceVerificationConfig {
    return new FaceVerificationConfig(referenceFeature,
      FaceVerificationConfig.DEFAULT_THRESHOLD, true, actions, 3000, 10000, true);
  }
}
