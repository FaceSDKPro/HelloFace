import { DemoL10n } from '../ui/DemoL10n';
import { FaceSearchSessionConfig, FaceSearchMode } from 'hiface';
import { DemoTheme } from '../ui/DemoTheme';
import { createDemoFaceSearchConfig, DEMO_SUCCESS_INTERVAL_MILLIS } from './DemoFaceSearchConfig';

/** 搜索参数草稿独立于相机会话；取消不写回，校验通过后一次提交。 */
@Component
export struct SearchSettingsDialog {
  @Prop initialConfig: FaceSearchSessionConfig = createDemoFaceSearchConfig();
  @Prop viewportHeight: number = 600;
  onCancel: () => void = () => {};
  onApply: (config: FaceSearchSessionConfig) => void = () => {};
  @State private draftSearchMode: FaceSearchMode = FaceSearchMode.SINGLE_FACE;
  @State private draftSearchGroup: string = '';
  @State private draftSearchTag: string = '';
  @State private draftSearchLiveness: boolean = true;
  @State private draftMaxFacesText: string = '3';
  @State private draftThresholdText: string = '0.80';
  @State private draftIntervalText: string = `${DEMO_SUCCESS_INTERVAL_MILLIS}`;
  @State private draftTimeoutText: string = '3000';
  @State private searchAdvancedVisible: boolean = false;
  @State private searchSettingsError: string = '';

  aboutToAppear(): void {
    this.setSearchSettingsDraft(this.initialConfig);
    this.searchAdvancedVisible = false;
  }

  build() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor('#99000000').onClick(() => {})
      Column({ space: 12 }) {
        Text(DemoL10n.text("搜索设置")).fontSize(20).fontWeight(FontWeight.Medium).fontColor('#FFFFFF').width('100%')
          .padding({ left: 16, right: 16, top: 20 })
        Scroll() {
          Column({ space: 12 }) {
            this.SectionTitle(DemoL10n.text("搜索模式"))
            Row() {
              this.SearchModeButton(DemoL10n.text("单人 1:N"), FaceSearchMode.SINGLE_FACE)
              this.SearchModeButton(DemoL10n.text("多人 M:N"), FaceSearchMode.MULTI_FACE)
            }.width('100%')
            Text(this.draftSearchMode === FaceSearchMode.SINGLE_FACE ?
              DemoL10n.text("识别最大的人脸；默认开启静默活体。") : DemoL10n.text("搜索多人，不检测头姿与活体。"))
              .fontSize(12).fontColor(DemoTheme.textOnDarkSecondary).width('100%')
            Row() {
              Text(DemoL10n.text("活体检测")).fontSize(14).fontColor('#FFFFFF').layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.draftSearchLiveness })
                .enabled(this.draftSearchMode === FaceSearchMode.SINGLE_FACE).selectedColor(DemoTheme.searchAccent)
                .onChange((value: boolean) => { this.draftSearchLiveness = value; })
            }.width('100%').height(48)
              .opacity(this.draftSearchMode === FaceSearchMode.SINGLE_FACE ? 1 : 0.45)
            Text(this.draftSearchMode === FaceSearchMode.SINGLE_FACE ?
              DemoL10n.text("1:N 默认开启，可手动关闭。") : DemoL10n.text("活体检测仅适用于 1:N 模式。"))
              .fontSize(12).fontColor(DemoTheme.textOnDarkSecondary).width('100%')
            if (this.draftSearchMode === FaceSearchMode.MULTI_FACE) {
              this.SearchField(DemoL10n.text("每次最多处理人数"), this.draftMaxFacesText, DemoL10n.text("1–5 人，默认 3 人。"),
                (value: string): void => { this.draftMaxFacesText = value; })
            }
            this.SectionTitle(DemoL10n.text("搜索范围"))
            Text(DemoL10n.text("指定分组；留空搜索全部。")).fontSize(12)
              .fontColor(DemoTheme.textOnDarkSecondary).width('100%')
            TextInput({ text: this.draftSearchGroup, placeholder: DemoL10n.text("例如 1A") })
              .height(52).fontSize(14).fontColor('#FFFFFF').backgroundColor('#243247').borderRadius(12)
              .border({ width: 1, color: DemoTheme.searchBorder }).caretColor(DemoTheme.searchAccent)
              .placeholderColor(DemoTheme.textOnDarkSecondary)
              .enterKeyType(EnterKeyType.Done).onSubmit(() => this.dismissKeyboard())
              .onChange((value: string) => { this.draftSearchGroup = value; })
            this.SectionTitle(DemoL10n.text("识别参数"))
            this.SearchField(DemoL10n.text("相似度阈值"), this.draftThresholdText,
              DemoL10n.text("0.75–0.85，数值越高，匹配要求越严格。"),
              (value: string): void => { this.draftThresholdText = value; }, InputType.NUMBER_DECIMAL)
            Button(this.searchAdvancedVisible ? DemoL10n.text("收起高级参数") : DemoL10n.text("更多参数：间隔与超时")).height(48).fontSize(12)
              .fontColor(DemoTheme.searchAccent).backgroundColor(Color.Transparent)
              .onClick(() => { this.searchAdvancedVisible = !this.searchAdvancedVisible; })
            if (this.searchAdvancedVisible) {
              this.SearchField(DemoL10n.text("成功后的间隔"), this.draftIntervalText,
                DemoL10n.text("0–3000 毫秒，默认 0；匹配成功后等待，不控制帧率。"),
                (value: string): void => { this.draftIntervalText = value; })
              this.SearchField(DemoL10n.text("每轮搜索超时"), this.draftTimeoutText, DemoL10n.text("1000–3000 毫秒；超时后开始下一轮。"),
                (value: string): void => { this.draftTimeoutText = value; })
            }
            if (this.searchSettingsError.length > 0) {
              Text(this.searchSettingsError).fontSize(12).fontColor(DemoTheme.searchError).width('100%')
            }
          }.width('100%').padding({ left: 16, right: 16, bottom: 4 })
        }.constraintSize({ maxHeight: Math.max(64, this.viewportHeight - 156) })
          .width('100%').scrollBar(BarState.Auto)
        Row({ space: 8 }) {
          Button(DemoL10n.text("重置")).height(48).fontSize(14).fontColor(DemoTheme.searchAccent).backgroundColor(Color.Transparent)
            .onClick(() => this.resetSearchSettingsDraft())
          Blank()
          Button(DemoL10n.text("取消")).height(48).fontSize(14).fontColor('#FFFFFF').backgroundColor(Color.Transparent)
            .onClick(() => { this.dismissKeyboard(); this.onCancel(); })
          Button(DemoL10n.text("应用")).height(48).fontSize(14).fontColor(DemoTheme.searchBackground).backgroundColor(DemoTheme.searchAccent)
            .onClick(() => this.commitSearchSettingsDraft())
        }.width('100%').padding({ left: 16, right: 16, bottom: 16 })
      }.width('94%').constraintSize({ maxWidth: 560 })
        .backgroundColor(DemoTheme.searchSurface).borderRadius(24).clip(true)
    }.width('100%').height('100%')
  }

  @Builder
  private SearchModeButton(title: string, mode: FaceSearchMode) {
    Button(title).height(48).layoutWeight(1).fontSize(13).borderRadius(12)
      .border({ width: 1, color: DemoTheme.searchBorder })
      .fontColor(this.draftSearchMode === mode ? DemoTheme.searchBackground : '#FFFFFF')
      .backgroundColor(this.draftSearchMode === mode ? DemoTheme.searchAccent : '#243247')
      .onClick(() => {
        if (this.draftSearchMode !== mode) {
          this.draftSearchMode = mode;
          this.draftSearchLiveness = mode === FaceSearchMode.SINGLE_FACE;
        }
      })
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
      .padding({ top: 6 }).width('100%')
  }

  @Builder
  private SearchField(label: string, value: string, hint: string, change: (value: string) => void,
    inputType: InputType = InputType.Number) {
    Column({ space: 6 }) {
      Text(label).fontSize(14).fontColor('#FFFFFF').width('100%')
      TextInput({ text: value }).height(52).fontSize(14).type(inputType).fontColor('#FFFFFF')
        .backgroundColor('#243247').borderRadius(12).border({ width: 1, color: DemoTheme.searchBorder })
        .caretColor(DemoTheme.searchAccent).enterKeyType(EnterKeyType.Done)
        .onSubmit(() => this.dismissKeyboard()).onChange(change)
      Text(hint).fontSize(12).fontColor(DemoTheme.textOnDarkSecondary).width('100%')
    }.width('100%')
  }

  private resetSearchSettingsDraft(): void {
    this.dismissKeyboard();
    this.setSearchSettingsDraft(createDemoFaceSearchConfig());
  }

  private commitSearchSettingsDraft(): void {
    if (![this.draftThresholdText, this.draftIntervalText, this.draftTimeoutText,
      this.draftMaxFacesText].every((value: string): boolean => /^\d+(\.\d+)?$/.test(value.trim()))) {
      this.searchSettingsError = DemoL10n.text("请输入有效数字");
      return;
    }
    let config: FaceSearchSessionConfig;
    try {
      config = new FaceSearchSessionConfig(this.draftSearchMode === FaceSearchMode.SINGLE_FACE ?
        FaceSearchMode.SINGLE_FACE : FaceSearchMode.MULTI_FACE,
        this.draftSearchGroup.trim(), this.draftSearchTag.trim(),
        this.draftSearchMode === FaceSearchMode.SINGLE_FACE && this.draftSearchLiveness,
        Number(this.draftThresholdText), Number(this.draftIntervalText),
        Number(this.draftTimeoutText), Number(this.draftMaxFacesText));
    } catch (error) {
      this.searchSettingsError = DemoL10n.text("搜索配置无效：{0}", [String(error)]);
      return;
    }
    this.dismissKeyboard();
    this.onApply(config);
  }

  private dismissKeyboard(): void {
    this.getUIContext().getFocusController().clearFocus();
  }

  private setSearchSettingsDraft(config: FaceSearchSessionConfig): void {
    this.draftSearchMode = config.mode;
    this.draftSearchGroup = config.group;
    this.draftSearchTag = config.tag;
    this.draftSearchLiveness = config.needsLiveness;
    this.draftThresholdText = (Math.round(config.threshold * 100) / 100).toFixed(2);
    this.draftIntervalText = `${config.searchIntervalMillis}`;
    this.draftTimeoutText = `${config.searchTimeoutMillis}`;
    this.draftMaxFacesText = `${config.maxFacesPerFrame}`;
    this.searchSettingsError = '';
  }
}
