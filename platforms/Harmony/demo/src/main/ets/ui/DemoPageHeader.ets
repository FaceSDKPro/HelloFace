import { DemoTheme } from './DemoTheme';

/** 浅色内容页的统一返回栏；布局与 Android NavigationButton.OnLight 对齐。 */
@Component
export struct DemoPageHeader {
  @Prop title: string = '';
  @Prop titleSize: number = 20;
  onBack: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_navigation_back')).width(24).height(24).fillColor(DemoTheme.contentText)
      }.width(48).height(48).backgroundColor(Color.Transparent)
        .accessibilityText('返回').onClick(() => this.onBack())
      Text(this.title).fontSize(this.titleSize).fontWeight(FontWeight.Bold)
        .fontColor(DemoTheme.contentText).layoutWeight(1)
    }.width('100%').constraintSize({ minHeight: 60 })
      .padding({ left: 10, right: 12 })
      .backgroundColor(DemoTheme.contentBackground)
  }
}
