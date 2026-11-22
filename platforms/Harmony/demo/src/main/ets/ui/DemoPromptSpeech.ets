import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { textToSpeech } from '@kit.CoreSpeechKit';

const PREEMPTIVE_PLAYBACK: Record<string, Object> = { 'queueMode': 1 };

/** Plays the latest prompt using the matching offline voice. */
export class DemoPromptSpeech {
  private engine: textToSpeech.TextToSpeechEngine | undefined = undefined;
  private lastPrompt: string | undefined = undefined;
  private closed: boolean;

  constructor(language: string) {
    this.closed = !canIUse('SystemCapability.AI.TextToSpeech');
    if (!this.closed) {
      this.initialize(language);
    }
  }

  speak(text: string | undefined): void {
    if (this.closed || text === undefined || text.length === 0 || text === this.lastPrompt) return;
    this.lastPrompt = text;
    this.speakLatest();
  }

  stop(): void {
    if (this.lastPrompt === undefined) return;
    this.lastPrompt = undefined;
    try { this.engine?.stop(); } catch (_) {}
  }

  close(): void {
    this.closed = true;
    this.stop();
    try { this.engine?.shutdown(); } catch (_) {}
    this.engine = undefined;
  }

  private async initialize(language: string): Promise<void> {
    let engine: textToSpeech.TextToSpeechEngine | undefined = undefined;
    try {
      engine = await textToSpeech.createEngine({
        language,
        person: language === 'zh-CN' ? 13 : 8,
        online: 1
      });
      if (!this.closed) {
        engine.setListener({
          onStart: () => {},
          onComplete: () => {},
          onStop: () => {},
          onError: (_requestId: string, errorCode: number) => {
            hilog.warn(0x0000, 'DemoPromptSpeech', 'TTS playback error: %{public}d', errorCode);
          }
        });
      }
    } catch (_) {
      if (!this.closed) {
        hilog.warn(0x0000, 'DemoPromptSpeech', 'Offline TTS unavailable for %{public}s', language);
      }
      this.close();
    }
    if (this.closed) {
      try { engine?.shutdown(); } catch (_) {}
      return;
    }
    this.engine = engine;
    // stop() clears pending text, including while the engine is starting.
    this.speakLatest();
  }

  private speakLatest(): void {
    if (this.engine === undefined || this.lastPrompt === undefined) return;
    try {
      this.engine.speak(this.lastPrompt, {
        requestId: util.generateRandomUUID(false).replace(/-/g, ''),
        extraParams: PREEMPTIVE_PLAYBACK
      });
    } catch (_) {
      this.stop();
      hilog.warn(0x0000, 'DemoPromptSpeech', 'TTS prompt could not be queued');
    }
  }
}
