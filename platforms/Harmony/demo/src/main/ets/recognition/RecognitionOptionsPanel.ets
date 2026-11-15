import { DemoL10n } from '../ui/DemoL10n';
import { DemoTheme } from '../ui/DemoTheme';

@Component
export struct RecognitionOptionsPanel {
  @Link silent: boolean;
  @Link actionsEnabled: boolean;
  @Link actionMask: number;
  standalone: boolean = false;
  private readonly titles: string[] = ['眨眼', '张嘴', '摇头', '点头'];

  build() {
    Column({ space: 10 }) {
      if (!this.standalone) {
        Row({ space: 12 }) {
          Column({ space: 3 }) {
            Text(DemoL10n.text('静默活体')).fontSize(15).fontWeight(FontWeight.Medium).fontColor(DemoTheme.contentText)
            Text(DemoL10n.text('检测是否为真人，无需指定动作')).fontSize(12).fontColor(DemoTheme.contentSecondary)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.silent }).selectedColor(DemoTheme.contentAccent)
            .onChange((checked: boolean): void => { this.silent = checked; })
            .accessibilityText(DemoL10n.text('静默活体'))
        }.width('100%')
      }
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text(DemoL10n.text('动作活体')).fontSize(15).fontWeight(FontWeight.Medium).fontColor(DemoTheme.contentText)
          Text(DemoL10n.text('勾选需要完成的动作')).fontSize(12).fontColor(DemoTheme.contentSecondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.actionsEnabled }).selectedColor(DemoTheme.contentAccent)
          .onChange((checked: boolean): void => { this.actionsEnabled = checked; })
          .accessibilityText(DemoL10n.text('动作活体'))
      }.width('100%')
      if (this.actionsEnabled) {
        Text(DemoL10n.text(this.actionMask === 0 ? '请至少勾选一个动作' : '至少选择一个动作，按下方顺序执行'))
          .fontSize(12).fontColor(this.actionMask === 0 ? DemoTheme.contentError : DemoTheme.contentSecondary).width('100%')
        Row({ space: 2 }) {
          ForEach(this.titles, (title: string, index: number) => {
            Row({ space: 2 }) {
              Checkbox().select((this.actionMask & (1 << index)) !== 0).selectedColor(DemoTheme.contentAccent)
                .width(22).height(22)
                .onChange((checked: boolean): void => {
                  this.actionMask = checked ? this.actionMask | (1 << index) : this.actionMask & ~(1 << index);
                }).accessibilityText(DemoL10n.text(title))
              Text(DemoL10n.text(title)).fontSize(11).fontColor(DemoTheme.contentText).maxLines(1)
            }.layoutWeight(1).height(40)
          }, (title: string): string => title)
        }.width('100%')
      }
      Text(DemoL10n.text(this.actionsEnabled ? '按勾选顺序完成动作，再正对镜头完成检测。' : this.standalone || this.silent ?
        '正对镜头即可，无需做指定动作。' : '仅进行 1:1 人脸比对，不进行活体检测。'))
        .fontSize(12).fontColor(DemoTheme.contentAccent).width('100%').padding(10)
        .backgroundColor('#EFF7F3').borderRadius(10)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
