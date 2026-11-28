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
    Column({ space: 11 }) {
      Row({ space: 12 }) {
        Column({ space: 3.3 }) {
          Text(DemoL10n.text('静默活体')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(DemoTheme.contentText)
          Text(DemoL10n.text(this.standalone ?
            '始终开启，无需指定动作即可检测是否为真人。' : '检测是否为真人，无需指定动作'))
            .fontSize(12).fontColor(DemoTheme.contentSecondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (!this.standalone) {
          Toggle({ type: ToggleType.Switch, isOn: this.silent }).selectedColor(DemoTheme.contentAccent)
            .onChange((checked: boolean): void => { this.silent = checked; })
            .accessibilityText(DemoL10n.text('静默活体'))
        }
      }.width('100%')
      Row({ space: 12 }) {
        Column({ space: 3.3 }) {
          Text(DemoL10n.text('动作活体')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(DemoTheme.contentText)
          Text(DemoL10n.text('勾选需要完成的动作')).fontSize(12).fontColor(DemoTheme.contentSecondary)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.actionsEnabled }).selectedColor(DemoTheme.contentAccent)
          .onChange((checked: boolean): void => { this.actionsEnabled = checked; })
          .accessibilityText(DemoL10n.text('动作活体'))
      }.width('100%')
      if (this.actionsEnabled) {
        if (this.actionMask === 0) {
          Text(DemoL10n.text('请至少勾选一个动作')).fontSize(12).fontColor(DemoTheme.contentError).width('100%')
        }
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
      } else {
        Text(DemoL10n.text(this.standalone || this.silent ?
          '正对镜头即可，无需做指定动作。' : '仅进行 1:1 人脸比对，不进行活体检测。'))
          .fontSize(12).fontColor(DemoTheme.contentSecondary).width('100%').padding(10)
          .backgroundColor('#EFF7F3').borderRadius(10)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
