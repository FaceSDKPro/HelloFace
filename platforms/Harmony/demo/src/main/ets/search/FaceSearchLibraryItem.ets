import { FaceSearchMetadata } from 'hiface';

/** 人脸库列表的轻量展示模型，不让 HF1 特征进入 ArkUI 响应式状态。 */
export class FaceSearchLibraryItem {
  readonly faceId: string;
  readonly group: string;
  readonly tag: string;

  constructor(entry: FaceSearchMetadata) {
    this.faceId = entry.faceId;
    this.group = entry.group;
    this.tag = entry.tag;
  }
}
