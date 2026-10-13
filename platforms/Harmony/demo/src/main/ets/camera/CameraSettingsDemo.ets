import { DemoL10n } from '../ui/DemoL10n';
import { DemoTheme } from '../ui/DemoTheme';
import { DemoPageHeader } from '../ui/DemoPageHeader';
import { common } from '@kit.AbilityKit';
import { CameraDemoSettings, CameraDemoSettingsStore } from './CameraDemoSettings';

/** 所有实时 Demo 共用的分辨率与坐标镜像校正设置。 */
@Component
export struct CameraSettingsDemo {
  onExit: () => void = () => {};
  @State private highResolution: boolean = false;
  @State private mirrorCoordinates: boolean = false;
  @State private loading: boolean = true;
  @State private saveState: string = DemoL10n.text("正在读取设置…");
  private visible: boolean = false;
  private lifecycleGeneration: number = 0;
  private savePending: boolean = false;
  private saving: boolean = false;
  private saveTask: Promise<void> | undefined = undefined;

  aboutToAppear(): void {
    this.visible = true;
    this.loading = true;
    this.saveState = DemoL10n.text("正在读取设置…");
    const generation: number = ++this.lifecycleGeneration;
    this.loadSettings(generation);
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.lifecycleGeneration += 1;
  }

  build() {
    Column() {
      DemoPageHeader({ title: DemoL10n.text("摄像头参数设置"), onBack: (): void => this.onExit() })

      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 12 }) {
            Text(DemoL10n.text("分析分辨率"))
              .fontSize(17)
              .fontColor(DemoTheme.contentText)
              .fontWeight(FontWeight.Bold)
              .width('100%')
            Text(DemoL10n.text("标准更省电；高清保留远处细节，自动选择 1080p 内兼容规格。"))
              .fontSize(13)
              .lineHeight(20)
              .fontColor(DemoTheme.contentSecondary)
              .width('100%')
            this.ResolutionOption('standard', DemoL10n.text("标准 · 接近 640×480"), false)
            this.ResolutionOption('high', DemoL10n.text("高清 · 接近 1280×720"), true)
          }
          .padding(20)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .width('100%')

          Row({ space: 14 }) {
            Column({ space: 5 }) {
              Text(DemoL10n.text("坐标镜像校正"))
                .fontSize(17)
                .fontColor(DemoTheme.contentText)
                .fontWeight(FontWeight.Bold)
              Text(DemoL10n.text("标记与预览左右相反时开启，不影响识别。"))
                .fontSize(13)
                .lineHeight(20)
                .fontColor(DemoTheme.contentSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.mirrorCoordinates })
              .enabled(!this.loading)
              .selectedColor(DemoTheme.contentAccent)
              .onChange((enabled: boolean) => this.setMirrorCoordinates(enabled))
          }
          .padding(20)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .width('100%')

          Text(this.saveState)
            .fontSize(13)
            .fontColor(this.saveState.includes(DemoL10n.text("失败")) ? DemoTheme.contentError : DemoTheme.contentAccent)
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .padding(20)
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DemoTheme.contentBackground)
  }

  @Builder
  private ResolutionOption(value: string, label: string, high: boolean) {
    Row({ space: 8 }) {
      Radio({ value: value, group: 'camera-resolution' })
        .checked(this.highResolution === high)
        .enabled(!this.loading)
        .radioStyle({ checkedBackgroundColor: DemoTheme.contentAccent })
        .accessibilityText(label)
        .onChange((checked: boolean): void => { if (checked) this.setHighResolution(high); })
      Text(label).fontSize(15).fontColor(DemoTheme.contentText).layoutWeight(1)
    }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 8, right: 8 })
      .enabled(!this.loading).onClick(() => this.setHighResolution(high))
  }

  private async loadSettings(generation: number): Promise<void> {
    try {
      const pendingSave: Promise<void> | undefined = this.saveTask;
      if (pendingSave !== undefined) {
        await pendingSave;
      }
      if (!this.visible || generation !== this.lifecycleGeneration) {
        return;
      }
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const settings: CameraDemoSettings = await CameraDemoSettingsStore.load(context);
      if (!this.visible || generation !== this.lifecycleGeneration) {
        return;
      }
      this.highResolution = settings.highResolution;
      this.mirrorCoordinates = settings.mirrorCoordinates;
      this.saveState = DemoL10n.text("已加载 · {0} · 坐标校正{1}", [String(settings.resolutionLabel()), String(settings.mirrorCoordinates ? DemoL10n.text("开") : DemoL10n.text("关"))]);
    } catch (error) {
      if (this.visible && generation === this.lifecycleGeneration) {
        this.saveState = DemoL10n.text("读取失败，使用默认设置：{0}", [String(error)]);
      }
    } finally {
      if (this.visible && generation === this.lifecycleGeneration) {
        this.loading = false;
      }
    }
  }

  private setHighResolution(enabled: boolean): void {
    if (this.loading || this.highResolution === enabled) {
      return;
    }
    this.highResolution = enabled;
    this.requestSave();
  }

  private setMirrorCoordinates(enabled: boolean): void {
    if (this.loading || this.mirrorCoordinates === enabled) {
      return;
    }
    this.mirrorCoordinates = enabled;
    this.requestSave();
  }

  private requestSave(): void {
    this.savePending = true;
    this.saveState = DemoL10n.text("正在保存…");
    if (!this.saving) {
      const task: Promise<void> = this.persistPendingSettings();
      this.saveTask = task;
      task.then((): void => this.clearSaveTask(task), (error: Error): void => {
        this.saving = false;
        this.clearSaveTask(task);
        if (this.visible) {
          this.saveState = DemoL10n.text("保存失败：{0}", [String(error)]);
        }
      });
    }
  }

  private clearSaveTask(task: Promise<void>): void {
    if (this.saveTask === task) {
      this.saveTask = undefined;
    }
  }

  private async persistPendingSettings(): Promise<void> {
    this.saving = true;
    let context: common.UIAbilityContext;
    try {
      context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (error) {
      this.savePending = false;
      this.saving = false;
      if (this.visible) {
        this.saveState = DemoL10n.text("保存失败：{0}", [String(error)]);
      }
      return;
    }
    while (this.savePending) {
      this.savePending = false;
      const settings = new CameraDemoSettings(this.highResolution, this.mirrorCoordinates);
      try {
        await CameraDemoSettingsStore.save(context, settings);
        if (this.visible) {
          this.saveState = DemoL10n.text("已保存 · {0} · 坐标校正{1}", [String(settings.resolutionLabel()), String(settings.mirrorCoordinates ? DemoL10n.text("开") : DemoL10n.text("关"))]);
        }
      } catch (error) {
        if (this.visible) {
          this.saveState = DemoL10n.text("保存失败：{0}", [String(error)]);
        }
      }
    }
    this.saving = false;
  }
}
