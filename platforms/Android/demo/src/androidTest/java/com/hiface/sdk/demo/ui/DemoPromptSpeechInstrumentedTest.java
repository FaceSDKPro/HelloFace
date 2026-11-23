package com.hiface.sdk.demo.ui;

import android.app.Instrumentation;
import android.content.Context;
import android.os.SystemClock;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import android.util.Log;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.File;
import java.io.FileInputStream;
import java.lang.reflect.Field;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

/** Uses the device's installed offline voices, including Samsung's ISO-3 locales. */
@RunWith(AndroidJUnit4.class)
public final class DemoPromptSpeechInstrumentedTest {
    private final Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();

    @Test public void chinesePromptPlaysAndProducesAudio() throws Exception {
        verifyAudio(Locale.CHINA, "请正对摄像头，缓慢转头");
    }

    @Test public void englishPromptPlaysAndProducesAudio() throws Exception {
        verifyAudio(Locale.US, "Please look at the camera and turn your head");
    }

    private void verifyAudio(Locale locale, String text) throws Exception {
        Context context = instrumentation.getTargetContext();
        DemoPromptSpeech[] speech = new DemoPromptSpeech[1];
        File output = File.createTempFile("tts-regression-", ".wav", context.getCacheDir());
        try {
            instrumentation.runOnMainSync(() -> {
                speech[0] = new DemoPromptSpeech(context, locale);
            });
            await(() -> Boolean.TRUE.equals(field(speech[0], "ready")), "offline voice was not selected");
            TextToSpeech engine = (TextToSpeech) field(speech[0], "engine");
            assertNotNull(engine);
            assertFalse(engine.getVoice().isNetworkConnectionRequired());
            Locale selected = engine.getVoice().getLocale();
            assertEquals(locale.getISO3Language(), selected.getISO3Language());
            assertTrue("voice uses another region", selected.getCountry().isEmpty()
                    || locale.getCountry().equals(selected.getCountry())
                    || locale.getISO3Country().equals(selected.getCountry()));
            Log.i("DemoPromptSpeechTest", "locale=" + locale + " engine=" + engine.getDefaultEngine()
                    + " voice=" + engine.getVoice().getName() + " voiceLocale=" + selected);
            CountDownLatch played = new CountDownLatch(1);
            CountDownLatch completed = new CountDownLatch(1);
            AtomicReference<String> error = new AtomicReference<>();
            engine.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                @Override public void onStart(String id) {}
                @Override public void onDone(String id) { complete(id); }
                @Override public void onError(String id) { onError(id, TextToSpeech.ERROR); }
                @Override public void onError(String id, int code) {
                    error.set("speech failed: " + code);
                    complete(id);
                }
                private void complete(String id) {
                    ("audio-check".equals(id) ? completed : played).countDown();
                }
            });
            // isSpeaking() is shared by all clients of the engine; await this utterance instead.
            instrumentation.runOnMainSync(() -> speech[0].speak(text));
            assertTrue("prompt did not finish", played.await(15, TimeUnit.SECONDS));
            assertNull(error.get());
            assertEquals(TextToSpeech.SUCCESS, engine.synthesizeToFile(text, null, output, "audio-check"));
            assertTrue("synthesis timed out", completed.await(15, TimeUnit.SECONDS));
            assertNull(error.get());
            assertTrue("no speech audio generated", output.length() > 1_000);
            int nonzeroBytes = 0;
            try (FileInputStream input = new FileInputStream(output)) {
                // Exclude the WAV header and ensure the payload contains more than silence.
                assertEquals(44, input.skip(44));
                int value;
                while ((value = input.read()) != -1) if (value != 0) nonzeroBytes++;
            }
            assertTrue("speech payload is silent", nonzeroBytes > 1_000);
        } finally {
            instrumentation.runOnMainSync(() -> { if (speech[0] != null) speech[0].close(); });
            output.delete();
        }
    }

    @Test public void finishReleasesEngineAndNextScreenStopsOldPrompt() throws Exception {
        Context context = instrumentation.getTargetContext();
        DemoPromptSpeech[] speech = new DemoPromptSpeech[2];
        try {
            for (int index = 0; index < 2; index++) {
                final int current = index;
                instrumentation.runOnMainSync(() -> {
                    speech[current] = new DemoPromptSpeech(context, Locale.US);
                    speech[current].speak("Please look at the camera and slowly turn your head from side to side.");
                });
                await(() -> field(speech[current], "startedId") != null, "prompt did not start");
                if (index == 1) assertNull(field(speech[0], "engine"));
                instrumentation.runOnMainSync(speech[current]::finish);
            }
            await(() -> field(speech[1], "engine") == null, "finishing prompt was not released");
        } finally {
            instrumentation.runOnMainSync(() -> {
                for (DemoPromptSpeech prompt : speech) if (prompt != null) prompt.close();
            });
        }
    }

    private interface Condition { boolean isTrue() throws Exception; }

    private void await(Condition condition, String message) throws Exception {
        long deadline = SystemClock.elapsedRealtime() + 15_000;
        while (SystemClock.elapsedRealtime() < deadline) {
            instrumentation.waitForIdleSync();
            if (condition.isTrue()) return;
            SystemClock.sleep(25);
        }
        fail(message);
    }

    private static Object field(DemoPromptSpeech speech, String name) throws Exception {
        Field field = DemoPromptSpeech.class.getDeclaredField(name);
        field.setAccessible(true);
        return field.get(speech);
    }
}
