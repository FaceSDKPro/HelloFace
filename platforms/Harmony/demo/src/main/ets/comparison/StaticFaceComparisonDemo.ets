import { DemoL10n } from '../ui/DemoL10n';
import { DemoTheme } from '../ui/DemoTheme';
import { DemoPageHeader } from '../ui/DemoPageHeader';
import { image } from '@kit.ImageKit';
import {
  FaceCaptureResult,
  HiFaceResult,
  HiFaceSdk
} from 'hiface';
import { PixelMapResource } from '../ui/PixelMapResource';
import { DemoErrorUi } from '../ui/DemoErrorUi';
import { FacePhotoPicker } from './FacePhotoPicker';

/** Android 双槽位对比页的 ArkTS 对应实现：每张图片只提取一次特征，再同步比较 HF1。 */
@Component
export struct StaticFaceComparisonDemo {
  @Require
  // 共享 SDK 实例不能用 @Prop 深拷贝。
  sdk: HiFaceSdk;
  onExit: () => void = () => {};
  @State private leftPreview: image.PixelMap | undefined = undefined;
  @State private rightPreview: image.PixelMap | undefined = undefined;
  @State private leftStatus: string = '';
  @State private rightStatus: string = '';
  @State private leftProcessing: boolean = false;
  @State private rightProcessing: boolean = false;
  // ArkUI 只观察就绪状态；实际人脸特征保留为非响应式私有字段。
  @State private leftReady: boolean = false;
  @State private rightReady: boolean = false;
  @State private leftFailed: boolean = false;
  @State private rightFailed: boolean = false;
  @State private pickerOpen: boolean = false;
  @State private comparisonText: string = '';
  @State private comparisonFailed: boolean = false;
  private leftFeature: string | undefined = undefined;
  private rightFeature: string | undefined = undefined;
  private leftGeneration: number = 0;
  private rightGeneration: number = 0;
  private lifecycleGeneration: number = 0;
  private visible: boolean = false;

  aboutToAppear(): void {
    this.visible = true;
    this.lifecycleGeneration += 1;
    this.pickerOpen = false;
    this.leftProcessing = false;
    this.rightProcessing = false;
    this.leftFeature = undefined;
    this.rightFeature = undefined;
    this.leftReady = false;
    this.rightReady = false;
    this.leftStatus = '';
    this.rightStatus = '';
    this.leftFailed = false;
    this.rightFailed = false;
    this.clearComparison();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.lifecycleGeneration += 1;
    this.leftGeneration += 1;
    this.rightGeneration += 1;
    this.releasePreview(0);
    this.releasePreview(1);
    this.leftFeature = undefined;
    this.rightFeature = undefined;
    this.leftReady = false;
    this.rightReady = false;
  }

  build() {
    Column() {
      DemoPageHeader({ title: DemoL10n.text("静态人脸 1:1 对比"), titleSize: 17, onBack: (): void => this.onExit() })

      Scroll() {
        Column({ space: 20 }) {
          Text(DemoL10n.text("选择清晰正脸照片，多人时自动选取最大人脸"))
            .fontSize(13)
            .lineHeight(20)
            .fontColor(DemoTheme.contentSecondary)
            .width('100%')

          Row({ space: 16 }) {
            this.PhotoSlot(0)
            this.PhotoSlot(1)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')

          if (this.comparisonText.length > 0) {
            Text(this.comparisonText)
              .fontSize(this.comparisonFailed ? 14 : 22)
              .fontWeight(this.comparisonFailed ? FontWeight.Regular : FontWeight.Bold)
              .fontColor(this.comparisonFailed ? DemoTheme.contentError : DemoTheme.contentAccent)
              .textAlign(TextAlign.Center)
              .padding(18)
              .width('100%')
          }
        }
        .padding({ left: 24, right: 24, top: 20, bottom: 16 })
        .constraintSize({ maxWidth: 640 })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)

      Button(DemoL10n.text("开始比对"))
        .enabled(this.canCompare())
        .width('calc(100% - 48vp)')
        .constraintSize({ maxWidth: 592 })
        .height(56)
        .borderRadius(12)
        .fontColor('#FFFFFF')
        .fontSize(17)
        .backgroundColor(DemoTheme.contentAccent)
        .margin({ left: 24, right: 24, top: 12, bottom: 25 })
        .onClick(() => this.compareFaces())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DemoTheme.contentBackground)
  }

  @Builder
  private PhotoSlot(slot: number) {
    Column({ space: 9 }) {
      Text(slot === 0 ? DemoL10n.text("照片 1") : DemoL10n.text("照片 2"))
        .fontSize(15)
        .fontColor(DemoTheme.contentText)
        .fontWeight(FontWeight.Medium)
      Stack() {
        if (slot === 0 && this.leftPreview !== undefined) {
          Image(this.leftPreview)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else if (slot === 1 && this.rightPreview !== undefined) {
          Image(this.rightPreview)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column({ space: 6 }) {
            Image($r('app.media.ic_compare_photo'))
              .width(32).height(32).fillColor(DemoTheme.contentAccent)
            Text(DemoL10n.text("选择照片"))
              .fontSize(12)
              .fontColor(DemoTheme.contentSecondary)
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .height('100%')
        }
        if (slot === 0 ? this.leftProcessing : this.rightProcessing) {
          Text(DemoL10n.text("正在处理…"))
            .fontSize(13)
            .fontColor('#FFFFFF')
            .padding(10)
            .backgroundColor('#BB242029')
            .borderRadius(10)
        }
      }
      .width('100%')
      .aspectRatio(1)
      .backgroundColor(DemoTheme.surfaceMuted)
      .borderRadius(16)
      .clip(true)
      .onClick(() => this.pickPhoto(slot))
      Text(slot === 0 ? this.leftStatus : this.rightStatus)
        .fontSize(12)
        .fontColor((slot === 0 ? this.leftFailed : this.rightFailed) ? DemoTheme.contentError :
          !(slot === 0 ? this.leftReady : this.rightReady) ? DemoTheme.contentSecondary : DemoTheme.contentAccent)
        .maxLines(2)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
  }

  private async pickPhoto(slot: number): Promise<void> {
    // 两个槽位可分别选择和排队处理；同一槽位处理期间避免重复堆积无意义请求。
    if (this.pickerOpen || (slot === 0 ? this.leftProcessing : this.rightProcessing)) {
      return;
    }
    this.pickerOpen = true;
    const lifecycle: number = this.lifecycleGeneration;
    let input: FacePhotoPicker | undefined = undefined;
    try {
      input = await FacePhotoPicker.select();
    } catch (error) {
      if (this.visible && lifecycle === this.lifecycleGeneration) {
        this.setPickerError(slot, DemoL10n.text("图片读取失败，请重新选择"));
      }
    } finally {
      if (lifecycle === this.lifecycleGeneration) {
        this.pickerOpen = false;
      }
    }
    if (input === undefined || !this.visible || lifecycle !== this.lifecycleGeneration) {
      return;
    }
    const generation: number = this.beginSlotProcessing(slot);
    try {
      // 与 Android 一致先显示新选原图；成功后再替换为 333×333 对齐脸，失败时保留所选图片。
      const selectedPreview: image.PixelMap | undefined = await PixelMapResource.createRgba(
        input.rgba.data, input.rgba.width, input.rgba.height);
      if (!this.isCurrent(slot, generation, lifecycle)) {
        await PixelMapResource.release(selectedPreview);
        return;
      }
      if (selectedPreview !== undefined) {
        await this.replacePreview(slot, selectedPreview);
      } else {
        await this.releasePreview(slot);
      }
      if (!this.isCurrent(slot, generation, lifecycle)) return;
      const result: HiFaceResult<FaceCaptureResult> = await this.sdk.capture().fromRgba(input.rgba);
      if (!this.isCurrent(slot, generation, lifecycle)) {
        return;
      }
      if (result.isFailure()) {
        this.setSlotError(slot, DemoErrorUi.describe(result.requireError()));
        return;
      }
      const capture: FaceCaptureResult = result.requireValue();
      this.setSlotFeature(slot, capture.feature);
      if (capture.alignedRgba !== undefined) {
        const preview: image.PixelMap | undefined = await PixelMapResource.createRgba(
          capture.alignedRgba, capture.alignedSide, capture.alignedSide);
        if (!this.isCurrent(slot, generation, lifecycle)) {
          await PixelMapResource.release(preview);
          return;
        }
        if (preview !== undefined) {
          await this.replacePreview(slot, preview);
        }
      }
    } catch (error) {
      if (this.isCurrent(slot, generation, lifecycle)) {
        this.setSlotError(slot, DemoL10n.text("人脸提取失败，请重试"));
      }
    } finally {
      if (this.isCurrent(slot, generation, lifecycle)) {
        this.setSlotProcessing(slot, false);
      }
    }
  }

  private beginSlotProcessing(slot: number): number {
    this.clearComparison();
    if (slot === 0) {
      this.leftGeneration += 1;
      this.leftFeature = undefined;
      this.leftReady = false;
      this.leftStatus = '';
      this.leftProcessing = true;
      this.leftFailed = false;
      return this.leftGeneration;
    }
    this.rightGeneration += 1;
    this.rightFeature = undefined;
    this.rightReady = false;
    this.rightStatus = '';
    this.rightProcessing = true;
    this.rightFailed = false;
    return this.rightGeneration;
  }

  private setSlotFeature(slot: number, feature: string): void {
    if (slot === 0) {
      this.leftFeature = feature;
      this.leftReady = true;
      this.leftStatus = DemoL10n.text("已就绪 · 点击更换");
      this.leftFailed = false;
    } else {
      this.rightFeature = feature;
      this.rightReady = true;
      this.rightStatus = DemoL10n.text("已就绪 · 点击更换");
      this.rightFailed = false;
    }
  }

  private setSlotError(slot: number, message: string): void {
    if (slot === 0) {
      this.leftFeature = undefined;
      this.leftReady = false;
      this.leftProcessing = false;
      this.leftStatus = message;
      this.leftFailed = true;
    } else {
      this.rightFeature = undefined;
      this.rightReady = false;
      this.rightProcessing = false;
      this.rightStatus = message;
      this.rightFailed = true;
    }
    this.clearComparison();
  }

  /** 读取新照片失败时保留槽位原有图片和特征，只更新对应错误提示。 */
  private setPickerError(slot: number, message: string): void {
    if (slot === 0) {
      this.leftStatus = message;
      this.leftFailed = true;
    } else {
      this.rightStatus = message;
      this.rightFailed = true;
    }
  }

  private setSlotProcessing(slot: number, processing: boolean): void {
    if (slot === 0) {
      this.leftProcessing = processing;
    } else {
      this.rightProcessing = processing;
    }
  }

  private compareFaces(): void {
    const left: string | undefined = this.leftFeature;
    const right: string | undefined = this.rightFeature;
    if (left === undefined || right === undefined) {
      return;
    }
    const result: HiFaceResult<number> = this.sdk.verification().compare(left, right);
    if (result.isFailure()) {
      this.comparisonFailed = true;
      this.comparisonText = DemoErrorUi.describe(result.requireError());
      return;
    }
    const similarity: number = result.requireValue();
    this.comparisonFailed = false;
    this.comparisonText = DemoL10n.text("相似度 {0}%", [String((similarity * 100).toFixed(2))]);
  }

  private canCompare(): boolean {
    return this.leftReady && this.rightReady &&
      !this.leftProcessing && !this.rightProcessing;
  }

  private clearComparison(): void {
    this.comparisonFailed = false;
    this.comparisonText = '';
  }

  private isCurrent(slot: number, generation: number, lifecycle: number): boolean {
    return this.visible && lifecycle === this.lifecycleGeneration &&
      generation === (slot === 0 ? this.leftGeneration : this.rightGeneration);
  }

  private async replacePreview(slot: number, preview: image.PixelMap): Promise<void> {
    const previous: image.PixelMap | undefined = slot === 0 ? this.leftPreview : this.rightPreview;
    if (slot === 0) {
      this.leftPreview = preview;
    } else {
      this.rightPreview = preview;
    }
    await PixelMapResource.release(previous);
  }

  private async releasePreview(slot: number): Promise<void> {
    const preview: image.PixelMap | undefined = slot === 0 ? this.leftPreview : this.rightPreview;
    if (slot === 0) {
      this.leftPreview = undefined;
    } else {
      this.rightPreview = undefined;
    }
    await PixelMapResource.release(preview);
  }
}
