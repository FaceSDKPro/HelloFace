package com.hiface.sdk.demo.ui;

import android.content.Context;
import android.media.AudioAttributes;
import android.os.Handler;
import android.os.Looper;
import android.speech.tts.TextToSpeech;
import android.speech.tts.Voice;
import androidx.annotation.MainThread;
import androidx.annotation.Nullable;
import java.util.Locale;
import java.util.Set;

/** Speaks the latest prompt for one screen using an installed voice for its text locale. */
@MainThread
public final class DemoPromptSpeech {
    private final Locale locale;
    private TextToSpeech engine;
    private boolean ready;
    private String lastPrompt;
    private long utteranceId;

    public DemoPromptSpeech(Context context, Locale locale) {
        this.locale = locale;
        Handler main = new Handler(Looper.getMainLooper());
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
        stop();
        if (engine != null) {
            engine.shutdown();
            engine = null;
        }
        ready = false;
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
        Voice fallback = null;
        for (Voice voice : voices) {
            Locale voiceLocale = voice.getLocale();
            Set<String> features = voice.getFeatures();
            if (!locale.getLanguage().equals(voiceLocale.getLanguage()) || voice.isNetworkConnectionRequired()
                    || (features != null && features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED))) {
                continue;
            }
            if (locale.getCountry().equals(voiceLocale.getCountry())) {
                return voice;
            }
            if (fallback == null) {
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
