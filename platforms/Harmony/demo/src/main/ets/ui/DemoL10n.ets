import { i18n } from '@kit.LocalizationKit';
import { resourceManager } from '@kit.LocalizationKit';
import { DEMO_TEXT_RESOURCES, DemoTextResource } from './DemoTextResources';

/** Demo 的区域语言和资源；SDK 原始错误及日志继续供开发者诊断。 */
export class DemoL10n {
  private static resources: resourceManager.ResourceManager | undefined = undefined;
  private static readonly cache: Map<string, string> = new Map();
  private static language: string = DemoL10n.languageForRegion(DemoL10n.systemRegion());

  static languageForRegion(region: string): string {
    const normalized: string = region.toUpperCase();
    return normalized === 'CN' || normalized === 'HK' || normalized === 'MO' || normalized === 'TW'
      ? 'zh-Hans' : 'en';
  }

  private static systemRegion(): string {
    try { return i18n.System.getSystemRegion(); } catch (_) { return ''; }
  }

  static configure(resources: resourceManager.ResourceManager): void {
    DemoL10n.cache.clear();
    DemoL10n.language = DemoL10n.languageForRegion(DemoL10n.systemRegion());
    const configuration: resourceManager.Configuration = resources.getConfigurationSync();
    configuration.locale = DemoL10n.language === 'zh-Hans' ? 'zh-Hans-CN' : 'en-US';
    DemoL10n.resources = resources.getOverrideResourceManager(configuration);
    // 同时选择菜单、权限理由等原生资源；不修改系统语言或地区。
    i18n.System.setAppPreferredLanguage(configuration.locale);
  }

  static text(key: string, args: string[] = []): string {
    const entry: DemoTextResource | undefined = DEMO_TEXT_RESOURCES[key];
    let value: string = DemoL10n.cache.get(key) ?? (DemoL10n.language === 'zh-Hans' ? key : (entry?.english ?? key));
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
