package com.hiface.sdk.demo.ui;

import android.content.Context;
import android.media.AudioAttributes;
import android.os.Handler;
import android.os.Looper;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.speech.tts.Voice;
import androidx.annotation.MainThread;
import androidx.annotation.Nullable;
import java.util.Locale;
import java.util.Set;

/** Speaks the latest prompt for one screen using an installed voice for its text locale. */
@MainThread
public final class DemoPromptSpeech {
    private static DemoPromptSpeech finishingPrompt;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Runnable releasePrompt = this::close;
    private final Locale locale;
    private TextToSpeech engine;
    private boolean ready;
    private String lastPrompt;
    private long utteranceId;
    private volatile String startedId;

    public DemoPromptSpeech(Context context, Locale locale) {
        stopFinishingPrompt();
        this.locale = locale;
        // Initialization can report an error before the constructor returns.
        engine = new TextToSpeech(context.getApplicationContext(), status -> main.post(() -> onInitialized(status)));
    }

    public void speak(@Nullable String text) {
        if (engine == null || text == null || text.isEmpty() || text.equals(lastPrompt)) {
            return;
        }
        lastPrompt = text;
        speakLatest();
    }

    public void stop() {
        if (ready && lastPrompt != null) {
            engine.stop();
        }
        lastPrompt = null;
    }

    public void close() {
        if (finishingPrompt == this) {
            finishingPrompt = null;
            main.removeCallbacks(releasePrompt);
        }
        stop();
        if (engine != null) {
            engine.shutdown();
            engine = null;
        }
        ready = false;
    }

    /** Keep the current audio through normal navigation for at most two seconds. */
    public void finish() {
        if (finishingPrompt == this) return;
        if (!ready || lastPrompt == null || !Long.toString(utteranceId).equals(startedId) || !engine.isSpeaking()) {
            close();
            return;
        }
        stopFinishingPrompt();
        finishingPrompt = this;
        main.postDelayed(releasePrompt, 2_000);
    }

    private static void stopFinishingPrompt() {
        if (finishingPrompt != null) finishingPrompt.close();
    }

    private void onInitialized(int status) {
        if (engine == null) {
            return;
        }
        Voice voice = status == TextToSpeech.SUCCESS ? offlineVoice() : null;
        if (voice == null || engine.setVoice(voice) != TextToSpeech.SUCCESS) {
            close();
            return;
        }
        engine.setAudioAttributes(new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build());
        engine.setOnUtteranceProgressListener(new UtteranceProgressListener() {
            @Override public void onStart(String id) { startedId = id; }
            @Override public void onDone(String id) {}
            @Override public void onError(String id) {}
        });
        ready = true;
        // Only the newest prompt survives engine startup. stop() clears it when the flow ends.
        speakLatest();
    }

    @Nullable
    private Voice offlineVoice() {
        Set<Voice> voices = engine.getVoices();
        if (voices == null) {
            return null;
        }
        // Demo locales are en-US/zh-CN; Samsung voices use ISO-3 codes (eng/USA, zho/CHN).
        String language = locale.getISO3Language();
        String country = locale.getISO3Country();
        Voice fallback = null;
        for (Voice voice : voices) {
            Locale voiceLocale = voice.getLocale();
            Set<String> features = voice.getFeatures();
            if ((!locale.getLanguage().equals(voiceLocale.getLanguage())
                    && !language.equals(voiceLocale.getLanguage())) || voice.isNetworkConnectionRequired()
                    || (features != null && features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED))) {
                continue;
            }
            if (locale.getCountry().equals(voiceLocale.getCountry()) || country.equals(voiceLocale.getCountry())) {
                return voice;
            }
            // Prefer a language-wide voice (for example Mandarin zh) over another region's voice.
            if (fallback == null || (voiceLocale.getCountry().isEmpty()
                    && !fallback.getLocale().getCountry().isEmpty())) {
                fallback = voice;
            }
        }
        return fallback;
    }

    private void speakLatest() {
        if (ready && lastPrompt != null
                && engine.speak(lastPrompt, TextToSpeech.QUEUE_FLUSH, null, Long.toString(++utteranceId))
                != TextToSpeech.SUCCESS) {
            stop();
        }
    }
}
