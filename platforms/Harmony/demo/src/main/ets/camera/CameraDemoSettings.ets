import { DemoL10n } from '../ui/DemoL10n';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'hiface_camera_settings';
const HIGH_RESOLUTION_KEY: string = 'high_resolution';
const RESOLUTION_TIER_KEY: string = 'resolution_tier';
const MIRROR_COORDINATES_KEY: string = 'mirror_coordinates';
const ZOOM_RATIO_KEY: string = 'zoom_ratio';
const PREFER_BACK_CAMERA_KEY: string = 'prefer_back_camera';

export enum CameraAnalysisResolution {
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high'
}

export interface CameraResolutionPreset {
  readonly tier: CameraAnalysisResolution;
  readonly width: number;
  readonly height: number;
  readonly labelKey: string;
}

// Share the nominal sizes between the settings labels and CameraKit profile selection.
export const CAMERA_RESOLUTION_PRESETS: CameraResolutionPreset[] = [
  { tier: CameraAnalysisResolution.LOW, width: 640, height: 480, labelKey: '低 · {0} × {1}' },
  { tier: CameraAnalysisResolution.MEDIUM, width: 1280, height: 960, labelKey: '中 · {0} × {1}' },
  { tier: CameraAnalysisResolution.HIGH, width: 1440, height: 1080, labelKey: '高 · {0} × {1}' }
];

export function cameraResolutionPreset(tier: CameraAnalysisResolution | undefined): CameraResolutionPreset {
  return CAMERA_RESOLUTION_PRESETS.find((preset: CameraResolutionPreset): boolean => preset.tier === tier)
    ?? CAMERA_RESOLUTION_PRESETS[0];
}

export function cameraResolutionLabel(preset: CameraResolutionPreset): string {
  return DemoL10n.text(preset.labelKey, [String(preset.width), String(preset.height)]);
}

/**
 * Demo host camera preferences, separate from inference configuration in the HiFace HAR.
 *
 * Demo 宿主相机偏好，不属于 HiFace HAR 的推理配置。
 */
export class CameraDemoSettings {
  // The settings screen leaves this undefined when no override is saved.
  readonly resolution: CameraAnalysisResolution | undefined;
  readonly mirrorCoordinates: boolean;
  readonly zoomRatio: number;
  readonly prefersBackCamera: boolean;

  constructor(resolution: CameraAnalysisResolution | undefined = undefined, mirrorCoordinates: boolean = false,
    zoomRatio: number = 0, prefersBackCamera: boolean = false) {
    this.resolution = resolution;
    this.mirrorCoordinates = mirrorCoordinates;
    this.zoomRatio = Number.isFinite(zoomRatio) && zoomRatio > 0 ? zoomRatio : 0;
    this.prefersBackCamera = prefersBackCamera;
  }

  resolutionLabel(): string {
    return this.resolution === undefined ? DemoL10n.text("按功能默认")
      : cameraResolutionLabel(cameraResolutionPreset(this.resolution));
  }
}

/**
 * Persist through app Preferences and flush the camera settings as one snapshot.
 *
 * 使用应用 Preferences 持久化；相机设置作为同一快照写入并 flush。
 */
export class CameraDemoSettingsStore {
  private static pendingSave: Promise<void> = Promise.resolve();

  // The next camera page waits for the settings page's entire save loop.
  static trackSave(task: Promise<void>): void {
    CameraDemoSettingsStore.pendingSave = task.catch((): void => {});
  }

  static async load(context: common.UIAbilityContext,
    fallback: CameraAnalysisResolution | undefined = undefined): Promise<CameraDemoSettings> {
    try {
      await CameraDemoSettingsStore.pendingSave;
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      const stored = await store.get(RESOLUTION_TIER_KEY, '');
      let resolution = CAMERA_RESOLUTION_PRESETS.find((preset: CameraResolutionPreset): boolean =>
        preset.tier === stored)?.tier;
      // Preserve the old 720p opt-in as Medium. A disabled or missing switch uses the feature default.
      if (stored === '' && await store.get(HIGH_RESOLUTION_KEY, false) === true) {
        resolution = CameraAnalysisResolution.MEDIUM;
      }
      const mirrorCoordinates = await store.get(MIRROR_COORDINATES_KEY, false);
      const zoomRatio = await store.get(ZOOM_RATIO_KEY, 0);
      const prefersBackCamera = await store.get(PREFER_BACK_CAMERA_KEY, false);
      return new CameraDemoSettings(resolution ?? fallback, mirrorCoordinates === true,
        typeof zoomRatio === 'number' ? zoomRatio : 0, prefersBackCamera === true);
    } catch (error) {
      throw new Error(`Unable to load camera settings: ${error}`);
    }
  }

  static async save(context: common.UIAbilityContext, settings: CameraDemoSettings): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      await store.put(RESOLUTION_TIER_KEY, settings.resolution ?? '');
      await store.put(MIRROR_COORDINATES_KEY, settings.mirrorCoordinates);
      await store.put(ZOOM_RATIO_KEY, settings.zoomRatio);
      await store.put(PREFER_BACK_CAMERA_KEY, settings.prefersBackCamera);
      await store.flush();
    } catch (error) {
      throw new Error(`Unable to save camera settings: ${error}`);
    }
  }
}
