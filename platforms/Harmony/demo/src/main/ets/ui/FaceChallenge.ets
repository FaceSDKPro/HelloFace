import { util } from '@kit.ArkTS';
import { FaceAction } from 'hiface';

/** 为 Demo 生成不可预测且不重复的动作挑战；生产接入也应由可信随机源生成挑战。 */
export class FaceChallenge {
  static async randomActions(count: number): Promise<ReadonlyArray<FaceAction>> {
    const actions: FaceAction[] = [
      FaceAction.SHAKE_HEAD,
      FaceAction.NOD_HEAD,
      FaceAction.BLINK,
      FaceAction.MOUTH_OPEN
    ];
    if (!Number.isInteger(count) || count < 1 || count > actions.length) {
      throw new Error('challenge action count must be between 1 and 4');
    }
    for (let index: number = actions.length - 1; index > 0; index -= 1) {
      const swapIndex: number = FaceChallenge.randomIndex(index + 1);
      const action: FaceAction = actions[index];
      actions[index] = actions[swapIndex];
      actions[swapIndex] = action;
    }
    return actions.slice(0, count);
  }

  private static randomIndex(upperExclusive: number): number {
    const acceptanceLimit: number = Math.floor(256 / upperExclusive) * upperExclusive;
    while (true) {
      let bytes: Uint8Array;
      try {
        bytes = util.generateRandomBinaryUUID(false);
      } catch (error) {
        throw new Error(`unable to generate secure challenge bytes: ${error}`);
      }
      const value: number = bytes[0];
      if (value < acceptanceLimit) {
        return value % upperExclusive;
      }
    }
  }
}
