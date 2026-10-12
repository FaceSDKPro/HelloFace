package com.hiface.sdk.demo;

import android.content.Context;
import android.content.ContextWrapper;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.SystemClock;
import android.util.JsonReader;
import android.util.Log;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.frame.Yuv420Frame;
import com.hiface.sdk.frame.YuvColorMatrix;
import com.hiface.sdk.frame.YuvColorRange;
import com.hiface.sdk.search.*;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.Assert.*;

/** Device regression with SDK-owned models and local, untracked PNG/I420 fixtures. */
@RunWith(AndroidJUnit4.class)
public final class FeaturePipelineInstrumentedTest {
    @Test public void staticExtractionGalleryAndFrameSearchUseTheSameFeatureSpace() throws Exception {
        Context target = InstrumentationRegistry.getInstrumentation().getTargetContext();
        File directory = new File(target.getCacheDir(), "feature-regression-" + UUID.randomUUID());
        assertTrue(directory.mkdirs());
        Context isolated = new ContextWrapper(target) {
            @Override public Context getApplicationContext() { return this; }
            @Override public File getFilesDir() { return directory; }
        };
        HiFaceSdk sdk = HiFaceSdk.builder(isolated).build();
        FaceSearchDatabase database = null;
        try {
            List<FaceSearchFeatureEntry> records = readRecords(target);
            assertEquals(10000, records.size());
            database = HiFaceSdk.openSearchDatabase(isolated).requireValue();
            for (int start = 0; start < records.size(); start += 1000)
                database.saveFeatures(records.subList(start, start + 1000)).requireValue();
            assertEquals(10000L, database.count(null, null).requireValue().longValue());
            assertEquals(1L, database.count("group_test", null).requireValue().longValue());
            assertEquals(5000L, database.count("group_A", null).requireValue().longValue());
            assertEquals(4999L, database.count("group_B", null).requireValue().longValue());
            database.warmUp().requireValue();

            for (int index : new int[]{0, 5001, 9999}) {
                FaceSearchFeatureEntry expected = records.get(index);
                assertEquals(Integer.toString(index), expected.getFaceId());
                String actual;
                try (InputStream input = InstrumentationRegistry.getInstrumentation().getContext()
                        .getAssets().open("feature/" + index + ".png")) {
                    BitmapFactory.Options options = new BitmapFactory.Options();
                    options.inPreferredConfig = Bitmap.Config.ARGB_8888;
                    Bitmap image = BitmapFactory.decodeStream(input, null, options);
                    assertNotNull("Local image fixture", image);
                    try {
                        actual = sdk.capture().extractFeatureBlocking(image).requireValue();
                        assertEquals(actual, sdk.capture().extractFeatureBlocking(image).requireValue());
                    } finally { image.recycle(); }
                }
                float agreement = sdk.verification().compare(actual, expected.getFeature()).requireValue();
                assertTrue("Android/host feature agreement: " + agreement, agreement > .999f);
                List<FaceSearchMatch> matches = database.search(actual, FaceSearchConfig.defaultConfig()).requireValue();
                assertEquals(expected.getFaceId(), matches.get(0).getEntry().getFaceId());
                assertTrue(matches.get(0).getScore() > .999f);
                assertEquals(expected.getFeature(), database.get(expected.getFaceId()).requireValue().getFeature());
                Log.i("FeaturePipelineTest", "PNG " + index + " host agreement=" + agreement
                        + " top1=" + matches.get(0).getScore());
            }
            FaceSearchFeatureEntry first = records.get(0);
            StringBuilder invalid = new StringBuilder("HF1:");
            for (int i = 0; i < 600; i++) invalid.append('!');
            assertTrue(database.saveFeatures(Arrays.asList(
                    new FaceSearchFeatureEntry("0", first.getFeature(), 0, "", "changed"),
                    new FaceSearchFeatureEntry("never-created", invalid.toString(), 0, "", "test"))).isFailure());
            assertFalse(database.contains("never-created").requireValue());
            assertEquals("group_test", database.get("0").requireValue().getGroup());
            try {
                new FaceSearchFeatureEntry("legacy", first.getFeature(), 0, "", "", "hiface-feature-new-v1");
                fail("Old feature space must be rejected");
            } catch (IllegalArgumentException expected) { /* Required rejection. */ }
            database.close();
            database = HiFaceSdk.openSearchDatabase(isolated).requireValue();
            assertEquals(first.getFeature(), database.get("0").requireValue().getFeature());
            database.releaseMemory().requireValue();
            assertEquals("0", database.search(first.getFeature(), FaceSearchConfig.builder()
                    .group("group_test").build()).requireValue().get(0).getEntry().getFaceId());
            assertTrue(database.search(first.getFeature(), FaceSearchConfig.builder()
                    .group("absent").build()).requireValue().isEmpty());
            Yuv420Frame frame = readFrame();
            for (boolean live : new boolean[]{false, true}) {
                FaceSearchResult result = searchFrame(sdk, frame, live);
                assertFalse(result.getFrame().getFaces().isEmpty());
                FaceSearchFace face = result.getFrame().getFaces().get(0);
                assertEquals("0", face.getFaceId());
                assertTrue(face.isThresholdPassed());
                assertTrue(face.getSimilarity() > .95f);
                if (live) {
                    assertNotNull(result.getLivenessScore());
                    assertEquals(result.getLivenessScore() < .90f
                                    ? FaceSearchResult.EndReason.SPOOF_DETECTED : FaceSearchResult.EndReason.MATCH_FOUND,
                            result.getEndReason());
                } else {
                    assertNull(result.getLivenessScore());
                    assertEquals(FaceSearchResult.EndReason.MATCH_FOUND, result.getEndReason());
                }
                Log.i("FeaturePipelineTest", "I420 search live=" + live + " identity=" + face.getSimilarity()
                        + " liveness=" + result.getLivenessScore() + " reason=" + result.getEndReason());
            }
        } finally {
            if (database != null) database.close();
            sdk.close();
            delete(directory);
        }
    }

    private static FaceSearchResult searchFrame(HiFaceSdk sdk, Yuv420Frame frame, boolean live) throws Exception {
        AtomicReference<FaceSearchResult> result = new AtomicReference<>();
        AtomicReference<HiFaceError> error = new AtomicReference<>();
        CountDownLatch finished = new CountDownLatch(1);
        FaceSearchSession session = sdk.search().startCameraSearch(FaceSearchSessionConfig.builder()
                .needLiveness(live).searchTimeoutMillis(3000).build(), new FaceSearchListener() {
            @Override public void onFrame(FaceSearchFrame value) {}
            @Override public void onProgress(FaceSearchProgress value) {}
            @Override public void onResult(FaceSearchResult value) { result.set(value); finished.countDown(); }
            @Override public void onError(HiFaceError value) { error.set(value); finished.countDown(); }
        });
        try {
            long deadline = SystemClock.uptimeMillis() + 10000;
            while (finished.getCount() != 0 && SystemClock.uptimeMillis() < deadline) {
                sdk.processFrame(frame);
                Thread.sleep(110);
            }
            assertNull("Search error: " + error.get(), error.get());
            assertNotNull("Search timed out before delivering a result", result.get());
            return result.get();
        } finally { session.close(); }
    }

    private static Yuv420Frame readFrame() throws Exception {
        byte[] data;
        try (InputStream input = InstrumentationRegistry.getInstrumentation().getContext().getAssets().open("feature/0.i420")) {
            java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream();
            byte[] buffer = new byte[8192]; int count;
            while ((count = input.read(buffer)) >= 0) output.write(buffer, 0, count);
            data = output.toByteArray();
        }
        int pixels = 332 * 332;
        assertEquals(pixels * 3 / 2, data.length);
        ByteBuffer y = ByteBuffer.allocateDirect(pixels), u = ByteBuffer.allocateDirect(pixels / 4),
                v = ByteBuffer.allocateDirect(pixels / 4);
        y.put(data, 0, pixels).rewind(); u.put(data, pixels, pixels / 4).rewind();
        v.put(data, pixels * 5 / 4, pixels / 4).rewind();
        return new Yuv420Frame(y, u, v, 332, 332, 332, 166, 166, 1,
                YuvColorRange.VIDEO, YuvColorMatrix.BT601, 0, false);
    }

    private static List<FaceSearchFeatureEntry> readRecords(Context context) throws Exception {
        List<FaceSearchFeatureEntry> records = new ArrayList<>();
        try (JsonReader reader = new JsonReader(new InputStreamReader(
                context.getAssets().open("face_search/features_10000.json"), StandardCharsets.UTF_8))) {
            reader.beginObject();
            while (reader.hasNext()) {
                switch (reader.nextName()) {
                    case "featureSpaceId": assertEquals(FaceFeatureFormat.FEATURE_SPACE_ID, reader.nextString()); break;
                    case "entryCount": assertEquals(10000, reader.nextInt()); break;
                    case "entries":
                        reader.beginArray();
                        while (reader.hasNext()) {
                            String id = null, feature = null, tag = "", group = ""; long time = 0;
                            reader.beginObject();
                            while (reader.hasNext()) {
                                switch (reader.nextName()) {
                                    case "faceId": id = reader.nextString(); break;
                                    case "feature": feature = reader.nextString(); break;
                                    case "group": group = reader.nextString(); break;
                                    case "tag": tag = reader.nextString(); break;
                                    case "updateTimeMillis": time = reader.nextLong(); break;
                                    default: reader.skipValue();
                                }
                            }
                            reader.endObject();
                            records.add(new FaceSearchFeatureEntry(id, feature, time, tag, group));
                        }
                        reader.endArray(); break;
                    default: reader.skipValue();
                }
            }
            reader.endObject();
        }
        return records;
    }

    private static void delete(File file) {
        File[] children = file.listFiles();
        if (children != null) for (File child : children) delete(child);
        file.delete();
    }
}
