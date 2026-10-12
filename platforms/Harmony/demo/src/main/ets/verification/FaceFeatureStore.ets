import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { FaceFeatureFormat } from 'hiface';

const STORE_NAME: string = 'hiface_verification_references';
// HF1 不携带模型身份；保留旧快照，只读取和更新当前空间的参考特征。
const ENCRYPTED_REFERENCES_KEY: string = `encrypted_references_v1:${FaceFeatureFormat.FEATURE_SPACE_ID}`;
const KEY_ALIAS: string = 'hiface.demo.verification.references.v1';
const ENVELOPE_VERSION: number = 1;
const NONCE_LENGTH: number = 12;
const GCM_TAG_LENGTH: number = 16;
const FEATURE_LENGTH: number = 604;
const MAX_FACE_ID_LENGTH: number = 64;
const MAX_REFERENCE_COUNT: number = 5000;
const PAYLOAD_HEADER_LENGTH: number = 8;
const PAYLOAD_MAGIC: ReadonlyArray<number> = [0x48, 0x46, 0x52, 0x31]; // HFR1
const ASSOCIATED_DATA: Uint8Array = new Uint8Array([
  0x48, 0x69, 0x46, 0x61, 0x63, 0x65, 0x2d, 0x31, 0x3a, 0x31
]); // HiFace-1:1

/** Demo 的 1:1 验证基准；HF1 不是哈希，持久化必须经过认证加密。 */
export class FaceReference {
  readonly faceId: string;
  readonly feature: string;

  constructor(faceId: string, feature: string) {
    this.faceId = faceId;
    this.feature = feature;
  }
}

/**
 * Demo 专用的 1:1 基准存储：HUKS 持有不可导出的 AES 密钥，Preferences 只保存 AES-GCM 密文。
 * 整份快照使用单一随机 nonce 和单一 Preferences 值提交，避免 ID 与特征分开写入造成半更新状态。
 */
export class FaceFeatureStore {
  private references: FaceReference[] = [];
  private loaded: boolean = false;
  private generation: number = 0;
  private operations: Promise<void> = Promise.resolve();
  private readonly encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: true });

  load(context: common.UIAbilityContext): Promise<FaceReference[]> {
    return this.enqueue<FaceReference[]>(() => this.loadSnapshot(context));
  }

  private async loadSnapshot(context: common.UIAbilityContext): Promise<FaceReference[]> {
    this.references = [];
    this.loaded = false;
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    const stored: preferences.ValueType = await store.get(
      ENCRYPTED_REFERENCES_KEY, new Uint8Array(0));
    if (!(stored instanceof Uint8Array)) {
      throw new Error('Encrypted face reference snapshot has an invalid type');
    }
    if (stored.byteLength === 0) {
      this.references = [];
      this.loaded = true;
      return [];
    }
    if (stored.byteLength <= 1 + NONCE_LENGTH + GCM_TAG_LENGTH || stored[0] !== ENVELOPE_VERSION) {
      throw new Error('Encrypted face reference snapshot has an invalid envelope');
    }
    if (!(await huks.hasKeyItem(KEY_ALIAS, { properties: [] }))) {
      throw new Error('Face reference encryption key is unavailable');
    }
    const nonce: Uint8Array = stored.slice(1, 1 + NONCE_LENGTH);
    const ciphertext: Uint8Array = stored.slice(1 + NONCE_LENGTH);
    const plaintext: Uint8Array = await this.decrypt(ciphertext, nonce);
    try {
      this.references = this.decode(plaintext);
      this.loaded = true;
      return Array.from(this.references);
    } finally {
      plaintext.fill(0);
    }
  }

  /** 完成 HUKS 加密及 Preferences flush 后才更新内存快照。 */
  save(context: common.UIAbilityContext, faceId: string,
    feature: string): Promise<FaceReference[]> {
    return this.enqueue<FaceReference[]>(() => this.saveSnapshot(context, faceId, feature));
  }

  private async saveSnapshot(context: common.UIAbilityContext, faceId: string,
    feature: string): Promise<FaceReference[]> {
    if (!this.loaded) await this.loadSnapshot(context);
    const normalizedId: string = faceId.trim();
    if (normalizedId.length === 0 || normalizedId.length > MAX_FACE_ID_LENGTH) {
      throw new Error(`Face ID must contain 1...${MAX_FACE_ID_LENGTH} characters`);
    }
    if (feature.length !== FEATURE_LENGTH || !feature.startsWith('HF1:')) {
      throw new Error('Feature must be a 604-character HF1 value');
    }
    const next: FaceReference[] = this.references
      .filter((entry: FaceReference): boolean => entry.faceId !== normalizedId)
      .concat([new FaceReference(normalizedId, feature)])
      .sort((left: FaceReference, right: FaceReference): number =>
        left.faceId.localeCompare(right.faceId));
    if (next.length > MAX_REFERENCE_COUNT) {
      throw new Error(`At most ${MAX_REFERENCE_COUNT} verification references may be stored`);
    }
    const plaintext: Uint8Array = this.encode(next);
    try {
      await this.ensureKey();
      const nonce: Uint8Array = (await cryptoFramework.createRandom().generateRandom(NONCE_LENGTH)).data;
      const ciphertext: Uint8Array = await this.encrypt(plaintext, nonce);
      if (ciphertext.byteLength <= GCM_TAG_LENGTH) {
        throw new Error('HUKS returned an invalid AES-GCM result');
      }
      const envelope: Uint8Array = new Uint8Array(1 + nonce.byteLength + ciphertext.byteLength);
      envelope[0] = ENVELOPE_VERSION;
      envelope.set(nonce, 1);
      envelope.set(ciphertext, 1 + nonce.byteLength);
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      await store.put(ENCRYPTED_REFERENCES_KEY, envelope);
      await store.flush();
      this.references = next;
      return Array.from(this.references);
    } finally {
      plaintext.fill(0);
    }
  }

  /** 页面销毁时只清除内存副本；加密快照供下次应用启动恢复。 */
  clear(): void {
    this.generation += 1;
    this.references = [];
    this.loaded = false;
  }

  /** 用户明确确认恢复时删除不可读取的密文快照；HUKS 密钥保留并可继续安全复用。 */
  reset(context: common.UIAbilityContext): Promise<void> {
    return this.enqueue<void>(() => this.resetSnapshot(context));
  }

  private async resetSnapshot(context: common.UIAbilityContext): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.delete(ENCRYPTED_REFERENCES_KEY);
    await store.flush();
    this.references = [];
    this.loaded = true;
  }

  /** 串行读改写，避免两个保存覆盖彼此；页面销毁后不能恢复旧明文快照。 */
  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const generation: number = this.generation;
    const result: Promise<T> = this.operations.then(async (): Promise<T> => {
      if (generation !== this.generation) throw new Error('Face reference operation was cancelled');
      try {
        const value: T = await operation();
        if (generation !== this.generation) throw new Error('Face reference operation was cancelled');
        return value;
      } finally {
        if (generation !== this.generation) {
          this.references = [];
          this.loaded = false;
        }
      }
    });
    this.operations = result.then((): void => {}, (): void => {});
    return result;
  }

  private async ensureKey(): Promise<void> {
    const empty: huks.HuksOptions = { properties: [] };
    if (await huks.hasKeyItem(KEY_ALIAS, empty)) return;
    const options: huks.HuksOptions = {
      properties: [{
        tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
        value: huks.HuksKeyAlg.HUKS_ALG_AES
      }, {
        tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
        value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
      }, {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
          huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
      }]
    };
    try {
      await huks.generateKeyItem(KEY_ALIAS, options);
    } catch (error) {
      // 两个保存操作同时首次进入时允许另一个操作已经生成同名密钥。
      if (!(await huks.hasKeyItem(KEY_ALIAS, empty))) {
        throw new Error(`Unable to generate the face reference encryption key: ${error}`);
      }
    }
  }

  private encrypt(plaintext: Uint8Array, nonce: Uint8Array): Promise<Uint8Array> {
    return this.finishCipher(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT,
      plaintext, nonce, undefined);
  }

  private decrypt(ciphertextWithTag: Uint8Array, nonce: Uint8Array): Promise<Uint8Array> {
    if (ciphertextWithTag.byteLength <= GCM_TAG_LENGTH) {
      return Promise.reject(new Error('Encrypted face reference payload is truncated'));
    }
    const ciphertext: Uint8Array = ciphertextWithTag.slice(
      0, ciphertextWithTag.byteLength - GCM_TAG_LENGTH);
    const tag: Uint8Array = ciphertextWithTag.slice(
      ciphertextWithTag.byteLength - GCM_TAG_LENGTH);
    return this.finishCipher(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT,
      ciphertext, nonce, tag);
  }

  private async finishCipher(purpose: huks.HuksKeyPurpose, input: Uint8Array,
    nonce: Uint8Array, tag: Uint8Array | undefined): Promise<Uint8Array> {
    const properties: huks.HuksParam[] = [{
      tag: huks.HuksTag.HUKS_TAG_ALGORITHM,
      value: huks.HuksKeyAlg.HUKS_ALG_AES
    }, {
      tag: huks.HuksTag.HUKS_TAG_KEY_SIZE,
      value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256
    }, {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: purpose
    }, {
      tag: huks.HuksTag.HUKS_TAG_PADDING,
      value: huks.HuksKeyPadding.HUKS_PADDING_NONE
    }, {
      tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE,
      value: huks.HuksCipherMode.HUKS_MODE_GCM
    }, {
      tag: huks.HuksTag.HUKS_TAG_NONCE,
      value: nonce
    }, {
      tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA,
      value: ASSOCIATED_DATA
    }];
    if (tag !== undefined) {
      properties.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag });
    }
    const options: huks.HuksOptions = { properties: properties, inData: input };
    let handle: number | undefined = undefined;
    try {
      handle = (await huks.initSession(KEY_ALIAS, options)).handle;
      const result: huks.HuksReturnResult = await huks.finishSession(handle, options);
      if (result.outData === undefined) throw new Error('HUKS returned no cipher output');
      return result.outData;
    } catch (error) {
      if (handle !== undefined) {
        try { await huks.abortSession(handle, { properties: [] }); } catch (_) {}
      }
      throw new Error(`HUKS AES-GCM operation failed: ${error}`);
    }
  }

  private encode(references: ReadonlyArray<FaceReference>): Uint8Array {
    const ids: Uint8Array[] = [];
    let length: number = PAYLOAD_HEADER_LENGTH;
    references.forEach((entry: FaceReference): void => {
      const id: Uint8Array = this.encoder.encodeInto(entry.faceId);
      if (id.byteLength === 0 || id.byteLength > 0xFFFF) {
        throw new Error('Face ID UTF-8 representation is invalid');
      }
      ids.push(id);
      length += 2 + id.byteLength + FEATURE_LENGTH;
    });
    const output: Uint8Array = new Uint8Array(length);
    output.set(PAYLOAD_MAGIC, 0);
    const view: DataView = new DataView(output.buffer);
    view.setUint32(4, references.length, false);
    let offset: number = PAYLOAD_HEADER_LENGTH;
    references.forEach((entry: FaceReference, index: number): void => {
      const id: Uint8Array = ids[index];
      view.setUint16(offset, id.byteLength, false);
      offset += 2;
      output.set(id, offset);
      offset += id.byteLength;
      const feature: Uint8Array = this.encoder.encodeInto(entry.feature);
      if (feature.byteLength !== FEATURE_LENGTH) {
        throw new Error('Feature UTF-8 representation is invalid');
      }
      output.set(feature, offset);
      feature.fill(0);
      offset += FEATURE_LENGTH;
    });
    ids.forEach((id: Uint8Array): void => { id.fill(0); });
    return output;
  }

  private decode(payload: Uint8Array): FaceReference[] {
    if (payload.byteLength < PAYLOAD_HEADER_LENGTH ||
      PAYLOAD_MAGIC.some((value: number, index: number): boolean => payload[index] !== value)) {
      throw new Error('Decrypted face reference snapshot has an invalid header');
    }
    const view: DataView = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
    const count: number = view.getUint32(4, false);
    if (count > MAX_REFERENCE_COUNT) throw new Error('Face reference snapshot is too large');
    const result: FaceReference[] = [];
    const ids: Set<string> = new Set<string>();
    let offset: number = PAYLOAD_HEADER_LENGTH;
    for (let index: number = 0; index < count; index++) {
      if (offset + 2 > payload.byteLength) throw new Error('Face reference snapshot is truncated');
      const idLength: number = view.getUint16(offset, false);
      offset += 2;
      if (idLength === 0 || offset + idLength + FEATURE_LENGTH > payload.byteLength) {
        throw new Error('Face reference snapshot contains an invalid record');
      }
      const faceId: string = this.decoder.decodeToString(payload.subarray(offset, offset + idLength));
      offset += idLength;
      const feature: string = this.decoder.decodeToString(
        payload.subarray(offset, offset + FEATURE_LENGTH));
      offset += FEATURE_LENGTH;
      if (faceId.trim() !== faceId || faceId.length === 0 || faceId.length > MAX_FACE_ID_LENGTH ||
        ids.has(faceId) || feature.length !== FEATURE_LENGTH || !feature.startsWith('HF1:')) {
        throw new Error('Face reference snapshot contains invalid data');
      }
      ids.add(faceId);
      result.push(new FaceReference(faceId, feature));
    }
    if (offset !== payload.byteLength) throw new Error('Face reference snapshot has trailing data');
    return result.sort((left: FaceReference, right: FaceReference): number =>
      left.faceId.localeCompare(right.faceId));
  }
}
