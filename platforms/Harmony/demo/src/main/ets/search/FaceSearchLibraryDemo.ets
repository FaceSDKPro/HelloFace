import { DemoL10n } from '../ui/DemoL10n';
import { common } from '@kit.AbilityKit';
import {
  FaceSearchDatabase,
  FaceSearchEntry,
  FaceSearchMetadata,
  HiFaceError,
  HiFaceErrorCode,
  HiFaceResult,
  HiFaceSdk
} from 'hiface';
import { DemoTheme } from '../ui/DemoTheme';
import { DemoErrorUi } from '../ui/DemoErrorUi';
import { CameraPageLifecycle } from '../camera/CameraPageLifecycle';
import {
  FaceSearchDemoImporter,
  FaceSearchImportProgress,
  FaceSearchImportSummary
} from './FaceSearchDemoImporter';
import { FaceSearchLibraryItem } from './FaceSearchLibraryItem';

const LOAD_SIZE: number = 100;
const PREFETCH_REMAINING: number = 10;

/** 人脸库管理示例：精确查询、滚动加载、删除以及两种批量导入。 */
@Component
export struct FaceSearchLibraryDemo {
  @Require
  // 共享 SDK 实例不能用 @Prop 深拷贝。
  sdk: HiFaceSdk;
  @Require
  cameraLifecycle: CameraPageLifecycle;
  onExit: () => void = () => {};
  @State private entries: FaceSearchLibraryItem[] = [];
  @State private faceId: string = '';
  @State private stateText: string = DemoL10n.text("正在打开人脸库…");
  @State private busy: boolean = false;
  @State private lookupMode: boolean = false;
  @State private failed: boolean = false;
  private database: FaceSearchDatabase | undefined = undefined;
  private lifecycleToken: number = 0;
  private taskToken: number = 0;
  private nextOffset: number = 0;
  private canLoadMore: boolean = false;
  private lifecycleBinding: number | undefined = undefined;
  private active: boolean = false;
  private importer: FaceSearchDemoImporter | undefined = undefined;
  private importTask: Promise<void> | undefined = undefined;
  private importCleanup: Promise<void> = Promise.resolve();
  private exitAfterImport: boolean = false;
  private stoppingImport: boolean = false;
  private exitDialogShowing: boolean = false;
  private importSaved: number = 0;
  private importResultMessage: string | undefined = undefined;

  aboutToAppear(): void {
    this.lifecycleBinding = this.cameraLifecycle.bind(
      (): void => this.stopPage(), (): void => this.startPage(),
      (): boolean => { this.requestExit(); return true; }, (): void => this.stopPage());
    if (this.cameraLifecycle.isActive()) this.startPage();
  }

  aboutToDisappear(): void {
    this.cameraLifecycle.unbind(this.lifecycleBinding);
    this.lifecycleBinding = undefined;
    this.stopPage();
  }

  private startPage(): void {
    if (this.active) return;
    this.active = true;
    const lifecycle: number = ++this.lifecycleToken;
    this.openAndLoad(lifecycle);
  }

  /** 切后台停止新输入，等待当前提取和尾批写库结束，再关闭管理连接。 */
  private stopPage(): void {
    if (!this.active) return;
    this.active = false;
    ++this.lifecycleToken;
    ++this.taskToken;
    this.canLoadMore = false;
    this.busy = false;
    const importer = this.importer;
    const database = this.database;
    this.exitDialogShowing = false;
    this.importResultMessage = undefined;
    if (importer !== undefined) this.stoppingImport = true;
    importer?.requestStop();
    if (importer !== undefined && this.importTask !== undefined) {
      this.importCleanup = this.importTask.then((): void => { database?.close(); });
    } else {
      database?.close();
    }
    this.database = undefined;
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_navigation_back')).width(23).height(23).fillColor('#FFFFFF')
        }
          .width(42).height(42).backgroundColor(Color.Transparent)
          .accessibilityText(DemoL10n.text("返回")).onClick(() => this.requestExit())
        Text(DemoL10n.text("人脸库"))
          .fontSize(21).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Text('⋮').fontSize(27).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        }
          .width(42).height(42).backgroundColor(DemoTheme.surfaceOnDark)
          .enabled(!this.busy)
          .accessibilityText(DemoL10n.text("功能菜单"))
          .bindMenu([
            { value: DemoL10n.text("刷新"), enabled: !this.busy, action: (): void => this.refresh() },
            { value: $r('app.string.search_import_features'), enabled: !this.busy && this.database !== undefined,
              action: (): void => this.confirmImport(false) },
            { value: $r('app.string.search_import_images'), enabled: !this.busy && this.database !== undefined,
              action: (): void => this.confirmImport(true) }
          ])
      }
      .padding({ left: 10, right: 14, top: 4, bottom: 4 })
      .width('100%')

      Row({ space: 4 }) {
        TextInput({ text: this.faceId, placeholder: DemoL10n.text("输入 Face ID 查找") })
          .enabled(!this.busy)
          .layoutWeight(1).height(40).fontSize(14).fontColor('#FFFFFF')
          .placeholderColor(DemoTheme.textOnDarkSecondary)
          .backgroundColor(Color.Transparent)
          .enterKeyType(EnterKeyType.Search)
          .onSubmit(() => this.lookup())
          .onChange((value: string) => this.onFaceIdChange(value))
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_search_search')).width(19).height(19)
            .fillColor(DemoTheme.textOnDarkSecondary)
        }
          .enabled(!this.busy && this.database !== undefined && this.faceId.trim().length > 0)
          .width(38).height(38).backgroundColor(Color.Transparent)
          .accessibilityText(DemoL10n.text("查找")).onClick(() => this.lookup())
      }
      .height(44).padding({ left: 12, right: 4 })
      .margin({ left: 16, right: 16, top: 4, bottom: 4 })
      .backgroundColor(DemoTheme.searchSurface).borderRadius(9)
      .width('100%')

      Text(this.stateText)
        .fontSize(12).fontColor(this.stateColor()).maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .height(34).padding({ left: 17, right: 17 }).width('100%')

      if (this.entries.length === 0) {
        this.EmptyState()
      } else {
        List({ space: 10 }) {
          ForEach(this.entries, (entry: FaceSearchLibraryItem) => {
            ListItem() { this.EntryCard(entry) }
          }, (entry: FaceSearchLibraryItem): string => entry.faceId)
        }
        .layoutWeight(1).width('100%')
        .padding({ left: 16, right: 16, bottom: 14 })
        .edgeEffect(EdgeEffect.Spring)
        .onScrollIndex((_start: number, end: number) => this.loadMoreIfNeeded(end))
      }
    }
    .width('100%').height('100%').backgroundColor(DemoTheme.searchBackground)
  }

  @Builder
  private EmptyState() {
    Column({ space: 8 }) {
      Text(this.failed ? DemoL10n.text("操作失败") :
        this.lookupMode ? DemoL10n.text("未找到该 Face ID") : DemoL10n.text("当前范围内暂无已录入人脸"))
        .fontSize(17).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
      Text(this.failed ? DemoL10n.text("请重试，或在右上角菜单刷新。") :
        this.lookupMode ? DemoL10n.text("请检查 Face ID，或清空输入返回全部记录。") :
          DemoL10n.text("从右上角菜单导入演示数据。"))
        .fontSize(12).lineHeight(18).fontColor('#98A2B3')
        .textAlign(TextAlign.Center).width('100%')
    }
    .justifyContent(FlexAlign.Center).layoutWeight(1)
    .padding({ left: 24, right: 24 }).width('100%')
  }

  @Builder
  private EntryCard(entry: FaceSearchLibraryItem) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(entry.faceId)
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(DemoL10n.text("分组：{0}", [String(entry.group.length === 0 ? DemoL10n.text("未分组") : entry.group)]) +
          (entry.tag.length === 0 ? '' : DemoL10n.text(" · 标签：{0}", [String(entry.tag)])))
          .fontSize(12).fontColor('#98A2B3')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button(DemoL10n.text("删除"))
        .enabled(!this.busy && this.database !== undefined).height(36).fontSize(12).fontColor(DemoTheme.searchError)
        .backgroundColor('#3A2430')
        .accessibilityText(DemoL10n.text("删除人脸 {0}", [String(entry.faceId)]))
        .onClick(() => this.confirmDelete(entry.faceId))
    }
    .padding(13).backgroundColor(DemoTheme.searchSurface)
    .borderRadius(12).width('100%')
  }

  /** 每次进入页面打开独立管理连接；连续搜索使用 SDK 自己的连接。 */
  private async openAndLoad(lifecycle: number): Promise<void> {
    this.busy = true;
    this.failed = false;
    this.stateText = DemoL10n.text("正在打开人脸库…");
    try {
      await this.importCleanup;
      if (!this.active || lifecycle !== this.lifecycleToken) return;
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const opened: HiFaceResult<FaceSearchDatabase> = await HiFaceSdk.openSearchDatabase(context);
      if (lifecycle !== this.lifecycleToken) {
        if (opened.isSuccess()) opened.requireValue().close();
        return;
      }
      if (opened.isFailure()) {
        this.failed = true;
        this.stateText = DemoL10n.text("打开失败：{0}", [String(DemoErrorUi.describe(opened.requireError()))]);
        return;
      }
      this.database = opened.requireValue();
      this.busy = false;
      if (this.faceId.trim().length > 0) this.lookup(); else this.loadFirstPage();
    } catch (error) {
      if (lifecycle === this.lifecycleToken) {
        this.failed = true;
        this.stateText = DemoL10n.text("打开失败：{0}", [String(error)]);
      }
    } finally {
      if (lifecycle === this.lifecycleToken && this.database === undefined) this.busy = false;
    }
  }

  /** 清空旧列表并读取前 100 条。 */
  private loadFirstPage(): void {
    if (this.database === undefined) return;
    const token: number = ++this.taskToken;
    this.lookupMode = false;
    this.failed = false;
    this.nextOffset = 0;
    this.canLoadMore = false;
    this.entries = [];
    this.loadPage(0, token);
  }

  /** 每页重新统计总数并按原始页长推进偏移；按 ID 合并，避免跨连接更新产生重复卡片。 */
  private async loadPage(offset: number, token: number): Promise<void> {
    const database: FaceSearchDatabase | undefined = this.database;
    if (database === undefined || this.busy) return;
    this.busy = true;
    if (offset === 0) this.stateText = DemoL10n.text("正在读取人脸库…");
    try {
      const counted: HiFaceResult<number> = await database.count();
      if (!this.isTaskActive(token)) return;
      if (counted.isFailure()) {
        this.showFailure(DemoL10n.text("计数失败"), counted.requireError(), offset === 0);
        return;
      }
      const total: number = counted.requireValue();
      if (offset >= total) {
        this.canLoadMore = false;
        this.stateText = DemoL10n.text("共 {0} 条人脸记录", [String(total)]);
        return;
      }
      const listed: HiFaceResult<ReadonlyArray<FaceSearchMetadata>> =
        await database.listRecent('', '', offset, LOAD_SIZE);
      if (!this.isTaskActive(token)) return;
      if (listed.isFailure()) {
        this.showFailure(DemoL10n.text("读取失败"), listed.requireError(), offset === 0);
        return;
      }
      const loaded: FaceSearchLibraryItem[] = listed.requireValue().map(
        (entry: FaceSearchMetadata): FaceSearchLibraryItem => new FaceSearchLibraryItem(entry));
      this.nextOffset = offset + loaded.length;
      this.canLoadMore = loaded.length > 0 && this.nextOffset < total;
      this.entries = offset === 0 ? loaded : this.mergeEntries(loaded);
      this.failed = false;
      this.stateText = DemoL10n.text("共 {0} 条人脸记录", [String(total)]);
    } catch (error) {
      if (this.isTaskActive(token)) {
        this.failed = true;
        this.canLoadMore = false;
        if (offset === 0) this.entries = [];
        this.stateText = DemoL10n.text("读取失败：{0}", [String(error)]);
      }
    } finally {
      if (this.isTaskActive(token)) this.busy = false;
    }
  }

  /** 第 90、190、290…条进入可见范围时提前加载下一批。 */
  private loadMoreIfNeeded(lastVisible: number): void {
    if (this.busy || this.lookupMode || this.entries.length === 0 || !this.canLoadMore) return;
    if (lastVisible >= this.entries.length - PREFETCH_REMAINING - 1) {
      const token: number = ++this.taskToken;
      this.loadPage(this.nextOffset, token);
    }
  }

  /** 完整 Face ID 精确查询；NOT_FOUND 是正常空结果。 */
  private async lookup(): Promise<void> {
    const database: FaceSearchDatabase | undefined = this.database;
    const query: string = this.faceId.trim();
    if (database === undefined || this.busy) return;
    if (query.length === 0) {
      this.loadFirstPage();
      return;
    }
    const token: number = ++this.taskToken;
    this.busy = true;
    this.failed = false;
    this.canLoadMore = false;
    this.lookupMode = true;
    this.nextOffset = 0;
    this.stateText = DemoL10n.text("正在查找 {0}…", [String(query)]);
    try {
      const found: HiFaceResult<FaceSearchEntry> = await database.get(query);
      if (!this.isTaskActive(token)) return;
      if (found.isSuccess()) {
        this.entries = [new FaceSearchLibraryItem(found.requireValue())];
        this.stateText = DemoL10n.text("查找结果");
      } else if (found.requireError().code === HiFaceErrorCode.NOT_FOUND) {
        this.entries = [];
        this.stateText = DemoL10n.text("查找结果");
      } else {
        this.showFailure(DemoL10n.text("查找失败"), found.requireError(), true);
      }
    } catch (error) {
      if (this.isTaskActive(token)) {
        this.failed = true;
        this.entries = [];
        this.stateText = DemoL10n.text("查找失败：{0}", [String(error)]);
      }
    } finally {
      if (this.isTaskActive(token)) this.busy = false;
    }
  }

  private onFaceIdChange(value: string): void {
    this.faceId = value;
    if (value.trim().length === 0 && this.lookupMode && !this.busy) this.loadFirstPage();
  }

  private refresh(): void {
    if (this.busy || !this.active) return;
    this.lookupMode = false;
    this.faceId = '';
    if (this.database === undefined) this.openAndLoad(this.lifecycleToken);
    else this.loadFirstPage();
  }

  private confirmImport(images: boolean): void {
    if (this.busy || this.database === undefined) return;
    const lifecycle: number = this.lifecycleToken;
    this.getUIContext().showAlertDialog({
      title: images ? DemoL10n.text("批量导入人脸图片") : DemoL10n.text("批量导入人脸特征"),
      message: images ?
        DemoL10n.text("联网导入 1 千张图片，覆盖同 Face ID 记录；已保存批次保留。") :
        DemoL10n.text("导入 1 万条内置 HF1 特征，覆盖同 Face ID 记录。"),
      primaryButton: { value: DemoL10n.text("开始导入"), action: (): void => {
        if (lifecycle === this.lifecycleToken) this.startImport(images);
      } },
      secondaryButton: { value: DemoL10n.text("取消"), action: (): void => {} }
    });
  }

  /** 页面只负责进度和结果；解析、下载、提取及分批写库由导入器完成。 */
  private startImport(images: boolean): Promise<void> {
    const token: number = this.lifecycleToken;
    const operation: Promise<void> = this.runImport(images).catch((error: Error): void => {
      this.importer = undefined;
      if (!this.active || token !== this.lifecycleToken) return;
      this.busy = false;
      this.stoppingImport = false;
      this.exitAfterImport = false;
      this.failed = true;
      this.stateText = DemoL10n.text("导入未完成，已保存 {0} 条：{1}", [String(this.importSaved), String(error.message)]);
      this.showToast(this.stateText);
    });
    this.importTask = operation;
    operation.then((): void => {
      if (this.importTask === operation) this.importTask = undefined;
    });
    return operation;
  }

  private async runImport(images: boolean): Promise<void> {
    const database: FaceSearchDatabase | undefined = this.database;
    if (database === undefined || this.busy) return;
    const token: number = ++this.taskToken;
    this.busy = true;
    this.failed = false;
    this.canLoadMore = false;
    this.importSaved = 0;
    this.stoppingImport = false;
    this.exitAfterImport = false;
    this.importResultMessage = undefined;
    const total: number = images ? 1000 : 10000;
    this.stateText = DemoL10n.text("已处理 0 / {0}，已保存 0 条", [String(total)]);
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    const importer = new FaceSearchDemoImporter(context, this.sdk, database,
      (): boolean => true);
    this.importer = importer;
    const progress = (value: FaceSearchImportProgress): void => {
      if (this.importer === importer) this.importSaved = value.imported;
      if (this.isTaskActive(token)) this.stateText =
        DemoL10n.text("已处理 {0} / {1}，已保存 {2} 条", [String(value.processed), String(value.total), String(value.imported)]);
    };
    const result: HiFaceResult<FaceSearchImportSummary> = images ?
      await importer.importImages(progress) : await importer.importFeatures(progress);
    // 旧任务返回时不能清空新页面导入器。
    if (this.importer === importer) this.importer = undefined;
    if (!this.isTaskActive(token)) return;
    this.busy = false;
    this.stoppingImport = false;
    if (result.isFailure()) {
      this.failed = true;
      this.stateText = DemoL10n.text("导入未完成，已保存 {0} 条：{1}", [String(this.importSaved), String(DemoErrorUi.describe(result.requireError()))]);
      this.exitAfterImport = false;
      this.showToast(this.stateText);
      return;
    }
    const summary: FaceSearchImportSummary = result.requireValue();
    const message: string = DemoL10n.text("{0}：已保存 {1} 条，失败 {2} 条", [String(summary.stopped ? DemoL10n.text("已停止") : DemoL10n.text("导入完成")), String(summary.imported), String(summary.failed)]);
    if (this.exitAfterImport) {
      this.importResultMessage = message;
      this.showImportResult();
      return;
    }
    this.showToast(message);
    this.lookupMode = false;
    this.faceId = '';
    this.loadFirstPage();
  }

  private showImportResult(): void {
    if (!this.active || this.exitDialogShowing || this.importResultMessage === undefined) return;
    const lifecycle: number = this.lifecycleToken;
    const message: string = this.importResultMessage;
    this.importResultMessage = undefined;
    this.getUIContext().showAlertDialog({ title: DemoL10n.text("导入结果"), message: message, autoCancel: false,
      primaryButton: { value: DemoL10n.text("返回"), action: (): void => {
        if (this.active && lifecycle === this.lifecycleToken) this.onExit();
      } } });
  }

  private dismissImportWait(): void {
    this.exitDialogShowing = false;
    this.showImportResult();
  }

  private requestExit(): void {
    if (this.importer === undefined) { this.onExit(); return; }
    if (this.exitDialogShowing) return;
    if (this.stoppingImport) {
      this.exitDialogShowing = true;
      this.getUIContext().showAlertDialog({ title: DemoL10n.text("任务正在执行"),
        message: DemoL10n.text("正在停止并保存，请稍候…"),
        cancel: (): void => this.dismissImportWait(),
        primaryButton: { value: DemoL10n.text("知道了"), action: (): void => this.dismissImportWait() } });
      return;
    }
    const lifecycle: number = this.lifecycleToken;
    this.exitDialogShowing = true;
    this.getUIContext().showAlertDialog({ title: DemoL10n.text("任务正在执行"),
      message: DemoL10n.text("正在导入。停止后保存已完成结果并退出。"),
      cancel: (): void => { this.exitDialogShowing = false; },
      primaryButton: { value: DemoL10n.text("停止并退出"), action: (): void => {
        if (!this.active || lifecycle !== this.lifecycleToken) return;
        this.exitDialogShowing = false;
        if (this.importer === undefined) { this.onExit(); return; }
        this.exitAfterImport = true;
        this.stoppingImport = true;
        this.stateText = DemoL10n.text("正在停止并保存，请稍候…");
        this.importer.requestStop();
      } },
      secondaryButton: { value: DemoL10n.text("继续导入"), action: (): void => { this.exitDialogShowing = false; } }
    });
  }

  /** 删除是不可恢复的数据操作，先展示当前 ID 再执行。 */
  private confirmDelete(faceId: string): void {
    if (this.busy) return;
    const lifecycle: number = this.lifecycleToken;
    this.getUIContext().showAlertDialog({
      title: DemoL10n.text("删除这条人脸？"),
      message: DemoL10n.text("Face ID：{0}\n\n删除后需重新录入。", [String(faceId)]),
      primaryButton: {
        value: DemoL10n.text("删除"), fontColor: DemoTheme.contentError,
        action: (): void => { if (lifecycle === this.lifecycleToken) this.deleteEntry(faceId); }
      },
      secondaryButton: { value: DemoL10n.text("取消"), action: (): void => {} }
    });
  }

  private async deleteEntry(faceId: string): Promise<void> {
    const database: FaceSearchDatabase | undefined = this.database;
    if (database === undefined || this.busy) return;
    const token: number = ++this.taskToken;
    const lookup: boolean = this.lookupMode;
    this.busy = true;
    try {
      const deleted: HiFaceResult<boolean> = await database.delete(faceId);
      if (!this.isTaskActive(token)) return;
      if (deleted.isFailure()) {
        this.showFailure(DemoL10n.text("删除失败"), deleted.requireError(), false);
        return;
      }
      this.busy = false;
      if (lookup) this.lookup(); else this.loadFirstPage();
    } catch (error) {
      if (this.isTaskActive(token)) {
        this.failed = true;
        this.stateText = DemoL10n.text("删除失败：{0}", [String(error)]);
      }
    } finally {
      if (this.isTaskActive(token)) this.busy = false;
    }
  }

  private showFailure(action: string, error: HiFaceError, clear: boolean): void {
    this.failed = true;
    this.canLoadMore = false;
    if (clear) this.entries = [];
    this.stateText = `${action}：${DemoErrorUi.describe(error)}`;
  }

  private isTaskActive(token: number): boolean {
    return this.active && this.database !== undefined && token === this.taskToken;
  }

  /** recent 排序会因覆盖记录改变；按 ID 更新元数据，避免分页期间出现重复卡片。 */
  private mergeEntries(page: FaceSearchLibraryItem[]): FaceSearchLibraryItem[] {
    const merged: FaceSearchLibraryItem[] = this.entries.slice();
    const indexes: Map<string, number> = new Map();
    merged.forEach((person: FaceSearchLibraryItem, index: number): void => {
      indexes.set(person.faceId, index);
    });
    page.forEach((person: FaceSearchLibraryItem): void => {
      const found: number | undefined = indexes.get(person.faceId);
      if (found !== undefined) {
        merged[found] = person;
      } else {
        indexes.set(person.faceId, merged.length);
        merged.push(person);
      }
    });
    return merged;
  }

  private stateColor(): string {
    if (this.failed) return DemoTheme.searchError;
    return '#B8C8DD';
  }

  private showToast(message: string): void {
    try { this.getUIContext().getPromptAction().showToast({ message: message }); } catch (_) {}
  }
}
