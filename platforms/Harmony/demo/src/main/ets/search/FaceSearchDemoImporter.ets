import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  FaceSearchDatabase,
  FaceSearchFeatureEntry,
  FaceFeatureFormat,
  HiFaceError,
  HiFaceErrorCode,
  HiFaceResult,
  HiFaceSdk,
  RgbaImage
} from 'hiface';
import { FacePhotoPicker } from '../comparison/FacePhotoPicker';

const FEATURE_ASSET: string = 'face_search/features_10000.json';
const IMAGE_ASSET: string = 'face_search/images_1000.json';
const FEATURE_COUNT: number = 10000;
const IMAGE_COUNT: number = 1000;
const FEATURE_BATCH_SIZE: number = 1000;
const IMAGE_BATCH_SIZE: number = 100;
const IMAGE_PREFETCH_COUNT: number = 5;
const PARSE_YIELD_SIZE: number = 100;
const MAX_IMAGE_BYTES: number = 20 * 1024 * 1024;

interface DemoManifestHeader {
  schemaVersion: number;
  entryCount: number;
  featureFormat?: string;
  featureSpaceId?: string;
  imageFormat?: string;
}

interface FeatureJsonEntry {
  faceId: string;
  feature: string;
  group: string;
  tag: string;
  updateTimeMillis: number;
}

interface ImageJsonEntry {
  faceId: string;
  imageUrl: string;
  group: string;
  tag: string;
  updateTimeMillis: number;
}

interface DownloadedImage {
  token: number;
  entry: ImageJsonEntry;
  bytes?: ArrayBuffer;
}

interface PendingDownload {
  token: number;
  task: Promise<DownloadedImage>;
}

export class FaceSearchImportProgress {
  readonly processed: number;
  readonly total: number;
  readonly imported: number;
  readonly failed: number;

  constructor(processed: number, total: number, imported: number = 0, failed: number = 0) {
    this.processed = processed;
    this.total = total;
    this.imported = imported;
    this.failed = failed;
  }
}

export class FaceSearchImportSummary {
  readonly imported: number;
  readonly failed: number;
  readonly stopped: boolean;

  constructor(imported: number, failed: number, stopped: boolean = false) {
    this.imported = imported;
    this.failed = failed;
    this.stopped = stopped;
  }
}

/**
 * demo 模块 rawfile 专用批量导入器，数据不属于 SDK HAR。特征 JSON 逐对象解析并按 1000 条提交，
 * 避免同时创建 10000 个 ArkTS 对象；
 * 图片最多并发预取 5 张，按下载完成顺序逐张解码和提取特征，每 100 条写库；
 * 内存中始终只保留一张解码图，预取队列限制了压缩图片的占用。
 * images_1000.json 仅为演示清单，接入业务时替换为已获授权的人脸测试图片 URL，并使用 CDN 加速。
 */
export class FaceSearchDemoImporter {
  private readonly context: common.UIAbilityContext;
  private readonly sdk: HiFaceSdk;
  private readonly database: FaceSearchDatabase;
  private readonly active: () => boolean;
  private stopped: boolean = false;
  private stopRequested: boolean = false;
  private wakeStop: () => void = () => {};
  private readonly stopSignal: Promise<DownloadedImage | undefined>;
  private readonly requests: http.HttpRequest[] = [];

  constructor(context: common.UIAbilityContext, sdk: HiFaceSdk, database: FaceSearchDatabase,
    active: () => boolean) {
    this.context = context;
    this.sdk = sdk;
    this.database = database;
    this.active = active;
    this.stopSignal = new Promise<DownloadedImage | undefined>((resolve): void => {
      this.wakeStop = (): void => resolve(undefined);
    });
  }

  /** 页面取消时主动销毁 HTTP 请求，不等 20 秒超时；不能取消已提交的数据库批次。 */
  cancel(): void {
    this.stopped = true;
    this.requestStop();
  }

  /** 停止新输入；在途提取结束后，导入循环仍可保存尾批并返回统计。 */
  requestStop(): void {
    this.stopRequested = true;
    this.wakeStop();
    const requests: http.HttpRequest[] = this.requests.splice(0);
    requests.forEach((request: http.HttpRequest): void => request.destroy());
  }

  private isActive(): boolean { return !this.stopped && this.active(); }

  async importFeatures(progress: (value: FaceSearchImportProgress) => void):
    Promise<HiFaceResult<FaceSearchImportSummary>> {
    try {
      const reader: JsonEntryReader = await this.reader(FEATURE_ASSET, FEATURE_COUNT, 'HF1', true);
      let imported: number = 0;
      let batch: FaceSearchFeatureEntry[] = [];
      let processed: number = 0;
      let encoded: string | undefined = reader.next();
      while (encoded !== undefined) {
        if (!this.isActive()) return this.cancelled();
        if (this.stopRequested) break;
        const value: FeatureJsonEntry = JSON.parse(encoded) as FeatureJsonEntry;
        batch.push(new FaceSearchFeatureEntry(value.faceId, value.feature, value.updateTimeMillis,
          value.tag ?? '', value.group ?? ''));
        processed += 1;
        if (batch.length === FEATURE_BATCH_SIZE) {
          const saved: HiFaceResult<boolean> = await this.database.saveFeatures(batch);
          if (saved.isFailure()) return this.failure(saved.requireError());
          imported += batch.length;
          batch = [];
          progress(new FaceSearchImportProgress(processed, FEATURE_COUNT, imported));
        }
        if ((imported + batch.length) % PARSE_YIELD_SIZE === 0) await this.yieldToUi();
        encoded = reader.next();
      }
      if (batch.length > 0) {
        if (!this.isActive()) return this.cancelled();
        const saved: HiFaceResult<boolean> = await this.database.saveFeatures(batch);
        if (saved.isFailure()) return this.failure(saved.requireError());
        imported += batch.length;
        progress(new FaceSearchImportProgress(processed, FEATURE_COUNT, imported));
      }
      if (!this.stopRequested && imported !== FEATURE_COUNT) return this.invalid('Feature JSON entry count is invalid');
      progress(new FaceSearchImportProgress(processed, FEATURE_COUNT, imported));
      return HiFaceResult.success(new FaceSearchImportSummary(imported, 0,
        this.stopRequested && processed < FEATURE_COUNT));
    } catch (error) {
      return this.invalid(`Invalid bundled feature JSON: ${error}`);
    }
  }

  async importImages(progress: (value: FaceSearchImportProgress) => void):
    Promise<HiFaceResult<FaceSearchImportSummary>> {
    try {
      const reader: JsonEntryReader = await this.reader(IMAGE_ASSET, IMAGE_COUNT, 'url', false);
      let processed: number = 0;
      let imported: number = 0;
      let failed: number = 0;
      let batch: FaceSearchFeatureEntry[] = [];
      const pending: PendingDownload[] = [];
      let nextToken: number = 0;
      let encoded: string | undefined = reader.next();
      const prefetch = (): void => {
        while (encoded !== undefined && pending.length < IMAGE_PREFETCH_COUNT && this.isActive() && !this.stopRequested) {
          const value: ImageJsonEntry = JSON.parse(encoded) as ImageJsonEntry;
          const token: number = nextToken++;
          pending.push({ token: token, task: this.downloadImage(value, token) });
          encoded = reader.next();
        }
      };
      prefetch();
      while (pending.length > 0) {
        if (!this.isActive()) return this.cancelled();
        if (this.stopRequested) break;
        const tasks: Promise<DownloadedImage>[] = pending.map(
          (value: PendingDownload): Promise<DownloadedImage> => value.task);
        const downloaded: DownloadedImage | undefined = await Promise.race([...tasks, this.stopSignal]);
        if (!this.isActive()) return this.cancelled();
        if (this.stopRequested || downloaded === undefined) break;
        const completedIndex: number = pending.findIndex(
          (value: PendingDownload): boolean => value.token === downloaded.token);
        if (completedIndex < 0) throw new Error('Completed image download is not pending');
        pending.splice(completedIndex, 1);
        // 按完成顺序消费，并在解码前补位，避免慢请求阻塞后续图片。
        prefetch();
        if (downloaded.bytes === undefined) {
          failed += 1;
          processed += 1;
          // 每张结束立即更新；最后一张在尾批写库完成后报告，避免重复终值。
          if (processed < IMAGE_COUNT) progress(new FaceSearchImportProgress(processed, IMAGE_COUNT, imported, failed));
          continue;
        }
        try {
          const rgba: RgbaImage = await FacePhotoPicker.decode(downloaded.bytes);
          if (!this.isActive()) return this.cancelled();
          if (this.stopRequested) break;
          const feature: HiFaceResult<string> = await this.sdk.capture().extractFeature(rgba);
          if (!this.isActive()) return this.cancelled();
          if (feature.isSuccess()) {
            const value: ImageJsonEntry = downloaded.entry;
            batch.push(new FaceSearchFeatureEntry(value.faceId, feature.requireValue(), value.updateTimeMillis,
              value.tag ?? '', value.group ?? ''));
          } else {
            failed += 1;
          }
        } catch (_) {
          failed += 1;
        }
        processed += 1;
        if (!this.isActive()) return this.cancelled();
        if (this.stopRequested) break;
        if (batch.length >= IMAGE_BATCH_SIZE) {
          const saved: HiFaceResult<boolean> = await this.database.saveFeatures(batch);
          if (saved.isFailure()) return this.failure(saved.requireError());
          imported += batch.length;
          batch = [];
        }
        if (processed < IMAGE_COUNT) progress(new FaceSearchImportProgress(processed, IMAGE_COUNT, imported, failed));
      }
      if (batch.length > 0) {
        if (!this.isActive()) return this.cancelled();
        const saved: HiFaceResult<boolean> = await this.database.saveFeatures(batch);
        if (saved.isFailure()) return this.failure(saved.requireError());
        imported += batch.length;
      }
      if (!this.stopRequested && processed !== IMAGE_COUNT) return this.invalid('Image JSON entry count is invalid');
      progress(new FaceSearchImportProgress(processed, IMAGE_COUNT, imported, failed));
      return HiFaceResult.success(new FaceSearchImportSummary(imported, failed,
        this.stopRequested && processed < IMAGE_COUNT));
    } catch (error) {
      return this.invalid(`Invalid bundled image JSON: ${error}`);
    } finally {
      // 清单损坏或写库失败也必须关闭仍在预取的请求。
      this.cancel();
    }
  }

  private async reader(asset: string, expectedCount: number, format: string,
    feature: boolean): Promise<JsonEntryReader> {
    const bytes: Uint8Array = await this.context.resourceManager.getRawFileContent(asset);
    const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
    const reader = new JsonEntryReader(text);
    const header: DemoManifestHeader = reader.header();
    const actualFormat: string | undefined = feature ? header.featureFormat : header.imageFormat;
    if (header.schemaVersion !== 1 || header.entryCount !== expectedCount || actualFormat !== format) {
      throw new Error('Unsupported bundled import manifest');
    }
    if (feature && header.featureSpaceId !== FaceFeatureFormat.FEATURE_SPACE_ID) {
      throw new Error('Incompatible featureSpaceId');
    }
    return reader;
  }

  private async download(url: string): Promise<ArrayBuffer> {
    if (!url.startsWith('https://')) throw new Error('Only HTTPS image URLs are supported');
    const request: http.HttpRequest = http.createHttp();
    this.requests.push(request);
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 20000,
        maxLimit: MAX_IMAGE_BYTES,
        usingCache: true
      });
      if (response.responseCode < 200 || response.responseCode >= 300 ||
        response.resultType !== http.HttpDataType.ARRAY_BUFFER) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      const result: ArrayBuffer = response.result as ArrayBuffer;
      if (result.byteLength === 0 || result.byteLength > MAX_IMAGE_BYTES) {
        throw new Error('Image response size is invalid');
      }
      return result;
    } finally {
      const index: number = this.requests.indexOf(request);
      if (index >= 0) {
        this.requests.splice(index, 1);
        request.destroy();
      }
    }
  }

  /** 预取失败也正常结算 Promise，页面取消或提前结束时不会遗留未处理的 rejection。 */
  private async downloadImage(entry: ImageJsonEntry, token: number): Promise<DownloadedImage> {
    try {
      return { token: token, entry: entry, bytes: await this.download(entry.imageUrl) };
    } catch (error) {
      if (!this.isActive() || this.stopRequested) return { token: token, entry: entry };
      hilog.warn(0xFF00, 'HiFaceImport', 'Image download failed: error=%{private}s', String(error));
      return { token: token, entry: entry };
    }
  }

  private failure(error: HiFaceError): HiFaceResult<FaceSearchImportSummary> {
    return HiFaceResult.failure<FaceSearchImportSummary>(error.code, error.message);
  }

  private invalid(message: string): HiFaceResult<FaceSearchImportSummary> {
    return HiFaceResult.failure<FaceSearchImportSummary>(HiFaceErrorCode.INVALID_ARGUMENT, message);
  }

  private cancelled(): HiFaceResult<FaceSearchImportSummary> {
    return HiFaceResult.failure<FaceSearchImportSummary>(HiFaceErrorCode.CLOSED, 'Import cancelled');
  }

  /** 大 JSON 解析定期让出 ArkUI 事件循环，避免 1 万条对象连续解析造成页面假死。 */
  private yieldToUi(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 0);
    });
  }
}

/** 只保留当前对象文本的轻量读取器，适合 bundled 大数组 JSON。 */
class JsonEntryReader {
  private readonly source: string;
  private readonly headerValue: DemoManifestHeader;
  private cursor: number;

  constructor(source: string) {
    const marker: string = '"entries":[';
    const entriesAt: number = source.indexOf(marker);
    if (entriesAt < 1) throw new Error('Manifest has no entries array');
    this.source = source;
    this.headerValue = JSON.parse(`${source.substring(0, entriesAt)}"entries":[]}`) as DemoManifestHeader;
    this.cursor = entriesAt + marker.length;
  }

  header(): DemoManifestHeader {
    return this.headerValue;
  }

  next(): string | undefined {
    while (this.cursor < this.source.length &&
      (this.source[this.cursor] === ',' || this.isWhitespace(this.source[this.cursor]))) {
      this.cursor += 1;
    }
    if (this.cursor >= this.source.length || this.source[this.cursor] === ']') return undefined;
    if (this.source[this.cursor] !== '{') throw new Error('Entry must be an object');
    const start: number = this.cursor;
    let depth: number = 0;
    let quoted: boolean = false;
    let escaped: boolean = false;
    for (; this.cursor < this.source.length; this.cursor += 1) {
      const character: string = this.source[this.cursor];
      if (quoted) {
        if (escaped) escaped = false;
        else if (character === '\\') escaped = true;
        else if (character === '"') quoted = false;
      } else if (character === '"') {
        quoted = true;
      } else if (character === '{') {
        depth += 1;
      } else if (character === '}') {
        depth -= 1;
        if (depth === 0) {
          this.cursor += 1;
          return this.source.substring(start, this.cursor);
        }
      }
    }
    throw new Error('Unterminated entry object');
  }

  private isWhitespace(value: string): boolean {
    return value === ' ' || value === '\n' || value === '\r' || value === '\t';
  }
}
