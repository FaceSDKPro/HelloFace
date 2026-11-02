import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { FaceImageCapture, FaceSearchConfig, FaceSearchDatabase, FaceSearchMatch,
  HiFaceErrorCode, HiFaceResult, HiFaceSdk, RgbaImage } from 'hiface';
import { FacePhotoPicker } from '../comparison/FacePhotoPicker';
import { DemoL10n } from '../ui/DemoL10n';
import { DemoPageHeader } from '../ui/DemoPageHeader';
import { DemoTheme } from '../ui/DemoTheme';
import { DemoErrorUi } from '../ui/DemoErrorUi';
import { PixelMapResource } from '../ui/PixelMapResource';

class ImageSearchFace {
  readonly index: number;
  readonly face: FaceImageCapture;
  // ID、分数只格式化一次，照片与缩略图直接复用。
  readonly label: string;
  readonly matched: boolean;
  readonly crop: image.PixelMap | undefined;
  constructor(index: number, face: FaceImageCapture, label: string, matched: boolean,
    crop: image.PixelMap | undefined) {
    this.index = index; this.face = face; this.label = label;
    this.matched = matched; this.crop = crop;
  }
}

/** SDK 负责多脸采集和特征搜索；页面只持有原图、缩略图及展示标签。 */
@Component
export struct FaceImageSearchDemo {
  @Require sdk: HiFaceSdk;
  onExit: () => void = () => {};
  onOpenLibrary: () => void = () => {};
  @State private preview: image.PixelMap | undefined = undefined;
  @State private faces: ImageSearchFace[] = [];
  @State private status: string = DemoL10n.text("选择一张包含人脸的图片");
  @State private processing: boolean = false;
  @State private pickerOpen: boolean = false;
  private visible: boolean = false;
  // 页面退出或换图后，旧异步结果不再更新 UI；旧任务创建的 PixelMap 由 finally 释放。
  private generation: number = 0;
  private imageWidth: number = 0;
  private imageHeight: number = 0;
  @State private selected: number = -1;
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToAppear(): void { this.visible = true; }
  aboutToDisappear(): void {
    this.visible = false; this.generation += 1;
    this.releaseImages();
  }

  build() {
    Column({ space: 12 }) {
      DemoPageHeader({ title: DemoL10n.text("图片人脸搜索识别"), titleSize: 17,
        onBack: (): void => this.onExit(), actionTitle: DemoL10n.text("人脸库"),
        onAction: (): void => this.onOpenLibrary() })
      Text(DemoL10n.text("最多检测 10 张脸 · 匹配阈值 0.80 · 不检测活体"))
        .fontSize(12).fontColor(DemoTheme.contentSecondary).width('calc(100% - 40vp)')
      Stack() {
        if (this.preview !== undefined) {
          Image(this.preview).width('100%').height('100%').objectFit(ImageFit.Contain)
        } else {
          Column({ space: 12 }) {
            Image($r('app.media.ic_compare_photo')).width(40).height(40)
            Text(DemoL10n.text("选择照片")).fontSize(14).fontColor(DemoTheme.contentSecondary)
          }
        }
        Canvas(this.context).width('100%').height('100%')
          .onReady(() => this.draw())
          .onAreaChange((_old: Area, area: Area) => {
            this.canvasWidth = Number(area.width); this.canvasHeight = Number(area.height); this.draw();
          })
        if (this.processing) {
          LoadingProgress().width(40).height(40).color(DemoTheme.contentAccent)
        }
      }.layoutWeight(1).width('calc(100% - 40vp)').backgroundColor('#FFFFFF').borderRadius(18).border({ width: 1, color: '#E1E7E4' }).clip(true)
      if (this.faces.length > 0) {
        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.faces, (result: ImageSearchFace) => {
              Column({ space: 6 }) {
                if (result.crop !== undefined) {
                  Image(result.crop).width(72).height(72).objectFit(ImageFit.Contain).borderRadius(10)
                } else {
                  Text('—').fontSize(28).fontColor(DemoTheme.contentSecondary).width(72).height(72).textAlign(TextAlign.Center)
                }
                Text(result.label).fontSize(11).maxLines(2).height(32).textAlign(TextAlign.Center)
                  .fontColor(DemoTheme.contentText).width(96)
              }.padding(8).borderRadius(14).backgroundColor('#FFFFFF')
                .border({ width: 1, color: this.selected === result.index ? DemoTheme.contentAccent : '#E1E7E4' })
                .onClick(() => { this.selected = result.index; this.draw(); })
            }, (result: ImageSearchFace): string => `${result.index}`)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).height(128)
          .width('calc(100% - 40vp)')
      }
      Text(this.status).fontSize(13).textAlign(TextAlign.Center).fontColor(DemoTheme.contentText)
        .padding({ left: 20, right: 20 })
      Button(DemoL10n.text("相册添加")).width('calc(100% - 40vp)').height(56).borderRadius(16)
        .backgroundColor(DemoTheme.contentAccent).fontColor('#FFFFFF')
        .enabled(!this.pickerOpen).margin({ bottom: 16 }).onClick(() => this.pick())
    }.width('100%').height('100%').backgroundColor(DemoTheme.contentBackground)
  }

  private async pick(): Promise<void> {
    if (this.pickerOpen) return;
    this.pickerOpen = true;
    let picked: FacePhotoPicker | undefined = undefined;
    try { picked = await FacePhotoPicker.select(FacePhotoPicker.IMAGE_SEARCH_MAX_SIDE); }
    catch (_) { if (this.visible) this.status = DemoL10n.text("图片读取失败，请重新选择"); }
    finally { this.pickerOpen = false; }
    if (!this.visible || picked === undefined) return;
    await this.load(picked.rgba);
  }

  private async load(input: RgbaImage): Promise<void> {
    const token: number = ++this.generation;
    const preview: image.PixelMap | undefined = await PixelMapResource.createRgba(input.data, input.width, input.height);
    if (!this.current(token)) { await PixelMapResource.release(preview); return; }
    this.releaseImages();
    this.preview = preview; this.imageWidth = input.width; this.imageHeight = input.height;
    this.selected = -1; this.draw();
    this.processing = true;
    this.status = DemoL10n.text("正在检测、矫正并搜索…");
    let database: FaceSearchDatabase | undefined = undefined;
    const results: ImageSearchFace[] = [];
    // 成功时把缩略图交给页面；旧任务或异常退出由 finally 释放临时结果。
    let committed: boolean = false;
    try {
      const extracted: HiFaceResult<FaceImageCapture[]> = await this.sdk.capture().facesFromRgba(input);
      if (!this.current(token)) return;
      if (extracted.isFailure()) { this.status = DemoErrorUi.describe(extracted.requireError()); return; }
      const faces: FaceImageCapture[] = extracted.requireValue();
      if (faces.length === 0) { this.status = DemoL10n.text("未检测到人脸，请更换清晰图片"); return; }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const opened: HiFaceResult<FaceSearchDatabase> = await HiFaceSdk.openSearchDatabase(context);
      if (opened.isFailure()) { if (this.current(token)) this.status = DemoErrorUi.describe(opened.requireError()); return; }
      database = opened.requireValue();
      if (!this.current(token)) return;
      const counted: HiFaceResult<number> = await database.count();
      if (!this.current(token)) return;
      if (counted.isFailure()) { this.status = DemoErrorUi.describe(counted.requireError()); return; }
      for (let i: number = 0; i < faces.length; i++) {
        if (!this.current(token)) return;
        const face: FaceImageCapture = faces[i];
        let crop: image.PixelMap | undefined = undefined;
        let matched: boolean = false;
        let label: string = DemoL10n.text("未匹配");
        if (face.capture.isFailure()) {
          const error = face.capture.requireError();
          label = error.code === HiFaceErrorCode.IMAGE_FACE_TOO_SMALL ?
            DemoL10n.text("人脸太小") : DemoErrorUi.describe(error);
        }
        else {
          const capture = face.capture.requireValue();
          const found: HiFaceResult<ReadonlyArray<FaceSearchMatch>> = await database.search(
            capture.feature, FaceSearchConfig.defaultConfig());
          if (!this.current(token)) return;
          if (found.isFailure()) label = DemoErrorUi.describe(found.requireError());
          else if (found.requireValue().length > 0) {
            const match: FaceSearchMatch = found.requireValue()[0];
            matched = true; label = `${match.entry.faceId},${match.score.toFixed(2)}`;
          }
          // 查询完成后才创建缩略图，随后立即交给 results，避免异常时留下无人持有的 PixelMap。
          if (capture.alignedRgba !== undefined) crop = await PixelMapResource.createRgba(
            capture.alignedRgba, capture.alignedSide, capture.alignedSide);
        }
        results.push(new ImageSearchFace(i, face, label, matched, crop));
      }
      if (!this.current(token)) return;
      this.faces = results; committed = true;
      this.status = DemoL10n.text("检测到 {0} 个人脸，搜索匹配成功 {1} 个",
        [`${results.length}`, `${results.filter((face: ImageSearchFace): boolean => face.matched).length}`]);
      if (counted.requireValue() === 0) this.status += '\n' + DemoL10n.text("人脸库为空，请先到人脸库录入");
      this.draw();
    } catch (_) {
      if (this.current(token)) this.status = DemoL10n.text("人脸处理未能完成，请重试");
    } finally {
      database?.close();
      if (!committed) results.forEach((result: ImageSearchFace) => { PixelMapResource.release(result.crop); });
      if (this.current(token)) this.processing = false;
    }
  }

  private current(token: number): boolean { return this.visible && token === this.generation; }
  private releaseImages(): void {
    PixelMapResource.release(this.preview); this.preview = undefined;
    this.faces.forEach((face: ImageSearchFace) => { PixelMapResource.release(face.crop); }); this.faces = [];
  }
  private draw(): void {
    const c = this.context;
    c.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    if (this.imageWidth === 0 || this.imageHeight === 0) return;
    const scale: number = Math.min(this.canvasWidth / this.imageWidth, this.canvasHeight / this.imageHeight);
    const dx: number = (this.canvasWidth - this.imageWidth * scale) / 2;
    const dy: number = (this.canvasHeight - this.imageHeight * scale) / 2;
    // 与原图 ImageFit.Contain 共用同一缩放/留白偏移；标签固定 10vp。
    c.font = '10vp sans-serif';
    this.faces.forEach((result: ImageSearchFace) => {
      const f: FaceImageCapture = result.face;
      const x: number = dx + f.x * scale; const y: number = dy + f.y * scale;
      c.strokeStyle = result.matched ? '#20B946' : '#CF7E14';
      c.lineWidth = this.selected === result.index ? 4 : 2;
      c.strokeRect(x, y, f.width * scale, f.height * scale);
      let label: string = result.label;
      const maxLabelWidth: number = Math.min(this.canvasWidth - 12, Math.max(f.width * scale, 96));
      while (c.measureText(label).width > maxLabelWidth && label.length > 2)
        label = label.substring(0, label.length - 2) + '…';
      const w: number = c.measureText(label).width + 8;
      const lx: number = Math.max(0, Math.min(x, this.canvasWidth - w));
      const ly: number = Math.max(16, y);
      c.fillStyle = '#CC111111'; c.fillRect(lx, ly - 16, w, 16);
      c.fillStyle = '#FFFFFF'; c.fillText(label, lx + 4, ly - 4);
    });
  }
}
