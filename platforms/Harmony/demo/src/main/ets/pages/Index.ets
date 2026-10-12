import { FaceReference, FaceFeatureStore } from '../verification/FaceFeatureStore';
import { DemoTheme } from '../ui/DemoTheme';
import { DemoSdkSession } from '../ui/DemoSdkSession';
import { FaceSearchSessionConfig, HiFaceResult, HiFaceSdk } from 'hiface';
import { CameraSettingsDemo } from '../camera/CameraSettingsDemo';
import { CameraPageLifecycle } from '../camera/CameraPageLifecycle';
import { RealtimeCameraDemo } from './RealtimeCameraDemo';
import { RealtimeMode } from '../camera/RealtimeMode';
import { StaticFaceComparisonDemo } from '../comparison/StaticFaceComparisonDemo';
import { FaceSearchLibraryDemo } from '../search/FaceSearchLibraryDemo';
import { createDemoFaceSearchConfig } from '../search/DemoFaceSearchConfig';
import { common } from '@kit.AbilityKit';

// 与 Android DemoHomeActivity 的七个入口及搜索子页面一一对应。
enum DemoPage {
  HOME, DETECTION, ENROLLMENT, VERIFICATION, LIVENESS, SEARCH,
  COMPARISON, CAMERA_SETTINGS, SEARCH_LIBRARY, SEARCH_ENROLLMENT
}

/** Demo 根页面：持有唯一 SDK 实例、HUKS 加密验证基准和与 Android 一致的功能返回栈。 */
@Entry
@Component
struct Index {
  @State private activePage: DemoPage = DemoPage.HOME;
  @State private cameraPageKey: number = 0;
  @State private sdkState: string = '正在准备识别模型…';
  @State private sdkInitializing: boolean = true;
  @State private sdkFailed: boolean = false;
  @State private references: FaceReference[] = [];
  @State private selectingReference: boolean = false;
  @State private selectedFaceId: string = '';
  @State private selectedFeature: string = '';
  @State private searchConfig: FaceSearchSessionConfig = createDemoFaceSearchConfig();
  private readonly featureStore: FaceFeatureStore = new FaceFeatureStore();
  private readonly sdkSession: DemoSdkSession = new DemoSdkSession();
  private sdk: HiFaceSdk | undefined = undefined;
  private backStack: DemoPage[] = [];
  private lifecycleToken: number = 0;
  private referenceStoreToken: number = 0;
  private savingReference: boolean = false;
  private readonly cameraLifecycle: CameraPageLifecycle = new CameraPageLifecycle();

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
        title: '1:1 人脸基准读取失败',
        message: '加密数据或设备密钥不可用。可保留现状退出，或清除旧基准后重新录入。',
        primaryButton: {
          value: '清除并重新录入',
          action: (): void => { this.resetReferenceStore(); }
        },
        secondaryButton: { value: '暂不处理', action: (): void => {} }
      });
    } catch (_) {
      this.showToast('1:1 人脸基准无法安全读取');
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
      this.showToast('旧的 1:1 人脸基准已清除，请重新录入');
    } catch (_) {
      if (token === this.referenceStoreToken) this.showToast('清除旧人脸基准失败');
    }
  }

  /** 初始化可重试；token 保证旧实例的晚到结果不能覆盖新的页面状态。 */
  private async initializeSdk(): Promise<void> {
    const token: number = ++this.lifecycleToken;
    this.sdkInitializing = true;
    this.sdkFailed = false;
    this.sdk = undefined;
    this.sdkState = '正在准备识别模型…';
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    const ready: HiFaceResult<HiFaceSdk> = await this.sdkSession.initialize(context);
    if (token !== this.lifecycleToken) return;
    this.sdkInitializing = false;
    this.sdkFailed = ready.isFailure();
    this.sdk = ready.isSuccess() ? ready.requireValue() : undefined;
    this.sdkState = ready.isSuccess() ? '识别引擎已就绪' : '识别引擎初始化失败，请点击重试';
  }

  aboutToDisappear(): void {
    ++this.lifecycleToken;
    ++this.referenceStoreToken;
    this.cameraLifecycle.pause();
    this.sdkSession.close();
    this.sdk = undefined;
    this.featureStore.clear();
    this.references = [];
    this.selectedFeature = '';
  }

  onPageShow(): void { this.cameraLifecycle.resume(); }
  onPageHide(): void { this.cameraLifecycle.pause(); }

  onBackPress(): boolean {
    if (this.selectingReference) {
      this.selectingReference = false;
      return true;
    }
    if (this.activePage === DemoPage.HOME) return false;
    if (this.cameraLifecycle.handleBack()) return true;
    this.goBack();
    return true;
  }

  /** 离开当前功能前先停止相机生命周期，再创建新的页面实例。 */
  private navigate(page: DemoPage): void {
    if (this.sdk === undefined && page !== DemoPage.CAMERA_SETTINGS) {
      this.showToast(this.sdkState);
      return;
    }
    this.cameraLifecycle.leave();
    this.backStack.push(this.activePage);
    this.activePage = page;
    this.cameraPageKey += 1;
  }

  /** 返回栈只保存 Demo 功能页；相机释放由共享生命周期对象统一触发。 */
  private goBack(): void {
    this.cameraLifecycle.leave();
    this.activePage = this.backStack.pop() ?? DemoPage.HOME;
    this.cameraPageKey += 1;
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

  private chooseReference(): void {
    if (this.references.length === 0) {
      this.showToast('请先完成人脸采集');
      return;
    }
    this.selectingReference = true;
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
      if (this.activePage === DemoPage.HOME) {
        this.Home()
      } else if (this.activePage === DemoPage.COMPARISON && this.sdk !== undefined) {
        StaticFaceComparisonDemo({ sdk: this.sdk, onExit: (): void => this.goBack() })
      } else if (this.activePage === DemoPage.CAMERA_SETTINGS) {
        CameraSettingsDemo({ onExit: (): void => this.goBack() })
      } else if (this.activePage === DemoPage.SEARCH_LIBRARY && this.sdk !== undefined) {
        FaceSearchLibraryDemo({ sdk: this.sdk, cameraLifecycle: this.cameraLifecycle,
          onExit: (): void => this.goBack() })
      } else if (this.sdk !== undefined) {
        ForEach([this.cameraPageKey], (_key: number) => {
          RealtimeCameraDemo({
            sdk: this.sdk!, cameraLifecycle: this.cameraLifecycle,
            initialMode: this.cameraMode(), initialReferenceFeature: this.selectedFeature,
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
      if (this.selectingReference) {
        this.ReferencePicker()
      }
    }
    .width('100%').height('100%').backgroundColor(DemoTheme.brand)
  }

  @Builder
  private Home() {
    Scroll() {
      Column() {
        Row() {
          Column({ space: 2 }) {
            Text('HelloFace SDK').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
            Text('离线｜数据安全｜高效').fontSize(11).fontColor(DemoTheme.textOnDarkSecondary)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            Image($r('app.media.ic_api_info')).width(20).height(20)
          }.width(40).height(40).borderRadius(20).backgroundColor(DemoTheme.surfaceOnDark)
          .accessibilityText('关于').onClick(() => this.showAbout())
        }.width('100%')
        Text('选择一项能力开始体验').fontSize(10).fontColor(DemoTheme.textOnDarkSecondary)
          .width('100%').margin({ top: 22, bottom: 12 })
        if (this.sdkFailed) {
          Button(this.sdkState).fontSize(13).fontColor('#FFFFFF')
            .width('100%').backgroundColor(DemoTheme.surfaceOnDark).margin({ bottom: 12 })
            .enabled(!this.sdkInitializing).onClick(() => this.initializeSdk())
        }
        this.FeatureCard($r('app.media.ic_api_camera_small'), '实时人脸检测',
          '实时展示人脸框、五点、轮廓和头姿', (): void => this.navigate(DemoPage.DETECTION))
        this.FeatureCard($r('app.media.ic_home_enroll'), '人脸采集',
          '采集清晰正脸，并保存人脸特征', (): void => this.navigate(DemoPage.ENROLLMENT))
        this.FeatureCard($r('app.media.ic_home_verify'), '1:1 人脸验证',
          '选择 Face ID，完成动作活体后进行动态 1:1 验证', (): void => this.chooseReference())
        this.FeatureCard($r('app.media.ic_home_liveness'), '活体检测',
          '随机动作挑战与双模型静默检测', (): void => this.navigate(DemoPage.LIVENESS))
        this.FeatureCard($r('app.media.ic_search_search'), '人脸搜索识别',
          '从人脸库中检索匹配结果', (): void => this.navigate(DemoPage.SEARCH))
        this.FeatureCard($r('app.media.ic_home_compare'), '静态人脸 1:1 对比',
          '比较两张静态图片中的人脸', (): void => this.navigate(DemoPage.COMPARISON))
        this.FeatureCard($r('app.media.ic_search_settings'), '摄像头参数设置',
          '设置分析分辨率与坐标镜像', (): void => this.navigate(DemoPage.CAMERA_SETTINGS))
        Text('关于 HiFace SDK Demo').height(42).fontSize(12).fontColor(DemoTheme.textOnDarkSecondary)
          .width('100%').textAlign(TextAlign.Center).margin({ top: 3 })
          .onClick(() => this.showAbout())
      }.padding({ left: 20, right: 20, top: 16, bottom: 20 }).width('100%')
    }.width('100%').height('100%').scrollBar(BarState.Off)
  }

  @Builder
  private FeatureCard(icon: Resource, title: string, description: string, action: () => void) {
    Row({ space: 11 }) {
      Image(icon).width(36).height(36).padding(8).borderRadius(10)
        .backgroundColor(DemoTheme.surfaceOnDark)
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
        Text(description).fontSize(12).fontColor(DemoTheme.textOnDarkSecondary)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(24).fontColor(DemoTheme.textOnDarkSecondary)
    }.width('100%').constraintSize({ minHeight: 68 }).padding({ left: 11, right: 11, top: 9, bottom: 9 })
    .backgroundColor(DemoTheme.surfaceOnDark).border({ width: 1, color: '#3DFFFFFF' }).borderRadius(14)
    .margin({ bottom: 11 }).onClick(action)
  }

  @Builder
  private ReferencePicker() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor('#99000000')
        .onClick(() => { this.selectingReference = false; })
      Column({ space: 12 }) {
        Text('选择要验证的 Face ID').fontSize(20).fontColor(DemoTheme.contentText).width('100%')
        Scroll() {
          Column() {
            ForEach(this.references, (entry: FaceReference) => {
              Text(entry.faceId).width('100%').padding(16).fontColor(DemoTheme.contentText)
                .onClick(() => {
                  this.selectedFaceId = entry.faceId;
                  this.selectedFeature = entry.feature;
                  this.selectingReference = false;
                  this.navigate(DemoPage.VERIFICATION);
                })
            }, (entry: FaceReference): string => entry.faceId)
          }.width('100%')
        }.constraintSize({ maxHeight: 360 }).width('100%')
        Button('取消').fontColor(DemoTheme.brand).backgroundColor(Color.Transparent)
          .alignSelf(ItemAlign.End).onClick(() => { this.selectingReference = false; })
      }.width('86%').padding(24).backgroundColor('#FFFFFF').borderRadius(24)
    }.width('100%').height('100%')
  }

  private showToast(message: string): void {
    try { this.getUIContext().getPromptAction().showToast({ message: message }); } catch (_) {}
  }

  private showAbout(): void {
    this.showToast('更新以及更多说明：https://github.com/FaceSDKPro/');
  }
}
