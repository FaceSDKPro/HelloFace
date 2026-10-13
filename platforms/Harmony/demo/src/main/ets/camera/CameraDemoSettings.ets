import { DemoL10n } from '../ui/DemoL10n';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'hiface_camera_settings';
const HIGH_RESOLUTION_KEY: string = 'high_resolution';
const MIRROR_COORDINATES_KEY: string = 'mirror_coordinates';

/** Demo 宿主相机偏好，不属于 HiFace HAR 的推理配置。 */
export class CameraDemoSettings {
  readonly highResolution: boolean;
  readonly mirrorCoordinates: boolean;

  constructor(highResolution: boolean = false, mirrorCoordinates: boolean = false) {
    this.highResolution = highResolution;
    this.mirrorCoordinates = mirrorCoordinates;
  }

  resolutionLabel(): string {
    return this.highResolution ? DemoL10n.text("高清（接近 1280×720）") : DemoL10n.text("标准（接近 640×480）");
  }
}

/** 使用应用 Preferences 持久化；两个字段始终作为同一快照写入并 flush。 */
export class CameraDemoSettingsStore {
  static async load(context: common.UIAbilityContext): Promise<CameraDemoSettings> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      const highResolution = await store.get(HIGH_RESOLUTION_KEY, false);
      const mirrorCoordinates = await store.get(MIRROR_COORDINATES_KEY, false);
      return new CameraDemoSettings(highResolution === true, mirrorCoordinates === true);
    } catch (error) {
      throw new Error(`Unable to load camera settings: ${error}`);
    }
  }

  static async save(context: common.UIAbilityContext, settings: CameraDemoSettings): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      await store.put(HIGH_RESOLUTION_KEY, settings.highResolution);
      await store.put(MIRROR_COORDINATES_KEY, settings.mirrorCoordinates);
      await store.flush();
    } catch (error) {
      throw new Error(`Unable to save camera settings: ${error}`);
    }
  }
}
