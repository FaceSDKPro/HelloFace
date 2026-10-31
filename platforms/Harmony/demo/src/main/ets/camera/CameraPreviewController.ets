import { DemoL10n } from '../ui/DemoL10n';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { BusinessError, systemDateTime } from '@kit.BasicServicesKit';
import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DEBUG } from 'BuildProfile';
import { Yuv420Frame } from 'hiface';
import { CameraFrameAdapter } from './CameraFrameAdapter';
import { CameraFrameRatePolicy, CameraFrameRateRange } from './CameraFrameRatePolicy';
import { CameraDemoSettings } from './CameraDemoSettings';
import { CameraProfileSelector } from './CameraProfileSelector';
import { CameraPreviewCallbacks, CameraPreviewState } from './CameraPreviewCallbacks';

const CAMERA_PERMISSION: Permissions = 'ohos.permission.CAMERA';
const RECEIVER_CAPACITY: number = 3;

/**
 * CameraKit dual-output preview with ImageReceiver NV21 adaptation, latest-frame backpressure, and
 * deterministic cleanup.
 *
 * CameraKit 双路预览，ImageReceiver NV21 适配、最新帧背压和确定性释放。
 */
export class CameraPreviewController {
  private readonly context: common.UIAbilityContext;
  private readonly callbacks: CameraPreviewCallbacks;
  private readonly settings: CameraDemoSettings;
  private readonly limitDisplayFrameRate: boolean;
  // The constructor rate is the active ceiling; preview may drop to 10 FPS while search is
  // idle.
  // 构造值是活跃上限；搜索待机预览可降至 10 FPS，分析独立降至 5 FPS。
  private readonly sessionFrameRate: number;
  private targetSessionFrameRate: number;
  private targetAnalysisFrameRate: number;
  private analysisOutputRateLimited: boolean = false;
  private applicationFrameInterval: number = 0;
  private cameraDevice: camera.CameraDevice | undefined = undefined;
  private cameraInput: camera.CameraInput | undefined = undefined;
  private session: camera.VideoSession | undefined = undefined;
  private displayOutput: camera.PreviewOutput | undefined = undefined;
  private analysisOutput: camera.PreviewOutput | undefined = undefined;
  private receiver: image.ImageReceiver | undefined = undefined;
  private surfaceId: string = '';
  private active: boolean = false;
  private frontCamera: boolean = true;
  private previewAspect: number = 0.75;
  private rotationDegrees: number = 0;
  private generation: number = 0;
  private frameTask: Promise<void> | undefined = undefined;
  private consumerTask: Promise<void> | undefined = undefined;
  private pendingFrame: Yuv420Frame | undefined = undefined;
  private static lifecycleTask: Promise<void> = Promise.resolve();
  private droppedFrames: number = 0;
  private consecutiveFrameErrors: number = 0;
  private frameWatchdog: number = -1;
  private lastFrameAt: number = 0;
  private lastAnalysisFrameAt: number = -1;
  private analysisPaused: boolean = false;
  private frameTimingSamples: number = 0;

  getPreviewAspectRatio(): number { return this.previewAspect; }

  // Bind events independently for each profile attempt; invalidate callbacks already queued before
  // off().
  // 每次规格尝试独立绑定事件。off() 前已排队的回调也必须失效。
  private attempt: number = 0;
  private startupError: string | undefined = undefined;
  private inputErrorCallback: ((error: BusinessError) => void) | undefined = undefined;
  private sessionErrorCallback: ((error: BusinessError) => void) | undefined = undefined;
  private previewErrorCallback: ((error: BusinessError) => void) | undefined = undefined;
  private arrivalCallback: (() => void) | undefined = undefined;

  private handleArrival(): void {
    if (!this.active) return;
    if (this.frameTask !== undefined) {
      // For overlapping callbacks, wait for the next actual frame event instead of reading the same
      // notifications twice.
      // 回调重叠时等待下一次真实到帧事件，避免重复读取同一批通知。
      this.recordDroppedFrame();
      return;
    }
    this.startFrameTask();
  }

  constructor(context: common.UIAbilityContext, callbacks: CameraPreviewCallbacks,
    settings: CameraDemoSettings = new CameraDemoSettings(), sessionFrameRate: number = 30,
    limitDisplayFrameRate: boolean = false) {
    if (!Number.isInteger(sessionFrameRate) || sessionFrameRate <= 0) {
      throw new Error('Session frame rate must be a positive integer');
    }
    this.context = context;
    this.callbacks = callbacks;
    this.settings = settings;
    this.sessionFrameRate = sessionFrameRate;
    this.targetSessionFrameRate = sessionFrameRate;
    this.targetAnalysisFrameRate = sessionFrameRate;
    this.limitDisplayFrameRate = limitDisplayFrameRate;
  }

  async start(surfaceId: string, preferFrontCamera: boolean = true): Promise<void> {
    const token: number = ++this.generation;
    this.active = false;
    // Serialize startup and cleanup so close() cannot race open(), and an old start cannot overwrite newer
    // resources.
    // 串行完成上一轮启动/释放，避免 open() 尚未完成就 close()，或旧启动覆盖新资源。
    const task: Promise<void> = CameraPreviewController.lifecycleTask.then(async (): Promise<void> => {
      await this.stopInternal();
      if (token === this.generation) {
        await this.startInternal(surfaceId, preferFrontCamera, token);
      }
    });
    CameraPreviewController.lifecycleTask = task.catch(() => {});
    await task;
  }

  private async startInternal(surfaceId: string, preferFrontCamera: boolean,
    token: number): Promise<void> {
    if (surfaceId.length === 0) {
      this.callbacks.onCameraError(DemoL10n.text("预览 Surface 尚未就绪"));
      return;
    }
    this.surfaceId = surfaceId;
    this.frontCamera = preferFrontCamera;
    this.callbacks.onCameraState(CameraPreviewState.REQUESTING_PERMISSION, this.frontCamera, '');
    try {
      if (!await this.requestPermission() || token !== this.generation) {
        if (token === this.generation) {
          this.callbacks.onCameraError(DemoL10n.text("需要相机权限才能运行实时人脸 Demo"));
        }
        return;
      }
      this.callbacks.onCameraState(CameraPreviewState.OPENING, this.frontCamera, '');
      const manager: camera.CameraManager = camera.getCameraManager(this.context);
      const device: camera.CameraDevice = this.selectCamera(
        manager.getSupportedCameras(), preferFrontCamera);
      this.cameraDevice = device;
      this.frontCamera = device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT;
      const capability: camera.CameraOutputCapability =
        manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_VIDEO);
      const profiles: camera.Profile[] = CameraProfileSelector.select(
        capability.previewProfiles, this.settings.highResolution);
      for (let index: number = 0; index < profiles.length; index++) {
        if (token !== this.generation) return;
        try {
          await this.startProfile(manager, device, profiles[index], surfaceId, token);
          if (token !== this.generation) await this.stopInternal();
          return;
        } catch (error) {
          // Support for each profile individually does not guarantee dual-output support. Fully release
          // partially opened resources before trying a smaller shared profile.
          // 设备单独声明支持某个规格，不代表它支持双输出组合。尝试更小的共享规格前，
          // 必须完整释放本次已经打开的部分资源。
          await this.stopInternal();
          if (token !== this.generation) return;
          if (index === profiles.length - 1) throw new Error(`${error}`);
          this.callbacks.onCameraState(CameraPreviewState.TRYING_PROFILE, this.frontCamera, '');
        }
      }
    } catch (error) {
      await this.stopInternal();
      if (token === this.generation) {
        try { this.callbacks.onCameraError(DemoL10n.text("相机启动失败：{0}", [String(error)])); } catch (_) {}
      }
    }
  }

  private async startProfile(manager: camera.CameraManager, device: camera.CameraDevice,
    analysisProfile: camera.Profile, surfaceId: string, token: number): Promise<void> {
    this.cameraDevice = device;
    const attempt: number = ++this.attempt;
    this.startupError = undefined;
    this.inputErrorCallback = (error: BusinessError): void =>
      this.handleRuntimeError(DemoL10n.text("相机输入中断"), error, token, attempt);
    this.sessionErrorCallback = (error: BusinessError): void =>
      this.handleRuntimeError(DemoL10n.text("相机会话异常"), error, token, attempt);
    this.previewErrorCallback = (error: BusinessError): void =>
      this.handleRuntimeError(DemoL10n.text("相机预览异常"), error, token, attempt);
    this.arrivalCallback = (): void => {
      if (token === this.generation && attempt === this.attempt) this.handleArrival();
    };
    // Use matching aspect ratios for both outputs to avoid face-box offsets between 16:9 analysis and 4:3
    // preview.
    // 两路使用相同比例，避免高清分析 16:9 与可见预览 4:3 的人脸框偏移。
    const displayProfile: camera.Profile = analysisProfile;
    const profileLabel: string = `${analysisProfile.size.width}×${analysisProfile.size.height}`;
    try {
      const receiverSize: image.Size = {
        width: analysisProfile.size.width,
        height: analysisProfile.size.height
      };
      const receiver: image.ImageReceiver = image.createImageReceiver(
        receiverSize, image.ImageFormat.JPEG, RECEIVER_CAPACITY);
      this.receiver = receiver;
      receiver.on('imageArrival', this.arrivalCallback);
      const analysisSurfaceId: string = await receiver.getReceivingSurfaceId();
      if (!this.canContinueStartup(token)) {
        return;
      }

      const input: camera.CameraInput = manager.createCameraInput(device);
      this.cameraInput = input;
      input.on('error', device, this.inputErrorCallback);
      await input.open();
      if (!this.canContinueStartup(token)) {
        return;
      }

      const displayOutput: camera.PreviewOutput = manager.createPreviewOutput(displayProfile, surfaceId);
      this.displayOutput = displayOutput;
      const analysisOutput: camera.PreviewOutput = manager.createPreviewOutput(
        analysisProfile, analysisSurfaceId);
      this.analysisOutput = analysisOutput;
      displayOutput.on('error', this.previewErrorCallback);
      analysisOutput.on('error', this.previewErrorCallback);

      const session: camera.VideoSession =
        manager.createSession<camera.VideoSession>(camera.SceneMode.NORMAL_VIDEO);
      this.session = session;
      session.on('error', this.sessionErrorCallback);
      session.beginConfig();
      if (!session.canAddInput(input)) {
        throw new Error(DemoL10n.text("当前设备不允许添加选定相机输入"));
      }
      session.addInput(input);
      if (!session.canAddOutput(displayOutput)) {
        throw new Error(DemoL10n.text("当前设备不支持可见预览输出"));
      }
      session.addOutput(displayOutput);
      if (!session.canAddOutput(analysisOutput)) {
        throw new Error(DemoL10n.text("当前设备不支持预览与分析双路输出"));
      }
      session.addOutput(analysisOutput);
      await session.commitConfig();
      if (!this.canContinueStartup(token)) {
        return;
      }
      if (this.limitDisplayFrameRate) {
        this.applyOutputFrameRate(displayOutput, this.targetSessionFrameRate);
      }
      this.analysisOutputRateLimited = this.applyOutputFrameRate(
        analysisOutput, this.targetAnalysisFrameRate);
      // If CameraKit rejects the target rate, retain app throttling at that rate before copying pixels.
      // CameraKit 拒绝目标帧率时，在像素复制前保留同频率的应用侧兜底门禁。
      this.updateApplicationFrameInterval();
      // Add PreviewOutput and commit the Session first; some devices otherwise report GetPreviewRotation
      // session-is-null error 7400201.
      // PreviewOutput 必须先加入并提交 Session。部分真机会在提交前返回
      // "GetPreviewRotation ... session is nullptr"（7400201）。
      const displayRotation: number = display.getDefaultDisplaySync().rotation;
      const previewRotation: camera.ImageRotation = displayOutput.getPreviewRotation(displayRotation);
      displayOutput.setPreviewRotation(previewRotation, true);
      this.rotationDegrees = analysisOutput.getPreviewRotation(displayRotation);
      this.previewAspect = previewRotation === 90 || previewRotation === 270 ?
        displayProfile.size.height / displayProfile.size.width :
        displayProfile.size.width / displayProfile.size.height;
      await session.start();
      if (!this.canContinueStartup(token)) {
        return;
      }
      this.active = true;
      this.droppedFrames = 0;
      this.consecutiveFrameErrors = 0;
      this.lastFrameAt = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
      this.lastAnalysisFrameAt = -1;
      this.frameWatchdog = setInterval(() => {
        if (token === this.generation && this.active && this.frameTask === undefined &&
          this.consumerTask === undefined &&
          systemDateTime.getUptime(systemDateTime.TimeType.STARTUP) - this.lastFrameAt >= 8000) {
          this.failCamera(DemoL10n.text("相机未收到分析帧，请重试"));
        }
      }, 1000);
      this.callbacks.onCameraState(CameraPreviewState.RUNNING, this.frontCamera,
        `${this.settings.highResolution ? DemoL10n.text("高清") : DemoL10n.text("标准")} ${profileLabel} · ` +
        DemoL10n.text("相机会话 {0} fps{1} · ", [String(this.targetSessionFrameRate), String(this.analysisOutputRateLimited ? '' : DemoL10n.text("（应用节流）"))]) +
        `rotation ${this.rotationDegrees}° · NV21/BT.709 video`);
    } catch (error) {
      throw new Error(`CameraKit profile ${profileLabel} failed: ${error}`);
    }
  }

  async switchCamera(): Promise<void> {
    if (this.surfaceId.length === 0) {
      return;
    }
    await this.start(this.surfaceId, !this.frontCamera);
  }

  /**
   * Update the SDK input target and request the analysis rate without rebuilding the session; request
   * preview rate too only when preview throttling is enabled. If dynamic settings fail, throttle
   * analysis before pixel copying.
   *
   * 更新 SDK 输入目标并请求分析输出帧率；仅启用预览限频时同时请求预览帧率，不重建会话。
   * 设备拒绝动态设置时，分析流仍在像素复制前按目标频率降帧。
   */
  setSessionFrameRate(targetFps: number, analysisFps: number = targetFps): void {
    if (!Number.isInteger(targetFps) || targetFps <= 0 || targetFps > this.sessionFrameRate) {
      throw new Error('Target frame rate must be a positive integer within the session frame rate');
    }
    if (!Number.isInteger(analysisFps) || analysisFps <= 0 || analysisFps > targetFps) {
      throw new Error('Analysis frame rate must be a positive integer within the preview frame rate');
    }
    if (this.targetSessionFrameRate === targetFps && this.targetAnalysisFrameRate === analysisFps) return;
    this.targetSessionFrameRate = targetFps;
    this.targetAnalysisFrameRate = analysisFps;
    if (this.limitDisplayFrameRate && this.displayOutput !== undefined) {
      this.applyOutputFrameRate(this.displayOutput, targetFps);
    }
    this.analysisOutputRateLimited = this.analysisOutput !== undefined &&
      this.applyOutputFrameRate(this.analysisOutput, analysisFps);
    this.updateApplicationFrameInterval();
    this.lastAnalysisFrameAt = -1;
  }

  /**
   * Pause only analysis pixel copying and business callbacks, retaining visible preview and the
   * CameraKit session.
   *
   * 只暂停分析帧的像素拷贝和业务回调，保持可见预览和 CameraKit 会话。
   */
  pauseAnalysis(): void {
    this.analysisPaused = true;
    this.pendingFrame = undefined;
  }

  /**
   * Resume analysis and admit the first frame immediately without reusing the pre-pause throttle
   * timestamp.
   *
   * 恢复分析帧；首帧立即通过，不继承暂停前的节流时间戳。
   */
  resumeAnalysis(): void {
    this.analysisPaused = false;
    this.lastAnalysisFrameAt = -1;
  }

  private updateApplicationFrameInterval(): void {
    // Separate preview/analysis targets retain the SDK gate even when the driver accepts both requests.
    // 预览与分析分开限频时，即使驱动接受请求，也保留 SDK 输入门禁，防止双输出共享帧率。
    this.applicationFrameInterval = this.analysisOutputRateLimited &&
      this.targetAnalysisFrameRate === this.targetSessionFrameRate ?
      0 : 1000 / this.targetAnalysisFrameRate - 2;
  }

  async stop(): Promise<void> {
    ++this.generation;
    this.active = false;
    const task: Promise<void> = CameraPreviewController.lifecycleTask.then(() => this.stopInternal());
    CameraPreviewController.lifecycleTask = task.catch(() => {});
    await task;
  }

  private async stopInternal(): Promise<void> {
    ++this.attempt;
    this.startupError = undefined;
    this.active = false;
    this.pendingFrame = undefined;
    if (this.frameWatchdog >= 0) clearInterval(this.frameWatchdog);
    this.frameWatchdog = -1;
    const receiver: image.ImageReceiver | undefined = this.receiver;
    if (receiver !== undefined) {
      try {
        receiver.off('imageArrival', this.arrivalCallback);
      } catch (_) {
      }
    }
    const session: camera.VideoSession | undefined = this.session;
    this.unregisterErrorCallbacks();
    this.arrivalCallback = undefined;
    this.inputErrorCallback = undefined;
    this.sessionErrorCallback = undefined;
    this.previewErrorCallback = undefined;
    if (session !== undefined) {
      try {
        await session.stop();
      } catch (_) {
      }
    }
    const frameTask: Promise<void> | undefined = this.frameTask;
    if (frameTask !== undefined) {
      try {
        await frameTask;
      } catch (_) {
      }
    }
    const consumerTask: Promise<void> | undefined = this.consumerTask;
    if (consumerTask !== undefined) {
      try {
        await consumerTask;
      } catch (_) {
      }
    }
    if (session !== undefined) {
      try {
        await session.release();
      } catch (_) {
      }
    }
    await this.releaseOutput(this.displayOutput);
    await this.releaseOutput(this.analysisOutput);
    const input: camera.CameraInput | undefined = this.cameraInput;
    if (input !== undefined) {
      try {
        await input.close();
      } catch (_) {
      }
    }
    if (receiver !== undefined) {
      try {
        await receiver.release();
      } catch (_) {
      }
    }
    this.session = undefined;
    this.displayOutput = undefined;
    this.analysisOutput = undefined;
    this.analysisOutputRateLimited = false;
    this.cameraInput = undefined;
    this.cameraDevice = undefined;
    this.receiver = undefined;
    this.frameTask = undefined;
    this.consumerTask = undefined;
    this.lastAnalysisFrameAt = -1;
  }

  private async requestPermission(): Promise<boolean> {
    try {
      const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result = await manager.requestPermissionsFromUser(this.context, [CAMERA_PERMISSION]);
      return result.authResults.length === 1 &&
        result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (_) {
      return false;
    }
  }

  private selectCamera(devices: Array<camera.CameraDevice>, preferFront: boolean): camera.CameraDevice {
    if (devices.length === 0) {
      throw new Error(DemoL10n.text("没有可用相机"));
    }
    const preferred: camera.CameraPosition = preferFront ?
      camera.CameraPosition.CAMERA_POSITION_FRONT : camera.CameraPosition.CAMERA_POSITION_BACK;
    for (const device of devices) {
      if (device.cameraPosition === preferred) {
        return device;
      }
    }
    return devices[0];
  }

  private startFrameTask(): void {
    const token: number = this.generation;
    const task: Promise<void> = this.consumeLatestFrame(token);
    this.frameTask = task;
    task.then(() => this.completeFrameTask(task), () => this.completeFrameTask(task));
  }

  private completeFrameTask(task: Promise<void>): void {
    if (this.frameTask !== task) {
      return;
    }
    this.frameTask = undefined;
  }

  private async consumeLatestFrame(token: number): Promise<void> {
    const readStartedAt: number = DEBUG ? systemDateTime.getUptime(systemDateTime.TimeType.STARTUP) : 0;
    try {
      const receiver: image.ImageReceiver | undefined = this.receiver;
      if (receiver === undefined || token !== this.generation || !this.active) {
        return;
      }
      // Read one buffer per imageArrival; on some devices readLatestImage additionally scans/discards the
      // queue and repeatedly logs no-dirty-buffer diagnostics.
      // 每个 imageArrival 只取一个缓冲。readLatestImage 会在部分真机上额外扫描并
      // 丢弃队列，持续产生 “no dirty buffer ready” 诊断日志。
      const source: image.Image = await receiver.readNextImage();
      if (source === undefined) return;
      const readFinishedAt: number = DEBUG ? systemDateTime.getUptime(systemDateTime.TimeType.STARTUP) : 0;
      let frame: Yuv420Frame | undefined = undefined;
      let copiedAt: number = readFinishedAt;
      try {
        if (token !== this.generation || !this.active || this.analysisPaused) {
          return;
        }
        // Match CameraX KEEP_ONLY_LATEST: retain only the newest pending frame during inference and consume it
        // immediately afterward, avoiding an extra camera interval of waiting.
        // 与 CameraX KEEP_ONLY_LATEST 一致：推理忙时仅保留一份最新帧，覆盖中间帧。
        // 推理完成立即消费它，避免丢弃所有到帧后再空等一个相机周期。
        const now: number = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
        if (this.lastAnalysisFrameAt < 0 ||
          now - this.lastAnalysisFrameAt >= this.applicationFrameInterval) {
          frame = await CameraFrameAdapter.read(source, this.rotationDegrees, this.frontCamera);
          copiedAt = DEBUG ? systemDateTime.getUptime(systemDateTime.TimeType.STARTUP) : 0;
          this.lastAnalysisFrameAt = now;
        } else {
          this.recordDroppedFrame();
        }
      } finally {
        // The adapter copied Y/U/V data; release camera buffers before inference continues.
        // 适配器已复制 Y/U/V 数据，推理期间无需继续占用相机缓冲区。
        await source.release();
      }
      this.lastFrameAt = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
      if (frame === undefined || token !== this.generation || !this.active) return;
      if (DEBUG && this.frameTimingSamples < 12) {
        hilog.info(0xFF00, 'HiFaceCamera',
          'Camera timing read=%{public}dms copy=%{public}dms release=%{public}dms',
          readFinishedAt - readStartedAt, copiedAt - readFinishedAt, this.lastFrameAt - copiedAt);
        this.frameTimingSamples++;
      }
      if (this.consumerTask !== undefined) {
        if (this.pendingFrame !== undefined) this.recordDroppedFrame();
        this.pendingFrame = frame;
      } else {
        this.startConsumerTask(frame, token);
      }
    } catch (error) {
      this.recordFrameError(error, token);
    }
  }

  private startConsumerTask(frame: Yuv420Frame, token: number): void {
    let task: Promise<void>;
    try {
      task = this.callbacks.onFrame(frame);
    } catch (error) {
      this.recordFrameError(error, token);
      return;
    }
    this.consumerTask = task;
    task.then(() => this.completeConsumerTask(task, token),
      (error: Error) => this.failConsumerTask(task, token, error));
  }

  private completeConsumerTask(task: Promise<void>, token: number): void {
    if (this.consumerTask !== task) return;
    this.consumerTask = undefined;
    if (token === this.generation && this.active) {
      this.consecutiveFrameErrors = 0;
      this.consumePendingFrame(token);
    }
  }

  private failConsumerTask(task: Promise<void>, token: number, error: Error): void {
    if (this.consumerTask !== task) return;
    this.consumerTask = undefined;
    this.recordFrameError(error, token);
    this.consumePendingFrame(token);
  }

  private consumePendingFrame(token: number): void {
    if (token !== this.generation || !this.active || this.consumerTask !== undefined) return;
    const frame: Yuv420Frame | undefined = this.pendingFrame;
    this.pendingFrame = undefined;
    if (frame !== undefined) this.startConsumerTask(frame, token);
  }

  private recordDroppedFrame(): void {
    this.droppedFrames += 1;
    try { this.callbacks.onFrameDropped(this.droppedFrames); } catch (_) {}
  }

  private recordFrameError(error: Object, token: number): void {
    if (token !== this.generation || !this.active) return;
    this.consecutiveFrameErrors += 1;
    if (this.consecutiveFrameErrors >= 3) {
      this.failCamera(DemoL10n.text("相机分析帧不可用，请重试"));
    } else {
      try { this.callbacks.onFrameError(DemoL10n.text("处理相机分析帧失败：{0}", [String(error)])); } catch (_) {}
    }
  }

  private async releaseOutput(output: camera.PreviewOutput | undefined): Promise<void> {
    if (output === undefined) {
      return;
    }
    try {
      await output.release();
    } catch (_) {
    }
  }

  private applyOutputFrameRate(output: camera.PreviewOutput, targetFps: number): boolean {
    try {
      const selected: CameraFrameRateRange | undefined =
        CameraFrameRatePolicy.select(output.getSupportedFrameRates(), targetFps);
      if (selected === undefined) return false;
      output.setFrameRate(selected.min, selected.max);
      // A successful setting does not guarantee the target rate; hardware fallback to 10 FPS still needs
      // throttling to 5 FPS before copying.
      // 设置成功不等于达到目标；例如硬件 10 FPS 回退必须继续在复制前限到 5 FPS。
      return selected.max <= targetFps;
    } catch (_) {
      // Some devices reject dynamic or dual-output frame-rate changes; retain equivalent latest-frame
      // throttling in the app.
      // 个别设备会拒绝动态或双路帧率设置；应用侧仍保留同样的最新帧节流。
      return false;
    }
  }

  private unregisterErrorCallbacks(): void {
    const input: camera.CameraInput | undefined = this.cameraInput;
    const device: camera.CameraDevice | undefined = this.cameraDevice;
    if (input !== undefined && device !== undefined) {
      try {
        input.off('error', device, this.inputErrorCallback);
      } catch (_) {
      }
    }
    try {
      this.session?.off('error', this.sessionErrorCallback);
    } catch (_) {
    }
    try {
      this.displayOutput?.off('error', this.previewErrorCallback);
    } catch (_) {
    }
    try {
      this.analysisOutput?.off('error', this.previewErrorCallback);
    } catch (_) {
    }
  }

  private failCamera(message: string): void {
    if (!this.active) return;
    // Queue cleanup and invalidate old requests before notifying the screen, allowing immediate retry from
    // the error callback.
    // 先排队释放并使旧请求失效，再通知页面，允许错误回调立即发起重试。
    this.stop();
    try { this.callbacks.onCameraError(message); } catch (_) {}
  }

  private canContinueStartup(token: number): boolean {
    if (token !== this.generation) return false;
    if (this.startupError !== undefined) throw new Error(this.startupError);
    return true;
  }

  private handleRuntimeError(label: string, error: BusinessError, token: number, attempt: number): void {
    if (token !== this.generation || attempt !== this.attempt) return;
    hilog.error(0xFF00, 'HiFaceDemo', 'Camera error: %{public}s code=%{public}d message=%{public}s', label, error.code, error.message);
    const message: string = `${label}: ${error.code}`;
    if (this.active) {
      this.failCamera(message);
    } else if (this.startupError === undefined) {
      // Preserve events received before open/commitConfig/start finishes, and never concurrently release
      // resources still being created.
      // open/commitConfig/start 尚未完成时的事件不能丢弃，也不能并发释放正在创建的资源。
      this.startupError = message;
    }
  }
}
