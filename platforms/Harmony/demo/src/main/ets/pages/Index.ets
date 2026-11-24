import { DemoL10n } from '../ui/DemoL10n';
import { DemoErrorUi } from '../ui/DemoErrorUi';
import { DemoPageHeader } from '../ui/DemoPageHeader';
import { PixelMapResource } from '../ui/PixelMapResource';
import { RecognitionOptionsPanel } from '../recognition/RecognitionOptionsPanel';
import { FacePhotoLibrary, FacePhotoStore, FacePhotoThumbnail } from '../verification/FacePhotoStore';
import { FaceReference, FaceFeatureStore } from '../verification/FaceFeatureStore';
import { DemoTheme } from '../ui/DemoTheme';
import { FacePhotoPicker } from '../comparison/FacePhotoPicker';
import { FaceVerificationFlow } from '../verification/FaceVerificationFlow';
import { FaceAction, FaceCaptureResult, FaceSearchSessionConfig, HiFaceResult, HiFaceSdk } from 'hiface';
import { CameraSettingsDemo } from '../camera/CameraSettingsDemo';
import { CameraPageLifecycle } from '../camera/CameraPageLifecycle';
import { RecognitionOutcome } from '../camera/DemoCallbacks';
import { RealtimeCameraDemo } from './RealtimeCameraDemo';
import { RealtimeMode } from '../camera/RealtimeMode';
import { FaceImageSearchDemo } from '../search/FaceImageSearchDemo';
import { StaticFaceComparisonDemo } from '../comparison/StaticFaceComparisonDemo';
import { FaceSearchLibraryDemo } from '../search/FaceSearchLibraryDemo';
import { createDemoFaceSearchConfig } from '../search/DemoFaceSearchConfig';
import { bundleManager, common } from '@kit.AbilityKit';
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';

// 导航只保存页面，不包装 SDK；各功能页直接调用 hiface 的公开 API。
enum DemoPage {
  HOME, DETECTION, ENROLLMENT, VERIFICATION, LIVENESS, SEARCH,
  IMAGE_SEARCH, COMPARISON, CAMERA_SETTINGS, SEARCH_LIBRARY, SEARCH_ENROLLMENT, RECOGNITION
}

const WEBSITE_URL: string = 'https://helloface.pages.dev/';

/** 根页面拥有 SDK 和功能导航；1:1 基准文件仅用于 Demo。 */
@Entry
@Component
struct Index {
  private readonly appVersion: string = this.readAppVersion();

  private readAppVersion(): string {
    try {
      return bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch {
      return '—';
    }
  }

  private aboutTitle(): string {
    return DemoL10n.text("关于 HelloFace SDK {0}", [this.appVersion]);
  }

  @State private activePage: DemoPage = DemoPage.HOME;
  // Changes on navigation. Recreates the camera page and identifies album work from earlier visits.
  @State private cameraPageKey: number = 0;
  @State private verificationSilent: boolean = true;
  @State private verificationActionsEnabled: boolean = true;
  // Bits select blink, mouth open, head shake, and head nod in that order. 9 preselects blink and nod.
  @State private verificationActionMask: number = 9;
  @State private livenessSilent: boolean = true;
  @State private livenessActionsEnabled: boolean = true;
  // Keep a separate action mask for standalone liveness, with the same bit order as verification.
  @State private livenessActionMask: number = 9;
  @State private recognitionMessage: string = '';
  @State private recognitionOutcome: RecognitionOutcome = RecognitionOutcome.CANCELED;
  @State private recognitionFrame: image.PixelMap | undefined = undefined;
  @State private recognitionFrameSize: image.Size = { width: 0, height: 0 };
  @State private sdkState: string = DemoL10n.text("正在准备识别模型…");
  @State private sdkInitializing: boolean = true;
  @State private sdkFailed: boolean = false;
  @State private references: FaceReference[] = [];
  // A candidate opens the shared confirmation and stays in memory until the user saves.
  @State private albumCandidate: FaceCaptureResult | undefined = undefined;
  // Track the page key of the pending picker/extraction. -1 means idle.
  @State private pickingAlbumForPage: number = -1;
  @State private albumError: string = '';
  @State private selectedFaceId: string = '';
  @State private selectedFeature: string = '';
  @State private searchConfig: FaceSearchSessionConfig = createDemoFaceSearchConfig();
  private readonly featureStore: FaceFeatureStore = new FaceFeatureStore();
  // 只把就绪实例交给子页面；原生句柄和 Promise 不进入 ArkUI 可深拷贝的状态。
  private sdk: HiFaceSdk | undefined = undefined;
  // Candidate instance awaiting readiness; only a successful current initialization becomes sdk.
  private initializingSdk: HiFaceSdk | undefined = undefined;
  // Demo navigation history; cameraPageKey separately invalidates work from earlier page instances.
  private backStack: DemoPage[] = [];
  // Invalidates SDK readiness callbacks from an earlier initialization or a closed root page.
  private lifecycleToken: number = 0;
  // Guards publication of asynchronously loaded or saved references after reset or teardown.
  private referenceStoreToken: number = 0;
  private savingReference: boolean = false;
  // Ordered actions copied from the chosen card when a camera flow starts.
  private selectedActions: FaceAction[] = [];
  private readonly cameraLifecycle: CameraPageLifecycle = new CameraPageLifecycle();
  private readonly recognitionScroller: Scroller = new Scroller();
  // Late decodes must not attach to another run or retain a released page.
  private recognitionGeneration: number = 0;
  private readonly deviceValues: string[] = [
    `${deviceInfo.majorVersion}.${deviceInfo.seniorVersion}.${deviceInfo.featureVersion}`,
    deviceInfo.productModel || '-', deviceInfo.hardwareModel || '-'];
  private readonly deviceText: string = this.deviceValues.join('/');

  aboutToAppear(): void {
    this.initializeSdk();
    this.restoreReferences();
  }

  /** 从 HUKS 保护的持久化快照恢复 1:1 基准；旧页面的晚到结果不能覆盖当前状态。 */
  private async restoreReferences(): Promise<void> {
    const token: number = ++this.referenceStoreToken;
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const restored: FaceReference[] = await this.featureStore.load(context);
      if (token === this.referenceStoreToken) this.references = restored;
    } catch (_) {
      if (token === this.referenceStoreToken) {
        this.references = [];
        this.showReferenceStoreRecovery();
      }
    }
  }

  /** 认证失败或密钥不可用时不静默覆盖旧密文，只允许用户明确重置。 */
  private showReferenceStoreRecovery(): void {
    try {
      this.getUIContext().showAlertDialog({
        title: DemoL10n.text("1:1 人脸基准读取失败"),
        message: DemoL10n.text("数据或密钥不可用。可保留退出，或清除基准后重新录入。"),
        primaryButton: {
          value: DemoL10n.text("清除并重新录入"),
          action: (): void => { this.resetReferenceStore(); }
        },
        secondaryButton: { value: DemoL10n.text("暂不处理"), action: (): void => {} }
      });
    } catch (_) {
      this.showToast(DemoL10n.text("1:1 人脸基准无法安全读取"));
    }
  }

  private async resetReferenceStore(): Promise<void> {
    const token: number = this.referenceStoreToken;
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.featureStore.reset(context);
      if (token !== this.referenceStoreToken) return;
      this.references = [];
      this.selectedFaceId = '';
      this.selectedFeature = '';
      this.showToast(DemoL10n.text("旧的 1:1 人脸基准已清除，请重新录入"));
    } catch (_) {
      if (token === this.referenceStoreToken) this.showToast(DemoL10n.text("清除旧人脸基准失败"));
    }
  }

  /** 重试前关闭旧实例；token 防止已退出或被替换的初始化结果重新挂回页面。 */
  private async initializeSdk(): Promise<void> {
    const token: number = ++this.lifecycleToken;
    this.closeSdk();
    this.sdkInitializing = true;
    this.sdkFailed = false;
    this.sdkState = DemoL10n.text("正在准备识别模型…");
    let candidate: HiFaceSdk | undefined = undefined;
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      candidate = HiFaceSdk.create(context);
      this.initializingSdk = candidate;
      const ready: HiFaceResult<boolean> = await candidate.whenReady();
      if (token !== this.lifecycleToken) {
        candidate.close();
        return;
      }
      this.initializingSdk = undefined;
      this.sdkInitializing = false;
      this.sdkFailed = ready.isFailure();
      if (ready.isSuccess()) {
        this.sdk = candidate;
        this.sdkState = DemoL10n.text("识别引擎已就绪");
      } else {
        candidate.close();
        const error = ready.requireError();
        this.sdkState = DemoErrorUi.isAccessError(error) ? DemoErrorUi.describe(error) :
          DemoL10n.text("识别引擎初始化失败，请点击重试");
      }
    } catch (_) {
      candidate?.close();
      if (token !== this.lifecycleToken) return;
      this.initializingSdk = undefined;
      this.sdkInitializing = false;
      this.sdkFailed = true;
      this.sdkState = DemoL10n.text("识别引擎初始化失败，请点击重试");
    }
  }

  private closeSdk(): void {
    this.initializingSdk?.close();
    this.initializingSdk = undefined;
    this.sdk?.close();
    this.sdk = undefined;
  }

  aboutToDisappear(): void {
    // 先使异步结果失效，再停止相机并关闭 SDK 资源。
    ++this.lifecycleToken;
    ++this.referenceStoreToken;
    this.cameraLifecycle.pause();
    this.clearRecognitionResult();
    this.closeSdk();
    this.featureStore.clear();
    this.references = [];
    this.selectedFeature = '';
  }

  onPageShow(): void { this.cameraLifecycle.resume(); }
  onPageHide(): void { this.cameraLifecycle.pause(); }

  onBackPress(): boolean {
    if (this.activePage === DemoPage.HOME) return false;
    if (this.cameraLifecycle.handleBack()) return true;
    if (this.albumCandidate !== undefined) {
      this.closeAlbumConfirmation();
      return true;
    }
    this.goBack();
    return true;
  }

  /** 离开当前功能前先停止相机生命周期，再创建新的页面实例。 */
  private navigate(page: DemoPage): void {
    if (this.sdk === undefined && page !== DemoPage.CAMERA_SETTINGS && page !== DemoPage.RECOGNITION) {
      this.showToast(this.sdkState);
      return;
    }
    this.cameraLifecycle.leave();
    this.backStack.push(this.activePage);
    this.albumError = '';
    this.activePage = page;
    this.cameraPageKey += 1;
  }

  /** 返回栈只保存 Demo 功能页；相机释放由共享生命周期对象统一触发。 */
  private goBack(): void {
    const previous: DemoPage = this.activePage;
    this.cameraLifecycle.leave();
    this.activePage = this.backStack.pop() ?? DemoPage.HOME;
    this.cameraPageKey += 1;
    if (previous === DemoPage.RECOGNITION) this.clearRecognitionResult();
    if (this.activePage === DemoPage.RECOGNITION && this.recognitionMessage.length === 0 &&
      (previous === DemoPage.VERIFICATION || previous === DemoPage.LIVENESS)) {
      this.recognitionOutcome = RecognitionOutcome.CANCELED;
      this.recognitionMessage = DemoL10n.text('检测已取消');
      this.scrollToRecognitionResult(this.recognitionGeneration);
    }
  }

  private clearRecognitionResult(): void {
    ++this.recognitionGeneration;
    const previous: image.PixelMap | undefined = this.recognitionFrame;
    this.recognitionFrame = undefined;
    this.recognitionMessage = '';
    PixelMapResource.release(previous);
  }

  private receiveRecognitionResult(pageKey: number, message: string, outcome: RecognitionOutcome,
    frameJpeg?: ArrayBuffer): void {
    // The same camera mode can already be open for a retry when an older page returns.
    if (pageKey !== this.cameraPageKey ||
      (this.activePage !== DemoPage.VERIFICATION && this.activePage !== DemoPage.LIVENESS)) return;
    this.recognitionMessage = message;
    this.recognitionOutcome = outcome;
    this.goBack();
    const token: number = this.recognitionGeneration;
    this.scrollToRecognitionResult(token);
    if (frameJpeg !== undefined) this.showRecognitionFrame(frameJpeg, token);
  }

  private async showRecognitionFrame(jpeg: ArrayBuffer, token: number): Promise<void> {
    const frame: image.PixelMap | undefined = await PixelMapResource.createJpeg(jpeg);
    if (token !== this.recognitionGeneration || this.activePage !== DemoPage.RECOGNITION) {
      await PixelMapResource.release(frame);
      return;
    }
    if (frame !== undefined) {
      try {
        const size: image.Size = frame.getImageInfoSync().size;
        if (size.width <= 0 || size.height <= 0) {
          await PixelMapResource.release(frame);
          return;
        }
        // Fit the visible image so the card padding begins at the photo edge.
        const scale: number = Math.min(160 / size.width, 120 / size.height);
        this.recognitionFrameSize = {
          width: Math.max(1, Math.round(size.width * scale)), height: Math.max(1, Math.round(size.height * scale))
        };
      } catch (_) {
        await PixelMapResource.release(frame);
        return;
      }
      this.recognitionFrame = frame;
      this.scrollToRecognitionResult(token);
    }
  }

  private scrollToRecognitionResult(token: number): void {
    setTimeout((): void => {
      if (token === this.recognitionGeneration && this.activePage === DemoPage.RECOGNITION) {
        this.recognitionScroller.scrollEdge(Edge.Bottom);
      }
    }, 0);
  }

  private keepsImageSearch(): boolean {
    return this.activePage === DemoPage.IMAGE_SEARCH ||
      (this.activePage === DemoPage.SEARCH_LIBRARY && this.backStack[this.backStack.length - 1] === DemoPage.IMAGE_SEARCH);
  }

  private cameraMode(): RealtimeMode {
    if (this.activePage === DemoPage.ENROLLMENT) return RealtimeMode.CAPTURE;
    if (this.activePage === DemoPage.VERIFICATION) return RealtimeMode.VERIFICATION;
    if (this.activePage === DemoPage.LIVENESS) return RealtimeMode.LIVENESS;
    if (this.activePage === DemoPage.SEARCH_ENROLLMENT) return RealtimeMode.SEARCH_ENROLLMENT;
    if (this.activePage === DemoPage.SEARCH) return this.searchConfig.mode === 1 ?
      RealtimeMode.SEARCH_MULTI : RealtimeMode.SEARCH_SINGLE;
    return RealtimeMode.DETECTION;
  }

  /** 1:1 基准与搜索库分开保存；只返回落盘结果，由仍然可见的相机页决定导航。 */
  private async saveReference(faceId: string, feature: string): Promise<boolean> {
    if (this.savingReference) return false;
    this.savingReference = true;
    const token: number = this.referenceStoreToken;
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const saved: FaceReference[] = await this.featureStore.save(context, faceId, feature);
      if (token !== this.referenceStoreToken) return false;
      this.references = saved;
      return true;
    } catch (_) {
      return false;
    } finally {
      this.savingReference = false;
    }
  }

  build() {
    Stack() {
      // Keep the photo-search instance while its library child is open; leaving the feature releases it.
      if (this.keepsImageSearch() && this.sdk !== undefined) {
        FaceImageSearchDemo({ sdk: this.sdk, onExit: (): void => this.goBack(),
          onOpenLibrary: (): void => this.navigate(DemoPage.SEARCH_LIBRARY) })
          .visibility(this.activePage === DemoPage.IMAGE_SEARCH ? Visibility.Visible : Visibility.Hidden)
      }
      if (this.activePage === DemoPage.HOME) {
        this.Home()
      } else if (this.activePage === DemoPage.RECOGNITION) {
        this.RecognitionPage()
        if (this.albumCandidate !== undefined && this.sdk !== undefined) {
          RealtimeCameraDemo({
            sdk: this.sdk, cameraLifecycle: this.cameraLifecycle, initialMode: RealtimeMode.CAPTURE,
            albumCandidate: this.albumCandidate,
            onReferenceConfirmed: (id: string, feature: string): Promise<boolean> => this.saveReference(id, feature),
            onPickAnother: (): void => { this.closeAlbumConfirmation(); this.pickReferencePhoto(); },
            onExit: (message?: string): void => this.closeAlbumConfirmation(message)
          })
        }
      } else if (this.activePage === DemoPage.COMPARISON && this.sdk !== undefined) {
        StaticFaceComparisonDemo({ sdk: this.sdk, onExit: (): void => this.goBack() })
      } else if (this.activePage === DemoPage.CAMERA_SETTINGS) {
        CameraSettingsDemo({ onExit: (): void => this.goBack() })
      } else if (this.activePage === DemoPage.SEARCH_LIBRARY && this.sdk !== undefined) {
        FaceSearchLibraryDemo({ sdk: this.sdk, cameraLifecycle: this.cameraLifecycle,
          onExit: (): void => this.goBack() })
      } else if (this.activePage !== DemoPage.IMAGE_SEARCH && this.sdk !== undefined) {
        ForEach([this.cameraPageKey], (key: number) => {
          RealtimeCameraDemo({
            sdk: this.sdk!, cameraLifecycle: this.cameraLifecycle,
            initialMode: this.cameraMode(), initialReferenceFeature: this.selectedFeature,
            recognitionConfigured: this.activePage === DemoPage.VERIFICATION || this.activePage === DemoPage.LIVENESS,
            recognitionActions: this.selectedActions,
            recognitionSilent: this.verificationSilent,
            onRecognitionResult: (message: string, outcome: RecognitionOutcome,
              frameJpeg?: ArrayBuffer): void => this.receiveRecognitionResult(key, message, outcome, frameJpeg),
            referenceFaceId: this.selectedFaceId, initialSearchConfig: this.searchConfig,
            onReferenceConfirmed: (faceId: string, feature: string): Promise<boolean> =>
              this.saveReference(faceId, feature),
            onSearchConfigChanged: (config: FaceSearchSessionConfig): void => { this.searchConfig = config; },
            onExit: (): void => this.goBack(),
            onOpenLibrary: (): void => this.navigate(DemoPage.SEARCH_LIBRARY),
            onEnroll: (): void => this.navigate(DemoPage.SEARCH_ENROLLMENT)
          })
        }, (key: number): string => `${key}`)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.activePage === DemoPage.RECOGNITION ? DemoTheme.contentBackground :
      this.activePage === DemoPage.HOME ? DemoTheme.homeBackground : DemoTheme.brand)
  }

  @Builder
  private Home() {
    Scroll() {
      Column() {
        Row() {
          Column({ space: 2 }) {
            Text('HelloFace SDK').fontSize(18).fontWeight(FontWeight.Medium).fontColor(DemoTheme.textOnDark)
            Text(DemoL10n.text("离线｜数据安全｜高效")).fontSize(11).fontColor(DemoTheme.textOnDarkSecondary)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            Image($r('app.media.ic_api_info')).width(20).height(20)
          }.width(40).height(40).borderRadius(20).backgroundColor(DemoTheme.surfaceOnDark)
          .accessibilityText(this.aboutTitle()).onClick(() => this.openWebsite())
        }.width('100%')
        Text(this.deviceText).fontSize(10).fontColor(DemoTheme.textOnDarkSecondary)
          .width('100%').textAlign(TextAlign.End).padding({ right: 4 }).margin({ top: 11, bottom: 12 })
          .gesture(LongPressGesture({ repeat: false, duration: 500 })
            .onAction((): void => this.copyDeviceInfo()))
        if (this.sdkFailed) {
          Button(this.sdkState).fontSize(13).fontColor(DemoTheme.textOnDark)
            .width('100%').backgroundColor(DemoTheme.surfaceOnDark).margin({ bottom: 12 })
            .enabled(!this.sdkInitializing).onClick(() => this.initializeSdk())
        }
        this.FeatureCard($r('app.media.ic_api_camera_small'), DemoL10n.text("实时人脸检测"),
          DemoL10n.text("查看人脸框、关键点、轮廓和头姿"), (): void => this.navigate(DemoPage.DETECTION))
        this.FeatureCard($r('app.media.ic_home_verify'), DemoL10n.text("人脸识别"),
          DemoL10n.text("通过相机进行 1:1 人脸识别与活体检测"), (): void => this.navigate(DemoPage.RECOGNITION))
        this.FeatureCard($r('app.media.ic_search_search'), DemoL10n.text("人脸搜索识别"),
          DemoL10n.text("RGB相机搜索识别，1:N搜索活体也用RGB相机"), (): void => this.navigate(DemoPage.SEARCH))
        this.FeatureCard($r('app.media.ic_home_compare'), DemoL10n.text("静态人脸 1:1 对比"),
          DemoL10n.text("比对两张图片中的人脸"), (): void => this.navigate(DemoPage.COMPARISON))
        this.FeatureCard($r('app.media.ic_search_search'), DemoL10n.text("图片人脸搜索识别"),
          DemoL10n.text("检测图片中的多个人脸并搜索人脸库"), (): void => this.navigate(DemoPage.IMAGE_SEARCH))
        this.FeatureCard($r('app.media.ic_search_settings'), DemoL10n.text("SDK参数设置"),
          DemoL10n.text("设置分析分辨率与坐标镜像"), (): void => this.navigate(DemoPage.CAMERA_SETTINGS))
        Text(this.aboutTitle()).height(42).fontSize(12).fontColor(DemoTheme.textOnDarkSecondary)
          .width('100%').textAlign(TextAlign.Center).margin({ top: 3 })
          .onClick(() => this.openWebsite())
      }.padding({ left: 20, right: 20, top: 16, bottom: 20 }).width('100%')
    }.width('100%').height('100%').scrollBar(BarState.Off)
  }

  private recognitionActions(verification: boolean): FaceAction[] {
    const enabled: boolean = verification ? this.verificationActionsEnabled : this.livenessActionsEnabled;
    const mask: number = verification ? this.verificationActionMask : this.livenessActionMask;
    const order: FaceAction[] = [FaceAction.BLINK, FaceAction.MOUTH_OPEN, FaceAction.SHAKE_HEAD, FaceAction.NOD_HEAD];
    const actions: FaceAction[] = [];
    if (enabled) for (let index: number = 0; index < order.length; ++index) {
      if ((mask & (1 << index)) !== 0) actions.push(order[index]);
    }
    return actions;
  }

  private startRecognition(reference: FaceReference | undefined = undefined): void {
    if (this.sdk === undefined) {
      this.showToast(this.sdkState);
      return;
    }
    const verification: boolean = reference !== undefined;
    const enabled: boolean = verification ? this.verificationActionsEnabled : this.livenessActionsEnabled;
    const actions: FaceAction[] = this.recognitionActions(verification);
    if (enabled && actions.length === 0) {
      this.showToast(DemoL10n.text('请至少勾选一个动作'));
      return;
    }
    this.selectedActions = actions;
    this.clearRecognitionResult();
    if (reference !== undefined) {
      this.selectedFaceId = reference.faceId;
      this.selectedFeature = reference.feature;
    }
    this.navigate(verification ? DemoPage.VERIFICATION : DemoPage.LIVENESS);
  }

  private confirmDeleteReference(faceId: string): void {
    const token: number = this.referenceStoreToken;
    this.getUIContext().showAlertDialog({
      title: DemoL10n.text('删除这条人脸？'),
      message: DemoL10n.text('Face ID：{0}\n\n删除后需重新录入。', [faceId]),
      primaryButton: {
        value: DemoL10n.text('删除'), fontColor: DemoTheme.contentError,
        action: (): void => {
          if (token === this.referenceStoreToken && this.activePage === DemoPage.RECOGNITION) {
            this.deleteReference(faceId);
          }
        }
      },
      secondaryButton: { value: DemoL10n.text('取消'), action: (): void => {} }
    });
  }

  private async deleteReference(faceId: string): Promise<void> {
    const token: number = ++this.referenceStoreToken;
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const remaining: FaceReference[] = await this.featureStore.remove(context, faceId);
      // The encrypted feature snapshot is authoritative. A stale thumbnail must not
      // make a completed identity deletion look as though it failed.
      // 加密特征快照是权威数据；旧头像清理失败不能把已完成的身份删除显示成失败。
      try {
        await FacePhotoStore.remove(context, faceId, FacePhotoLibrary.REFERENCE);
      } catch (_) {
        // The photo is only Demo presentation data and is no longer reachable.
      }
      if (token === this.referenceStoreToken && this.activePage === DemoPage.RECOGNITION) {
        this.references = remaining;
        this.showToast(DemoL10n.text('已删除 {0}', [faceId]));
      }
    } catch (error) {
      if (token === this.referenceStoreToken && this.activePage === DemoPage.RECOGNITION) {
        this.showToast(DemoL10n.text('删除失败：{0}', [String(error)]));
      }
    }
  }

  // Keep the system picker on the recognition page; discard results from a previous visit.
  private async pickReferencePhoto(): Promise<void> {
    const sdk = this.sdk;
    if (sdk === undefined) { this.showToast(this.sdkState); return; }
    const page = this.cameraPageKey;
    if (this.pickingAlbumForPage === page) return;
    this.pickingAlbumForPage = page;
    this.albumError = '';
    try {
      const photo = await FacePhotoPicker.select(FacePhotoPicker.IMAGE_SEARCH_MAX_SIDE);
      if (photo === undefined || this.cameraPageKey !== page || this.sdk !== sdk) return;
      const sample = await FaceVerificationFlow.referenceFromPhoto(sdk, photo);
      if (this.cameraPageKey !== page || this.sdk !== sdk) return;
      if (sample.alignedRgba === undefined) throw new Error(DemoL10n.text("录入预览生成失败"));
      this.albumCandidate = sample;
    } catch (error) {
      if (this.cameraPageKey === page && this.sdk === sdk) this.albumError = (error as Error).message;
    } finally {
      if (this.pickingAlbumForPage === page) this.pickingAlbumForPage = -1;
    }
  }

  private closeAlbumConfirmation(message: string = ''): void {
    this.cameraLifecycle.leave();
    this.albumCandidate = undefined;
    this.albumError = message;
  }

  @Builder
  private EnrollmentButton(label: string, action: () => void) {
    Button(label, { type: ButtonType.Normal }).layoutWeight(1).height(42).padding({ left: 4, right: 4 })
      .backgroundColor(Color.Transparent).fontColor(DemoTheme.homeBackground).fontSize(16).fontWeight(FontWeight.Bold)
      .onClick(action)
  }

  @Builder
  private RecognitionPage() {
    Column() {
      DemoPageHeader({ title: DemoL10n.text('人脸识别'), onBack: (): void => this.goBack() })
      Scroll(this.recognitionScroller) {
        Column({ space: 12 }) {
        Column({ space: 11 }) {
          Text(DemoL10n.text('1:1 人脸验证')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(DemoTheme.contentText)
          Text(DemoL10n.text('选择已录入的人脸，与当前相机人脸进行比对')).fontSize(12).fontColor(DemoTheme.contentSecondary)
          RecognitionOptionsPanel({ silent: $verificationSilent, actionsEnabled: $verificationActionsEnabled,
            actionMask: $verificationActionMask })
          Text(DemoL10n.text('已录入的人脸')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(DemoTheme.contentText)
          Column({ space: 4 }) {
            Text(DemoL10n.text(this.references.length === 0 ? '暂无已录入的人脸。' :
              '左右滑动，点击头像开始 1:1 验证，长按删除')).fontSize(12).fontColor(DemoTheme.contentSecondary)
            if (this.references.length > 0) {
              List({ space: 12 }) {
                ForEach(this.references, (entry: FaceReference) => {
                  ListItem() {
                    Column({ space: 8 }) {
                      FacePhotoThumbnail({ faceId: entry.faceId, library: FacePhotoLibrary.REFERENCE, diameter: 72, circular: true })
                      Text(entry.faceId).fontSize(13).fontColor(DemoTheme.contentText).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                        .textAlign(TextAlign.Center).width('100%')
                    }.width(96).padding({ top: 4, bottom: 4 })
                  }.priorityGesture(GestureGroup(GestureMode.Exclusive,
                    LongPressGesture({ repeat: false, duration: 500 })
                      .onAction((): void => this.confirmDeleteReference(entry.faceId)),
                    TapGesture().onAction((): void => this.startRecognition(entry))))
                    .accessibilityText(DemoL10n.text('验证 {0}，长按删除', [entry.faceId]))
                }, (entry: FaceReference): string => entry.faceId)
              }.listDirection(Axis.Horizontal).width('100%').height(116)
                .scrollBarWidth(1)
            }
            Row({ space: 16 }) {
              this.EnrollmentButton(DemoL10n.text('相册添加'), (): void => { this.pickReferencePhoto(); })
              this.EnrollmentButton(DemoL10n.text('相机录入'), (): void => this.navigate(DemoPage.ENROLLMENT))
            }.width('100%')
            if (this.albumError.length > 0) {
              Text(this.albumError).fontSize(12).fontColor(DemoTheme.contentError)
            }
          }.alignItems(HorizontalAlign.Start).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 14, right: 14, top: 14, bottom: 6 }).backgroundColor('#FFFFFF')
          .borderRadius(16).border({ width: 1, color: '#E2E8E5' })
        Column({ space: 11 }) {
          Text(DemoL10n.text('独立活体检测')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(DemoTheme.contentText)
          Text(DemoL10n.text('不比对身份。静默活体始终开启，可叠加动作挑战。')).fontSize(12).fontColor(DemoTheme.contentSecondary)
          RecognitionOptionsPanel({ silent: $livenessSilent, actionsEnabled: $livenessActionsEnabled,
            actionMask: $livenessActionMask, standalone: true })
          Button(DemoL10n.text('开始活体检测')).width('100%').height(48)
            .backgroundColor(DemoTheme.contentAccent).fontColor(DemoTheme.textOnDark)
            .onClick(() => this.startRecognition())
        }.width('100%').alignItems(HorizontalAlign.Start).padding(14).backgroundColor('#FFFFFF')
          .borderRadius(16).border({ width: 1, color: '#E2E8E5' })
        if (this.recognitionMessage.length > 0) {
          Row({ space: 12 }) {
            Text(this.recognitionMessage).fontSize(14).fontColor(this.recognitionOutcome === RecognitionOutcome.PASSED
              ? DemoTheme.contentAccent : this.recognitionOutcome === RecognitionOutcome.CANCELED
              ? DemoTheme.contentSecondary : DemoTheme.contentError).layoutWeight(1)
            if (this.recognitionFrame !== undefined) {
              Image(this.recognitionFrame).width(this.recognitionFrameSize.width).height(this.recognitionFrameSize.height)
                .objectFit(ImageFit.Contain)
                .accessibilityText(DemoL10n.text('检测结束时的相机画面'))
            }
          }.alignItems(VerticalAlign.Center).width('100%').padding(14)
            .backgroundColor('#FFFFFF')
            .borderRadius(16).border({ width: 1, color: '#E2E8E5' })
        }
        }.padding({ left: 12, right: 12, top: 8, bottom: 16 }).width('100%')
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(DemoTheme.contentBackground)
      .enabled(this.albumCandidate === undefined && this.pickingAlbumForPage !== this.cameraPageKey)
  }

  @Builder
  private FeatureCard(icon: Resource, title: string, description: string, action: () => void) {
    Row({ space: 11 }) {
      Image(icon).width(36).height(36).padding(8).borderRadius(12)
        .border({ width: 1, color: DemoTheme.borderOnDark })
        .backgroundColor(DemoTheme.surfaceOnDark)
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(DemoTheme.textOnDark)
        Text(description).fontSize(12).fontColor(DemoTheme.textOnDarkSecondary)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(24).fontColor(DemoTheme.homeArrow)
        .width(28).height(28).textAlign(TextAlign.Center).borderRadius(14)
        .backgroundColor(DemoTheme.homeArrowSurface)
    }.width('100%').constraintSize({ minHeight: 68 }).padding({ left: 11, right: 11, top: 9, bottom: 9 })
    .backgroundColor(DemoTheme.surfaceOnDark).border({ width: 1, color: DemoTheme.borderOnDark }).borderRadius(14)
    .margin({ bottom: 11 }).onClick(action)
  }

  private copyDeviceInfo(): void {
    const value: string = this.deviceText;
    hilog.info(0xFF00, 'DeviceInfo', '%{public}s', value);
    try {
      pasteboard.getSystemPasteboard().setDataSync(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value));
      this.showToast(DemoL10n.text("已复制"));
    } catch (_) {
      this.showToast(DemoL10n.text("复制失败"));
    }
  }

  private showToast(message: string): void {
    try { this.getUIContext().getPromptAction().showToast({ message: message }); } catch (_) {}
  }

  private async openWebsite(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.openLink(WEBSITE_URL, { appLinkingOnly: false });
    } catch (_) {
      this.showToast(DemoL10n.text("更多：{0}", [WEBSITE_URL]));
    }
  }
}
