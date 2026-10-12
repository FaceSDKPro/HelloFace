import { HiFaceSdk, HiFaceResult, HiFaceErrorCode } from 'hiface';
import { common } from '@kit.AbilityKit';

/** 初始化失败可重建；退出或重试后，旧初始化不能重新激活页面。 */
export class DemoSdkSession {
  private generation: number = 0;
  private sdk: HiFaceSdk | undefined = undefined;

  async initialize(context: common.UIAbilityContext): Promise<HiFaceResult<HiFaceSdk>> {
    this.close();
    const generation: number = this.generation;
    let candidate: HiFaceSdk | undefined = undefined;
    try {
      candidate = HiFaceSdk.create(context);
      this.sdk = candidate;
      const ready: HiFaceResult<boolean> = await candidate.whenReady();
      if (generation !== this.generation) {
        candidate.close();
        return HiFaceResult.failure<HiFaceSdk>(HiFaceErrorCode.CLOSED, 'Demo initialization cancelled');
      }
      if (ready.isFailure()) {
        candidate.close();
        this.sdk = undefined;
        const error = ready.requireError();
        return HiFaceResult.failure<HiFaceSdk>(error.code, error.message);
      }
      return HiFaceResult.success(candidate);
    } catch (_) {
      candidate?.close();
      if (generation === this.generation) this.sdk = undefined;
      return HiFaceResult.failure<HiFaceSdk>(generation === this.generation ?
        HiFaceErrorCode.INTERNAL_ERROR : HiFaceErrorCode.CLOSED, 'Unable to initialize Demo SDK');
    }
  }

  close(): void {
    this.generation += 1;
    this.sdk?.close();
    this.sdk = undefined;
  }
}
