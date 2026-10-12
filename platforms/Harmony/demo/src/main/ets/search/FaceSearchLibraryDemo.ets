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
  @State private stateText: string = '正在打开人脸库…';
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

  aboutToAppear(): void {
    this.lifecycleBinding = this.cameraLifecycle.bind(
      (): void => this.stopPage(), (): void => this.startPage(), undefined, (): void => this.stopPage());
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

  /** 切后台或离开页面即停止下载和后续写库；已进入 Native 的单次操作自然结束。 */
  private stopPage(): void {
    if (!this.active) return;
    this.active = false;
    ++this.lifecycleToken;
    ++this.taskToken;
    this.canLoadMore = false;
    this.busy = false;
    this.importer?.cancel();
    this.importer = undefined;
    this.database?.close();
    this.database = undefined;
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_navigation_back')).width(23).height(23).fillColor('#FFFFFF')
        }
          .width(42).height(42).backgroundColor(Color.Transparent)
          .accessibilityText('返回').onClick(() => this.onExit())
        Text('人脸库')
          .fontSize(21).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          Text('⋮').fontSize(27).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
        }
          .width(42).height(42).backgroundColor(DemoTheme.surfaceOnDark)
          .enabled(!this.busy)
          .accessibilityText('功能菜单')
          .bindMenu([
            { value: '刷新', enabled: !this.busy, action: (): void => this.refresh() },
            { value: $r('app.string.search_import_features'), enabled: !this.busy && this.database !== undefined,
              action: (): void => this.confirmImport(false) },
            { value: $r('app.string.search_import_images'), enabled: !this.busy && this.database !== undefined,
              action: (): void => this.confirmImport(true) }
          ])
      }
      .padding({ left: 10, right: 14, top: 4, bottom: 4 })
      .width('100%')

      Row({ space: 4 }) {
        TextInput({ text: this.faceId, placeholder: '输入 Face ID 查找' })
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
          .accessibilityText('查找').onClick(() => this.lookup())
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
      Text(this.failed ? '操作失败' :
        this.lookupMode ? '未找到该 Face ID' : '当前范围内暂无已录入人脸')
        .fontSize(17).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
      Text(this.failed ? '请根据上方提示重试，或从右上角菜单刷新。' :
        this.lookupMode ? '请检查 Face ID，或清空输入返回全部记录。' :
          '可从右上角菜单导入演示数据。')
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
        Text(`分组：${entry.group.length === 0 ? '未分组' : entry.group}` +
          (entry.tag.length === 0 ? '' : ` · 标签：${entry.tag}`))
          .fontSize(12).fontColor('#98A2B3')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Button('删除')
        .enabled(!this.busy && this.database !== undefined).height(36).fontSize(12).fontColor(DemoTheme.searchError)
        .backgroundColor('#3A2430')
        .accessibilityText(`删除人脸 ${entry.faceId}`)
        .onClick(() => this.confirmDelete(entry.faceId))
    }
    .padding(13).backgroundColor(DemoTheme.searchSurface)
    .borderRadius(12).width('100%')
  }

  /** 每次进入页面打开独立管理连接；连续搜索使用 SDK 自己的连接。 */
  private async openAndLoad(lifecycle: number): Promise<void> {
    this.busy = true;
    this.failed = false;
    this.stateText = '正在打开人脸库…';
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const opened: HiFaceResult<FaceSearchDatabase> = await HiFaceSdk.openSearchDatabase(context);
      if (lifecycle !== this.lifecycleToken) {
        if (opened.isSuccess()) opened.requireValue().close();
        return;
      }
      if (opened.isFailure()) {
        this.failed = true;
        this.stateText = `打开失败：${DemoErrorUi.describe(opened.requireError())}`;
        return;
      }
      this.database = opened.requireValue();
      this.busy = false;
      if (this.faceId.trim().length > 0) this.lookup(); else this.loadFirstPage();
    } catch (error) {
      if (lifecycle === this.lifecycleToken) {
        this.failed = true;
        this.stateText = `打开失败：${error}`;
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
    if (offset === 0) this.stateText = '正在读取人脸库…';
    try {
      const counted: HiFaceResult<number> = await database.count();
      if (!this.isTaskActive(token)) return;
      if (counted.isFailure()) {
        this.showFailure('计数失败', counted.requireError(), offset === 0);
        return;
      }
      const total: number = counted.requireValue();
      if (offset >= total) {
        this.canLoadMore = false;
        this.stateText = `共 ${total} 条人脸记录`;
        return;
      }
      const listed: HiFaceResult<ReadonlyArray<FaceSearchMetadata>> =
        await database.listRecent('', '', offset, LOAD_SIZE);
      if (!this.isTaskActive(token)) return;
      if (listed.isFailure()) {
        this.showFailure('读取失败', listed.requireError(), offset === 0);
        return;
      }
      const loaded: FaceSearchLibraryItem[] = listed.requireValue().map(
        (entry: FaceSearchMetadata): FaceSearchLibraryItem => new FaceSearchLibraryItem(entry));
      this.nextOffset = offset + loaded.length;
      this.canLoadMore = loaded.length > 0 && this.nextOffset < total;
      this.entries = offset === 0 ? loaded : this.mergeEntries(loaded);
      this.failed = false;
      this.stateText = `共 ${total} 条人脸记录`;
    } catch (error) {
      if (this.isTaskActive(token)) {
        this.failed = true;
        this.canLoadMore = false;
        if (offset === 0) this.entries = [];
        this.stateText = `读取失败：${error}`;
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
    this.stateText = `正在查找 ${query}…`;
    try {
      const found: HiFaceResult<FaceSearchEntry> = await database.get(query);
      if (!this.isTaskActive(token)) return;
      if (found.isSuccess()) {
        this.entries = [new FaceSearchLibraryItem(found.requireValue())];
        this.stateText = '查找结果';
      } else if (found.requireError().code === HiFaceErrorCode.NOT_FOUND) {
        this.entries = [];
        this.stateText = '查找结果';
      } else {
        this.showFailure('查找失败', found.requireError(), true);
      }
    } catch (error) {
      if (this.isTaskActive(token)) {
        this.failed = true;
        this.entries = [];
        this.stateText = `查找失败：${error}`;
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
      title: images ? '批量导入人脸图片' : '批量导入人脸特征',
      message: images ?
        '将联网下载内置 JSON 中的1千张人脸图片，逐张提取特征并覆盖同 Face ID 记录。已提交批次会保留。' :
        '将从 App 内置 JSON 导入 1 万条 HF1 人脸特征，同 Face ID 记录会被覆盖。',
      primaryButton: { value: '开始导入', action: (): void => {
        if (lifecycle === this.lifecycleToken) this.startImport(images);
      } },
      secondaryButton: { value: '取消', action: (): void => {} }
    });
  }

  /** 页面只负责进度和结果；解析、下载、提取及分批写库由导入器完成。 */
  private async startImport(images: boolean): Promise<void> {
    const database: FaceSearchDatabase | undefined = this.database;
    if (database === undefined || this.busy) return;
    const token: number = ++this.taskToken;
    this.busy = true;
    this.failed = false;
    this.canLoadMore = false;
    const total: number = images ? 1000 : 10000;
    this.stateText = `正在导入 0 / ${total}`;
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    const importer = new FaceSearchDemoImporter(context, this.sdk, database,
      (): boolean => this.isTaskActive(token));
    this.importer = importer;
    const progress = (value: FaceSearchImportProgress): void => {
      if (this.isTaskActive(token)) this.stateText = `正在导入 ${value.processed} / ${value.total}`;
    };
    const result: HiFaceResult<FaceSearchImportSummary> = images ?
      await importer.importImages(progress) : await importer.importFeatures(progress);
    // 旧任务返回时不能清空新页面导入器。
    if (this.importer === importer) this.importer = undefined;
    if (!this.isTaskActive(token)) return;
    this.busy = false;
    if (result.isFailure()) {
      this.failed = true;
      this.stateText = `导入失败：${DemoErrorUi.describe(result.requireError())}`;
      this.showToast('批量导入失败');
      return;
    }
    const summary: FaceSearchImportSummary = result.requireValue();
    this.showToast(`已导入 ${summary.imported} 条，失败 ${summary.failed} 条`);
    this.lookupMode = false;
    this.faceId = '';
    this.loadFirstPage();
  }

  /** 删除是不可恢复的数据操作，先展示当前 ID 再执行。 */
  private confirmDelete(faceId: string): void {
    if (this.busy) return;
    const lifecycle: number = this.lifecycleToken;
    this.getUIContext().showAlertDialog({
      title: '删除这条人脸？',
      message: `Face ID：${faceId}\n\n删除后将无法搜索到这条人脸，需重新录入才能恢复。`,
      primaryButton: {
        value: '删除', fontColor: DemoTheme.contentError,
        action: (): void => { if (lifecycle === this.lifecycleToken) this.deleteEntry(faceId); }
      },
      secondaryButton: { value: '取消', action: (): void => {} }
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
        this.showFailure('删除失败', deleted.requireError(), false);
        return;
      }
      this.busy = false;
      if (lookup) this.lookup(); else this.loadFirstPage();
    } catch (error) {
      if (this.isTaskActive(token)) {
        this.failed = true;
        this.stateText = `删除失败：${error}`;
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
