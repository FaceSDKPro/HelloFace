import { FaceSearchBounds, FaceSearchEndReason, FaceSearchFace, FaceSearchFrame,
  FaceSearchResult } from 'hiface';

const STALE_FRAME_MILLIS: number = 1200;
const SCORE_HOLD_MILLIS: number = 1000;
const MAX_ASSOCIATION_GAP_MILLIS: number = 300;

export class FaceSearchOverlayVisual {
  readonly color: string;
  readonly label: string;
  readonly details: string;

  constructor(color: string, label: string, details: string) {
    this.color = color;
    this.label = label;
    this.details = details;
  }
}

const UNSCORED_VISUAL: FaceSearchOverlayVisual = new FaceSearchOverlayVisual('#A4B4C9', '', '');

class HeldSearchScore {
  readonly face: FaceSearchFace;
  readonly frameId: number;
  readonly deadline: number;
  readonly livenessScore: number | undefined;
  readonly spoofRejected: boolean;
  readonly finalResult: boolean;
  private readonly visualValue: FaceSearchOverlayVisual;

  constructor(face: FaceSearchFace, frameId: number, deadline: number,
    livenessScore: number | undefined = undefined, spoofRejected: boolean = false,
    finalResult: boolean = false) {
    this.face = face;
    this.frameId = frameId;
    this.deadline = deadline;
    this.livenessScore = livenessScore;
    this.spoofRejected = spoofRejected;
    this.finalResult = finalResult;
    this.visualValue = this.makeVisual();
  }

  completed(livenessScore: number | undefined, spoofRejected: boolean): HeldSearchScore {
    return new HeldSearchScore(this.face, this.frameId, this.deadline,
      livenessScore, spoofRejected, true);
  }

  visual(): FaceSearchOverlayVisual {
    return this.visualValue;
  }

  private makeVisual(): FaceSearchOverlayVisual {
    const matched: boolean = this.face.thresholdPassed && this.face.faceId !== undefined;
    const color: string = this.spoofRejected ? '#FF3C3C' : matched && !this.finalResult ?
      '#A4B4C9' : matched ? '#28DC64' : this.face.similarity === undefined ? '#A4B4C9' : '#FF3C3C';
    // 只有实际查库评分才能判定未匹配，低分仍保留在 SDK 结果中。
    const identity: string = matched ? this.face.faceId! :
      this.face.similarity !== undefined ? '未匹配' : '';
    const label: string = this.spoofRejected ?
      (identity.length === 0 ? '活体未通过' : `${identity} · 活体未通过`) : identity;
    const similarity: string = matched && this.face.similarity !== undefined ?
      `相似度 ${this.face.similarity.toFixed(3)}` : '';
    const liveness: string = this.livenessScore !== undefined ?
      `活体 ${this.livenessScore.toFixed(3)}` : '';
    const details: string = similarity.length === 0 ? liveness : liveness.length === 0 ?
      similarity : `${similarity} · ${liveness}`;
    return new FaceSearchOverlayVisual(color, label, details);
  }
}

/** 与 Android OverlayState 一致：坐标始终取最新帧，评分仅短时且无歧义地关联。 */
export class FaceSearchOverlayState {
  private displayed: FaceSearchFrame | undefined = undefined;
  private scores: Array<HeldSearchScore | undefined> =
    [undefined, undefined, undefined, undefined, undefined];
  private scratch: Array<HeldSearchScore | undefined> =
    [undefined, undefined, undefined, undefined, undefined];
  private scoredThisFrame: number = 0;
  private newestFrameId: number = -1;
  private rejectedThrough: number = -1;
  private completedThrough: number = -1;
  private frameDeadline: number = 0;
  private lastFrameAt: number = 0;
  private associationEnabled: boolean = true;

  frame(): FaceSearchFrame | undefined { return this.displayed; }

  visual(index: number): FaceSearchOverlayVisual {
    return this.scores[index]?.visual() ?? UNSCORED_VISUAL;
  }

  /** 当前画面或评分中最早的显示截止时间；无可见人脸时不安排刷新。 */
  expiresAt(): number {
    if (this.displayed === undefined || this.displayed.faces.length === 0) return 0;
    let deadline: number = this.frameDeadline;
    for (const score of this.scores) {
      if (score !== undefined) deadline = Math.min(deadline, score.deadline);
    }
    return deadline;
  }

  accept(frame: FaceSearchFrame, now: number): boolean {
    if (frame.frameId < this.newestFrameId) return false;
    const expired: boolean = this.expire(now);
    const sameFrame: boolean = frame.frameId === this.newestFrameId;
    // 已超时消失的画面不能被同一帧晚到的评分回调重新显示。
    if (sameFrame && this.displayed === undefined) return expired;
    const previous: FaceSearchFrame | undefined = this.displayed;
    const wasVisible: boolean = previous !== undefined && previous.faces.length > 0;
    const continuous: boolean = previous !== undefined &&
      frame.imageWidth === previous.imageWidth && frame.imageHeight === previous.imageHeight &&
      now - this.lastFrameAt <= MAX_ASSOCIATION_GAP_MILLIS;
    const next: Array<HeldSearchScore | undefined> = this.scratch;
    if (!sameFrame) this.scoredThisFrame = 0;
    for (let index: number = 0; index < frame.faces.length && index < next.length; index += 1) {
      const face: FaceSearchFace = frame.faces[index];
      const previousIndex: number = sameFrame ? index : continuous && this.associationEnabled &&
        previous !== undefined ? FaceSearchOverlayState.associate(frame.faces, index, previous.faces) : -1;
      const old: HeldSearchScore | undefined = previousIndex < 0 ? undefined : this.scores[previousIndex];
      if (face.similarity !== undefined && frame.frameId > this.rejectedThrough) {
        const bit: number = 1 << index;
        // 同一帧可能重复上报评分，不能借此无限延长标签显示时间。
        next[index] = (this.scoredThisFrame & bit) !== 0 ? old :
          new HeldSearchScore(face, frame.frameId, now + SCORE_HOLD_MILLIS);
        this.scoredThisFrame |= bit;
      } else {
        next[index] = old;
      }
    }
    if (!sameFrame) {
      this.frameDeadline = now + STALE_FRAME_MILLIS;
      this.lastFrameAt = now;
    }
    this.newestFrameId = frame.frameId;
    this.displayed = frame;
    this.scratch = this.scores;
    this.scores = next;
    for (let index: number = 0; index < this.scratch.length; index += 1) {
      this.scratch[index] = undefined;
    }
    // 空帧仍推进 frameId，防止晚到评分复活旧框，但无需不断提交空 Canvas 绘制。
    return expired || wasVisible || frame.faces.length > 0;
  }

  complete(result: FaceSearchResult, now: number): boolean {
    let changed: boolean = this.expire(now);
    const frame: FaceSearchFrame = result.frame;
    const frameId: number = frame.frameId;
    if (this.displayed === undefined || frameId > this.newestFrameId ||
      frameId <= this.completedThrough) return changed;
    this.completedThrough = frameId;
    const spoofRejected: boolean = result.endReason === FaceSearchEndReason.SPOOF_DETECTED;
    const matched: boolean = frame.faces.some((face: FaceSearchFace): boolean => face.thresholdPassed);
    if (spoofRejected) {
      // 保留本批身份分数用于展示，但旧身份和颜色不能继续关联到当前框。
      changed = this.rejectScoresThrough(frameId - 1) || changed;
      this.rejectedThrough = Math.max(this.rejectedThrough, frameId);
    } else if (!matched) {
      changed = this.rejectScoresThrough(result.endReason === FaceSearchEndReason.TIMEOUT ?
        frameId - 1 : frameId) || changed;
    }
    if (this.displayed === undefined || frame.imageWidth !== this.displayed.imageWidth ||
      frame.imageHeight !== this.displayed.imageHeight) return changed;
    let updated: boolean = false;
    for (let index: number = 0; index < this.scores.length; index += 1) {
      const score: HeldSearchScore | undefined = this.scores[index];
      if (score !== undefined && score.frameId === frameId) {
        this.scores[index] = score.completed(result.livenessScore, spoofRejected);
        updated = true;
        changed = true;
      }
    }
    // 活体拒绝可能在查库评分前结束；只允许单人同帧结果补到当前框。
    if (spoofRejected && !updated && frameId === this.newestFrameId &&
      (this.scoredThisFrame & 1) === 0 && frame.faces.length === 1 &&
      this.displayed.faces.length === 1) {
      this.scores[0] = new HeldSearchScore(frame.faces[0], frameId,
        now + SCORE_HOLD_MILLIS, result.livenessScore, true, true);
      this.scoredThisFrame |= 1;
      changed = true;
    }
    return changed;
  }

  setAssociationEnabled(enabled: boolean): boolean {
    if (this.associationEnabled === enabled) return false;
    this.associationEnabled = enabled;
    let changed: boolean = false;
    for (let index: number = 0; index < this.scores.length; index += 1) {
      if (this.scores[index] !== undefined && this.scores[index]!.frameId < this.newestFrameId) {
        this.scores[index] = undefined;
        changed = true;
      }
    }
    this.lastFrameAt = -MAX_ASSOCIATION_GAP_MILLIS - 1;
    return changed;
  }

  /** 当前失败轮次使旧评分失效，后续晚到的同帧评分也不能重新出现。 */
  rejectScores(): boolean {
    return this.rejectScoresThrough(this.newestFrameId);
  }

  private rejectScoresThrough(frameId: number): boolean {
    this.rejectedThrough = Math.max(this.rejectedThrough, frameId);
    let changed: boolean = false;
    for (let index: number = 0; index < this.scores.length; index += 1) {
      const score: HeldSearchScore | undefined = this.scores[index];
      if (score !== undefined && score.frameId <= this.rejectedThrough) {
        this.scores[index] = undefined;
        changed = true;
      }
    }
    return changed;
  }

  expire(now: number): boolean {
    if (this.displayed !== undefined && now >= this.frameDeadline) {
      const changed: boolean = this.displayed.faces.length > 0;
      this.displayed = undefined;
      for (let index: number = 0; index < this.scores.length; index += 1) {
        this.scores[index] = undefined;
      }
      this.frameDeadline = 0;
      return changed;
    }
    let changed: boolean = false;
    for (let index: number = 0; index < this.scores.length; index += 1) {
      const score: HeldSearchScore | undefined = this.scores[index];
      if (score !== undefined && now >= score.deadline) {
        this.scores[index] = undefined;
        changed = true;
      }
    }
    return changed;
  }

  clear(): void {
    this.displayed = undefined;
    for (let index: number = 0; index < this.scores.length; index += 1) {
      this.scores[index] = undefined;
      this.scratch[index] = undefined;
    }
    this.newestFrameId = -1;
    this.rejectedThrough = -1;
    this.completedThrough = -1;
    this.scoredThisFrame = 0;
    this.frameDeadline = 0;
    this.lastFrameAt = 0;
    this.associationEnabled = true;
  }

  private static associate(current: ReadonlyArray<FaceSearchFace>, index: number,
    previous: ReadonlyArray<FaceSearchFace>): number {
    const box = current[index].bounds;
    if (FaceSearchOverlayState.crowded(current, index)) return -1;
    let match: number = -1;
    for (let candidate: number = 0; candidate < previous.length; candidate += 1) {
      if (!FaceSearchOverlayState.near(box, previous[candidate].bounds)) continue;
      if (match !== -1) return -1;
      match = candidate;
    }
    if (match < 0 || FaceSearchOverlayState.crowded(previous, match)) return -1;
    for (let candidate: number = 0; candidate < current.length; candidate += 1) {
      if (candidate !== index && FaceSearchOverlayState.near(
        current[candidate].bounds, previous[match].bounds)) return -1;
    }
    return match;
  }

  private static crowded(faces: ReadonlyArray<FaceSearchFace>, index: number): boolean {
    for (let candidate: number = 0; candidate < faces.length; candidate += 1) {
      if (candidate !== index && FaceSearchOverlayState.overlap(
        faces[index].bounds, faces[candidate].bounds) > 0.25) return true;
    }
    return false;
  }

  private static near(a: FaceSearchBounds, b: FaceSearchBounds): boolean {
    const widthRatio: number = a.width / b.width;
    const heightRatio: number = a.height / b.height;
    const dx: number = (a.x + a.width / 2 - b.x - b.width / 2) / Math.min(a.width, b.width);
    const dy: number = (a.y + a.height / 2 - b.y - b.height / 2) / Math.min(a.height, b.height);
    return widthRatio >= 0.7 && widthRatio <= 1.4 && heightRatio >= 0.7 && heightRatio <= 1.4 &&
      dx * dx + dy * dy <= 0.09 && FaceSearchOverlayState.overlap(a, b) >= 0.5;
  }

  private static overlap(a: FaceSearchBounds, b: FaceSearchBounds): number {
    const width: number = Math.max(0, Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x));
    const height: number = Math.max(0, Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y));
    const intersection: number = width * height;
    return intersection / (a.width * a.height + b.width * b.height - intersection);
  }
}
