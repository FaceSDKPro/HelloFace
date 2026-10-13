import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DemoL10n } from '../ui/DemoL10n';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0xFF00;

/** Demo 唯一 Ability：只加载首页，SDK 初始化和功能导航由 Index 管理。 */
export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    DemoL10n.configure(this.context.resourceManager);
    hilog.info(DOMAIN, 'HiFaceDemo', 'EntryAbility created');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(DOMAIN, 'HiFaceDemo', 'Failed to load Index: %{public}d', error.code);
      }
    });
  }
}
