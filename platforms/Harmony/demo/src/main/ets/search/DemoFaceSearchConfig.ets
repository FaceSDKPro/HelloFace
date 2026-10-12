import { FaceSearchSessionConfig, FaceSearchMode } from 'hiface';

/**
 * Demo 默认匹配成功后立即开始下一轮，与 SDK 公共默认保持一致。
 * 该参数不控制相机帧率，设置页允许配置 0–3000 ms。
 */
export const DEMO_SUCCESS_INTERVAL_MILLIS: number = 0;

export function createDemoFaceSearchConfig(): FaceSearchSessionConfig {
  return new FaceSearchSessionConfig(FaceSearchMode.SINGLE_FACE, '', '', true,
    FaceSearchSessionConfig.DEFAULT_THRESHOLD, DEMO_SUCCESS_INTERVAL_MILLIS, 3000, 3);
}
