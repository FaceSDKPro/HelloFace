import { i18n } from '@kit.LocalizationKit';
import { resourceManager } from '@kit.LocalizationKit';
import { DEMO_TEXT_RESOURCES, DemoTextResource } from './DemoTextResources';

/**
 * Demo locale and resources; raw SDK errors and logs remain available for developer diagnosis.
 *
 * Demo 跟随系统/应用语言选择资源；SDK 原始错误及日志继续供开发者诊断。
 */
export class DemoL10n {
  private static resources: resourceManager.ResourceManager | undefined = undefined;
  private static readonly cache: Map<string, string> = new Map();

  static followsChineseResources(): boolean {
    try {
      const language: string = i18n.System.getSystemLanguage().toLowerCase().replace('_', '-');
      return language === 'zh' || language.startsWith('zh-');
    } catch (_) {
      return false;
    }
  }

  static configure(resources: resourceManager.ResourceManager): void {
    DemoL10n.cache.clear();
    DemoL10n.resources = resources;
  }

  static text(key: string, args: string[] = []): string {
    const entry: DemoTextResource | undefined = DEMO_TEXT_RESOURCES[key];
    let value: string = DemoL10n.cache.get(key) ??
      (DemoL10n.followsChineseResources() ? key : (entry?.english ?? key));
    if (!DemoL10n.cache.has(key) && entry !== undefined && DemoL10n.resources !== undefined) {
      try { value = DemoL10n.resources.getStringByNameSync(entry.name); } catch (_) {}
    }
    DemoL10n.cache.set(key, value);
    return value.replace(/\{(\d+)\}/g, (match: string, index: string): string => {
      const position: number = Number(index);
      return position < args.length ? args[position] : match;
    });
  }
}
