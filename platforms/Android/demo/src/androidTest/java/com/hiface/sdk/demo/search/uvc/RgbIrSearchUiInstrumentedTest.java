package com.hiface.sdk.demo.search.uvc;

import android.app.Activity;
import android.app.Instrumentation;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.Context;
import android.content.res.Configuration;
import android.content.pm.ActivityInfo;
import android.os.Bundle;
import android.os.SystemClock;
import android.os.ParcelFileDescriptor;
import android.view.View;
import android.widget.TextView;
import android.view.accessibility.AccessibilityNodeInfo;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.common.HiFaceResult;
import com.hiface.sdk.detection.FaceDetectionResult;
import com.hiface.sdk.frame.RgbIrFrame;
import com.hiface.sdk.frame.Yuv420Frame;
import com.hiface.sdk.frame.YuvColorMatrix;
import com.hiface.sdk.frame.YuvColorRange;
import com.hiface.sdk.search.*;
import java.nio.ByteBuffer;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicReference;
import java.util.List;
import java.util.Locale;
import java.io.File;
import java.io.FileOutputStream;
import org.junit.After;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

/** No capture is started. Exercises real windows, resources, textures and recreation without face data. */
@RunWith(AndroidJUnit4.class)
public final class RgbIrSearchUiInstrumentedTest {
    private final Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
    private Activity activity, home, enrollment;
    private UvcEnrollmentConfirmation testConfirmation;
    private UvcSearchStatusUi testStatusUi;
    private void launch() {
        AccessibilityServiceInfo service=instrumentation.getUiAutomation().getServiceInfo();
        service.flags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;
        instrumentation.getUiAutomation().setServiceInfo(service);
        Context target=instrumentation.getTargetContext();
        // Enter through the exported home, then the real in-app control. Some OEMs reject
        // instrumentation launching a non-exported screen while the app is in the background.
        Instrumentation.ActivityMonitor homeMonitor=instrumentation.addMonitor("com.hiface.sdk.demo.DemoHomeActivity",null,false);
        ParcelFileDescriptor command=instrumentation.getUiAutomation().executeShellCommand(
                "am start -W -f 0x10008000 -n "+target.getPackageName()+"/com.hiface.sdk.demo.DemoHomeActivity");
        try(java.io.InputStream output=new ParcelFileDescriptor.AutoCloseInputStream(command)){
            byte[] buffer=new byte[1024];while(output.read(buffer)!=-1) { /* drain shell completion */ }
        }catch(java.io.IOException error){throw new AssertionError(error);}
        home=homeMonitor.waitForActivityWithTimeout(5000);instrumentation.removeMonitor(homeMonitor);assertNotNull(home);
        Instrumentation.ActivityMonitor searchMonitor=instrumentation.addMonitor(UVCCameraFaceSearchActivity.class.getName(),null,false);
        instrumentation.runOnMainSync(()->home.findViewById(R.id.featureUVCCameraFaceSearch).performClick());
        activity=searchMonitor.waitForActivityWithTimeout(5000);instrumentation.removeMonitor(searchMonitor);assertNotNull(activity);
        instrumentation.waitForIdleSync();
    }
    private AccessibilityNodeInfo node(String id) {
        String resource=id.startsWith("android:")?id:instrumentation.getTargetContext().getPackageName()+":id/"+id;
        long deadline=SystemClock.uptimeMillis()+3000;
        do {
            AccessibilityNodeInfo root=instrumentation.getUiAutomation().getRootInActiveWindow();
            if(root!=null){
                List<AccessibilityNodeInfo> found=root.findAccessibilityNodeInfosByViewId(resource);
                root.recycle();
                if(!found.isEmpty())return found.get(0);
            }
            SystemClock.sleep(25);
        }while(SystemClock.uptimeMillis()<deadline);
        throw new AssertionError("Missing UI: "+resource);
    }
    private void click(String id) {
        AccessibilityNodeInfo view=node(id);
        assertTrue(view.performAction(AccessibilityNodeInfo.ACTION_CLICK));view.recycle();
        instrumentation.waitForIdleSync();
    }
    private void openSettings(boolean camera) {
        click("uvcSettings");
        clickText(activity.getString(camera ? R.string.uvc_search_settings : R.string.search_settings));
    }

    private void clickText(String title) {
        long deadline = SystemClock.uptimeMillis() + 3000;
        do {
            AccessibilityNodeInfo root = instrumentation.getUiAutomation().getRootInActiveWindow();
            if (root != null) {
                List<AccessibilityNodeInfo> found = root.findAccessibilityNodeInfosByText(title);
                root.recycle();
                if (!found.isEmpty()) {
                    AccessibilityNodeInfo item = found.get(0);
                    for (int i = 1; i < found.size(); i++) found.get(i).recycle();
                    while (item != null && !item.isClickable()) {
                        AccessibilityNodeInfo parent = item.getParent();
                        item.recycle(); item = parent;
                    }
                    assertNotNull("Settings menu item must be accessible", item);
                    assertTrue(item.performAction(AccessibilityNodeInfo.ACTION_CLICK));
                    item.recycle(); instrumentation.waitForIdleSync();
                    return;
                }
            }
            SystemClock.sleep(25);
        } while (SystemClock.uptimeMillis() < deadline);
        throw new AssertionError("Missing settings menu item: " + title);
    }

    private void screenshot(String name) {
        instrumentation.waitForIdleSync();
        try { instrumentation.getUiAutomation().waitForIdle(500,5000); }
        catch(java.util.concurrent.TimeoutException error) { throw new AssertionError("UI did not settle",error); }
        File folder=new File(instrumentation.getTargetContext().getExternalFilesDir(null),"rgbir-ui");
        assertTrue(folder.isDirectory()||folder.mkdirs());
        // Capture the physical display: OEM compatibility windows can crop UiAutomation.takeScreenshot().
        ParcelFileDescriptor capture=instrumentation.getUiAutomation().executeShellCommand("screencap -p");
        try(java.io.InputStream input=new ParcelFileDescriptor.AutoCloseInputStream(capture);
                FileOutputStream stream=new FileOutputStream(new File(folder,name+".png"))){
            byte[] buffer=new byte[16384];int size;
            while((size=input.read(buffer))!=-1)stream.write(buffer,0,size);
        }catch(java.io.IOException error){throw new AssertionError(error);}
    }
    @After public void close() {
        instrumentation.runOnMainSync(()->{
            if(testConfirmation!=null)testConfirmation.dismiss();
            if(enrollment!=null)enrollment.finish();
            if(testStatusUi!=null)testStatusUi.clear();
            if(activity!=null)activity.finish();if(home!=null)home.finish();
        });
        instrumentation.waitForIdleSync();
    }
    @Test public void mainScreenAndSettingsUseAccessibleControls() {
        launch();
        instrumentation.runOnMainSync(()->{
            assertTrue(activity.findViewById(R.id.uvcStart).isEnabled());
            assertFalse(activity.findViewById(R.id.uvcStop).isEnabled());
            assertNull(activity.findViewById(R.id.uvcCameraSettings));
            assertEquals(View.GONE,activity.findViewById(R.id.uvcDebugPanel).getVisibility());
        });
        screenshot("main");
        openSettings(true);
        awaitText(activity.getString(R.string.uvc_search_setup_hint));
        AccessibilityNodeInfo threshold=node("uvcThreshold");assertEquals("0.50",threshold.getText().toString());threshold.recycle();
        AccessibilityNodeInfo rgb=node("uvcRgbDevice");assertNotNull(rgb.getContentDescription());rgb.recycle();
        screenshot("settings");
        click("android:id/button1");
    }
    @Test public void recreationRetainsParametersAndDebugSurfacesWithoutStartingCapture() {
        launch();openSettings(true);
        AccessibilityNodeInfo threshold=node("uvcThreshold");
        Bundle input=new Bundle();input.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,"0.65");
        assertTrue(threshold.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,input));threshold.recycle();
        click("uvcDebug");click("android:id/button1");
        Instrumentation.ActivityMonitor monitor=instrumentation.addMonitor(UVCCameraFaceSearchActivity.class.getName(),null,false);
        instrumentation.runOnMainSync(()->activity.recreate());
        activity=monitor.waitForActivityWithTimeout(5000);instrumentation.removeMonitor(monitor);
        assertNotNull(activity);instrumentation.waitForIdleSync();
        instrumentation.runOnMainSync(()->{
            assertEquals(View.VISIBLE,activity.findViewById(R.id.uvcDebugPanel).getVisibility());
            assertTrue(activity.findViewById(R.id.uvcStart).isEnabled());
            assertFalse(activity.findViewById(R.id.uvcStop).isEnabled());
        });
        screenshot("debug");
        instrumentation.runOnMainSync(()->assertTrue(((TextView)activity.findViewById(R.id.uvcDiagnostics))
                .getText().toString().contains("P95")));
        openSettings(true);
        AccessibilityNodeInfo restored=node("uvcThreshold");assertEquals("0.65",restored.getText().toString());restored.recycle();
        click("android:id/button1");
    }
    private void input(String id, String value) {
        AccessibilityNodeInfo field = node(id);
        Bundle arguments = new Bundle();
        arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value);
        assertTrue(field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments));
        field.recycle();
        instrumentation.waitForIdleSync();
    }

    @Test public void searchSettingsValidateDraftCancelResetApplyAndRestore() {
        launch();
        openSettings(false);
        input("uvcSearchGroup", "discarded");
        click("android:id/button2");
        openSettings(false);
        AccessibilityNodeInfo group = node("uvcSearchGroup");
        assertFalse(group.getText().toString().contains("discarded")); group.recycle();
        input("uvcSearchThreshold", "0.20");
        click("android:id/button1");
        AccessibilityNodeInfo invalid = node("uvcSearchThreshold");
        assertNotNull(invalid.getError()); invalid.recycle();
        click("android:id/button3");
        input("uvcSearchGroup", "regression-group");
        input("uvcSearchThreshold", "0.83");
        input("uvcSearchInterval", "1200");
        input("uvcSearchTimeout", "2000");
        click("android:id/button1");
        AccessibilityNodeInfo main = instrumentation.getUiAutomation().getRootInActiveWindow();
        assertNotNull(main);
        assertTrue("Search parameters belong only in settings",
                main.findAccessibilityNodeInfosByText("regression-group").isEmpty());
        main.recycle();
        Instrumentation.ActivityMonitor monitor = instrumentation.addMonitor(UVCCameraFaceSearchActivity.class.getName(), null, false);
        instrumentation.runOnMainSync(() -> activity.recreate());
        activity = monitor.waitForActivityWithTimeout(5000); instrumentation.removeMonitor(monitor);
        assertNotNull(activity); instrumentation.waitForIdleSync();
        openSettings(false);
        for (String[] expected : new String[][]{{"uvcSearchGroup","regression-group"},
                {"uvcSearchThreshold","0.83"},{"uvcSearchInterval","1200"},{"uvcSearchTimeout","2000"}}) {
            AccessibilityNodeInfo field = node(expected[0]);
            assertEquals(expected[1], field.getText().toString()); field.recycle();
        }
        screenshot("search-settings");
        click("android:id/button2");
    }

    private void createStatusUi() {
        testStatusUi = new UvcSearchStatusUi(activity.findViewById(android.R.id.content),
                new android.os.Handler(android.os.Looper.getMainLooper()));
        testStatusUi.config(UvcSearchSettingsDialog.defaults());
    }

    private static FaceSearchFrame statusFrame(long id, int irStatus, Float similarity, String faceId) {
        long[] metadata = new long[com.hiface.sdk.internal.contract.RgbIrContract.IR_SEARCH_META_SIZE];
        float[] values = new float[com.hiface.sdk.internal.contract.RgbIrContract.IR_SEARCH_VALUES_SIZE];
        metadata[0] = 1; metadata[1] = id; metadata[2] = irStatus;
        if (irStatus == com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_PASSED
                || irStatus == com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_REJECTED) {
            metadata[3] = metadata[4] = 1; values[2] = values[3] = 120;
            values[4] = irStatus == com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_PASSED ? .95f : .1f;
        }
        FaceSearchFace face = new FaceSearchFace(new FaceSearchFace.Bounds(0, 0, 120, 120),
                faceId != null, similarity, faceId, "", "");
        return new FaceSearchFrame(id, 640, 480, java.util.Collections.singletonList(face),
                new InfraredSearchInfo(metadata, values));
    }

    private static FaceSearchResult matchResult(long id, float similarity) {
        return new FaceSearchResult(FaceSearchResult.EndReason.MATCH_FOUND, null,
                statusFrame(id, com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_PASSED,
                        similarity, "synthetic-id"));
    }

    @Test public void emptyScopeAndIrReasonsTakePriorityOverGenericSearchProgress() {
        launch();
        instrumentation.runOnMainSync(() -> {
            createStatusUi();
            testStatusUi.frame(statusFrame(1, com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_FACE_MISMATCH, null, null));
            testStatusUi.progress(new FaceSearchProgress(FaceSearchProgress.Stage.SEARCHING, 1, 1));
        });
        SystemClock.sleep(300);
        instrumentation.runOnMainSync(() -> {
            assertEquals(activity.getString(R.string.uvc_search_face_mismatch),
                    ((TextView) activity.findViewById(R.id.uvcStatus)).getText().toString());
            testStatusUi.progress(new FaceSearchProgress(FaceSearchProgress.Stage.EMPTY_GALLERY, 1, 1));
        });
        SystemClock.sleep(300);
        instrumentation.runOnMainSync(() -> {
            assertEquals(activity.getString(R.string.search_ui_empty_caption),
                    ((TextView) activity.findViewById(R.id.uvcStatus)).getText().toString());
            assertFalse(activity.findViewById(R.id.uvcResult).isClickable());
        });
    }

    @Test public void detectionFramesRetainCompletedResultAndKeepActionLayoutStable() {
        launch();
        int[] changes = {0}, position = new int[2];
        long start = SystemClock.uptimeMillis();
        java.util.List<String> events = new java.util.ArrayList<>();
        String[] first = {null};
        instrumentation.runOnMainSync(() -> {
            createStatusUi();
            activity.findViewById(R.id.uvcStart).getLocationOnScreen(position);
            ((TextView) activity.findViewById(R.id.uvcResult)).addTextChangedListener(new android.text.TextWatcher() {
                @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
                @Override public void onTextChanged(CharSequence s, int offset, int before, int count) {
                    changes[0]++;
                    events.add((SystemClock.uptimeMillis() - start) + "ms:"
                            + (activity.getString(R.string.uvc_search_no_result).contentEquals(s) ? "empty" : "complete"));
                }
                @Override public void afterTextChanged(android.text.Editable s) {}
            });
            testStatusUi.result(matchResult(1, .9f));
            TextView result = activity.findViewById(R.id.uvcResult);
            first[0] = result.getText().toString();
            for (int id = 2; id <= 15; id++) {
                testStatusUi.frame(statusFrame(id,
                        com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_NOT_EVALUATED, null, null));
                testStatusUi.progress(new FaceSearchProgress(FaceSearchProgress.Stage.SEARCHING, 1, 1));
                assertEquals(first[0], result.getText().toString());
                assertTrue(activity.findViewById(R.id.uvcResult).isClickable());
            }
            for (int id = 16; id <= 30; id++) testStatusUi.result(matchResult(id, .99f));
            assertEquals(1, changes[0]);
        });
        SystemClock.sleep(600);
        instrumentation.runOnMainSync(() -> {
            assertEquals(events.toString(), 2, changes[0]);
            assertTrue(((TextView) activity.findViewById(R.id.uvcResult)).getText().toString().contains("0.99"));
            int[] after = new int[2]; activity.findViewById(R.id.uvcStart).getLocationOnScreen(after);
            assertArrayEquals(position, after);
        });
    }

    @Test public void rejectionAndPairLossClearIdentityAndCancelQueuedDisplayUpdates() {
        launch();
        instrumentation.runOnMainSync(() -> {
            createStatusUi();
            testStatusUi.result(matchResult(1, .9f));
            testStatusUi.result(matchResult(2, .99f)); // A score update is queued, not yet displayed.
            FaceSearchFrame rejected = statusFrame(3,
                    com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_REJECTED, .99f, "synthetic-id");
            testStatusUi.frame(rejected);
            TextView result = activity.findViewById(R.id.uvcResult);
            assertEquals(activity.getString(R.string.uvc_search_no_result), result.getText().toString());
            testStatusUi.result(new FaceSearchResult(FaceSearchResult.EndReason.SPOOF_DETECTED, null, rejected));
            String rejectedText = result.getText().toString();
            assertFalse(rejectedText.contains("synthetic-id"));
            testStatusUi.frame(statusFrame(4,
                    com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_REJECTED, null, null));
            assertEquals(rejectedText, result.getText().toString());
            testStatusUi.waitingForPair();
            testStatusUi.result(matchResult(5, .99f)); // Even a newer queued result cannot recover a lost pair.
            testStatusUi.progress(new FaceSearchProgress(FaceSearchProgress.Stage.SEARCHING, 1, 1));
        });
        SystemClock.sleep(600);
        instrumentation.runOnMainSync(() -> {
            assertEquals(activity.getString(R.string.uvc_search_no_result),
                    ((TextView) activity.findViewById(R.id.uvcResult)).getText().toString());
            assertEquals(activity.getString(R.string.uvc_search_waiting_pair),
                    ((TextView) activity.findViewById(R.id.uvcStatus)).getText().toString());
            assertFalse(activity.findViewById(R.id.uvcResult).isClickable());
        });
    }

    @Test public void resultExpiryUsesLastCompletionAndStopCancelsPendingGuidance() {
        launch();
        instrumentation.runOnMainSync(() -> { createStatusUi(); testStatusUi.result(matchResult(1, .9f)); });
        SystemClock.sleep(1000);
        instrumentation.runOnMainSync(() -> testStatusUi.result(matchResult(2, .99f)));
        SystemClock.sleep(650);
        instrumentation.runOnMainSync(() -> assertTrue(activity.findViewById(R.id.uvcResult).isClickable()));
        SystemClock.sleep(1000);
        instrumentation.runOnMainSync(() -> {
            assertFalse(activity.findViewById(R.id.uvcResult).isClickable());
            testStatusUi.progress(new FaceSearchProgress(FaceSearchProgress.Stage.SEARCHING, 1, 1));
            testStatusUi.clear();
            ((TextView) activity.findViewById(R.id.uvcStatus)).setText(R.string.uvc_search_stopped);
        });
        SystemClock.sleep(300);
        instrumentation.runOnMainSync(() -> assertEquals(activity.getString(R.string.uvc_search_stopped),
                ((TextView) activity.findViewById(R.id.uvcStatus)).getText().toString()));
    }

    private void assertDetailsText(String expected) {
        instrumentation.waitForIdleSync();
        AccessibilityNodeInfo root = instrumentation.getUiAutomation().getRootInActiveWindow();
        assertNotNull(root);
        List<AccessibilityNodeInfo> found = root.findAccessibilityNodeInfosByText(expected);
        root.recycle();
        boolean exact = false;
        for (AccessibilityNodeInfo node : found) {
            exact |= expected.contentEquals(node.getText());
            node.recycle();
        }
        assertTrue("Full sample details must remain readable", exact);
    }

    @Test public void referenceResultFormatPreservesFullIdAndSeparatesIrFromRgbLiveness() {
        launch();
        String id = new String(new char[180]).replace('\0', 'X') + "-END";
        instrumentation.runOnMainSync(() -> {
            createStatusUi();
            FaceSearchFrame frame = statusFrame(1,
                    com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_PASSED, .921f, id);
            testStatusUi.result(new FaceSearchResult(FaceSearchResult.EndReason.MATCH_FOUND, .11f, frame));
            TextView result = activity.findViewById(R.id.uvcResult);
            assertEquals(id + "=0.92, Liveness=0.95", result.getText().toString());
            assertEquals(android.text.TextUtils.TruncateAt.MIDDLE, result.getEllipsize());
            result.performClick();
        });
        String full = "Face ID: " + id + "\n" + activity.getString(R.string.search_ui_overlay_similarity)
                + " 0.921 · " + activity.getString(R.string.uvc_search_ir_liveness) + " 0.950";
        assertDetailsText(full);
        instrumentation.runOnMainSync(() -> testStatusUi.result(matchResult(2, .99f)));
        assertDetailsText(full); // Open details retain their original sample while the card updates.
        click("android:id/button1");
        instrumentation.runOnMainSync(() -> {
            FaceSearchFrame candidate = statusFrame(3,
                    com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_REJECTED, .999f, id);
            long[] metadata = new long[com.hiface.sdk.internal.contract.RgbIrContract.IR_SEARCH_META_SIZE];
            metadata[0] = 1; metadata[1] = 3;
            metadata[2] = com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_REJECTED;
            metadata[3] = metadata[4] = 1;
            float[] values = new float[com.hiface.sdk.internal.contract.RgbIrContract.IR_SEARCH_VALUES_SIZE];
            values[2] = values[3] = 120; // IR zero is a valid rejection, not a missing score.
            FaceSearchFrame rejected = new FaceSearchFrame(3, 640, 480, candidate.getFaces(),
                    new InfraredSearchInfo(metadata, values));
            testStatusUi.result(new FaceSearchResult(FaceSearchResult.EndReason.SPOOF_DETECTED, 1f, rejected));
            TextView result = activity.findViewById(R.id.uvcResult);
            assertEquals(activity.getString(R.string.uvc_search_ir_rejected), result.getText().toString());
            assertFalse(result.getContentDescription().toString().contains(id));
            result.performClick();
        });
        assertDetailsText(activity.getString(R.string.uvc_search_ir_rejected) + "\n"
                + activity.getString(R.string.search_ui_overlay_similarity) + " 0.999 · "
                + activity.getString(R.string.uvc_search_ir_liveness) + " 0.000\n"
                + activity.getString(R.string.uvc_search_ir_rejected_hint));
        click("android:id/button1");
        instrumentation.runOnMainSync(() -> {
            testStatusUi.result(new FaceSearchResult(FaceSearchResult.EndReason.TIMEOUT, null,
                    statusFrame(4, com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_NOT_EVALUATED, null, null)));
            TextView result = activity.findViewById(R.id.uvcResult);
            assertEquals(activity.getString(R.string.uvc_search_ir_unavailable), result.getText().toString());
            result.performClick();
        });
        assertDetailsText(activity.getString(R.string.uvc_search_ir_unavailable) + "\n"
                + activity.getString(R.string.search_ui_overlay_similarity) + " — · "
                + activity.getString(R.string.uvc_search_ir_liveness) + " —");
        click("android:id/button1");
        instrumentation.runOnMainSync(() -> {
            testStatusUi.result(new FaceSearchResult(FaceSearchResult.EndReason.TIMEOUT, null,
                    statusFrame(5, com.hiface.sdk.internal.contract.RgbIrContract.SEARCH_IR_PASSED, .5f, null)));
            TextView result = activity.findViewById(R.id.uvcResult);
            assertEquals(activity.getString(R.string.uvc_search_timeout), result.getText().toString());
            result.performClick();
        });
        assertDetailsText(activity.getString(R.string.uvc_search_timeout) + "\n"
                + activity.getString(R.string.search_ui_overlay_similarity) + " 0.500 · "
                + activity.getString(R.string.uvc_search_ir_liveness) + " 0.950\n"
                + activity.getString(R.string.uvc_search_unmatched_hint));
        click("android:id/button1");
    }

    private void enterEnrollment() {
        Instrumentation.ActivityMonitor monitor = instrumentation.addMonitor(UVCCameraFaceEnrollmentActivity.class.getName(), null, false);
        instrumentation.runOnMainSync(() -> activity.findViewById(R.id.uvcEnroll).performClick());
        enrollment = monitor.waitForActivityWithTimeout(5000); instrumentation.removeMonitor(monitor);
        assertNotNull(enrollment); instrumentation.waitForIdleSync();
    }

    @Test public void uvcEnrollmentEntryInheritsScopeAndRotationWithoutOpeningBuiltInCamera() {
        launch();
        openSettings(false); input("uvcSearchGroup", "capture-scope"); click("android:id/button1");
        openSettings(true); click("uvcRgbRotation"); clickText("90°"); click("android:id/button1");
        enterEnrollment();
        instrumentation.runOnMainSync(() -> {
            assertTrue(enrollment.findViewById(R.id.uvcEnrollPreview) instanceof android.view.TextureView);
            assertNull(enrollment.findViewById(R.id.cameraPreview));
            UvcEnrollmentState state = new androidx.lifecycle.ViewModelProvider((androidx.appcompat.app.AppCompatActivity) enrollment)
                    .get(UvcEnrollmentState.class);
            assertEquals("capture-scope", state.group);
        });
        click("uvcEnrollSettings");
        awaitText("90°");
        screenshot("enrollment-settings"); click("android:id/button1");
        Instrumentation.ActivityMonitor monitor = instrumentation.addMonitor(UVCCameraFaceEnrollmentActivity.class.getName(), null, false);
        instrumentation.runOnMainSync(() -> enrollment.recreate());
        enrollment = monitor.waitForActivityWithTimeout(5000); instrumentation.removeMonitor(monitor);
        assertNotNull(enrollment); instrumentation.waitForIdleSync();
        screenshot("enrollment");
        click("uvcEnrollSettings");
        awaitText("90°");
        click("android:id/button1");
        instrumentation.runOnMainSync(() -> enrollment.findViewById(R.id.backButton).performClick());
        instrumentation.waitForIdleSync();
        instrumentation.runOnMainSync(() -> {
            assertTrue(activity.findViewById(R.id.uvcStart).isEnabled());
            assertFalse(activity.findViewById(R.id.uvcStop).isEnabled());
        });
    }

    @Test public void enrollmentConfirmationValidatesIdRetainsDraftAndPreventsDuplicateSubmit() {
        launch(); enterEnrollment();
        int[] saves = {0}, retakes = {0};
        UvcEnrollmentState draft = new UvcEnrollmentState(); draft.initialize("capture-scope");
        draft.pending = new com.hiface.sdk.capture.FaceCaptureResult(new byte[333 * 333 * 4], "synthetic-ui-feature");
        instrumentation.runOnMainSync(() -> {
            testConfirmation = new UvcEnrollmentConfirmation((androidx.appcompat.app.AppCompatActivity) enrollment,
                    draft, new UvcEnrollmentConfirmation.Listener() {
                @Override public void save(String id, String group) {
                    assertEquals("synthetic-id", id); assertEquals("edited-scope", group);
                    saves[0]++; testConfirmation.setSaving(true);
                }
                @Override public void retake() { retakes[0]++; }
                @Override public void cancel() { fail("Unexpected cancellation"); }
            });
            testConfirmation.show();
        });
        click("android:id/button1");
        AccessibilityNodeInfo id = node("uvcEnrollId"); assertNotNull(id.getError()); id.recycle();
        input("uvcEnrollId", "  synthetic-id  "); input("uvcEnrollGroup", " edited-scope ");
        click("android:id/button1");
        instrumentation.runOnMainSync(() -> {
            assertEquals(1, saves[0]); assertEquals("synthetic-id", draft.faceId); assertEquals("edited-scope", draft.group);
        });
        AccessibilityNodeInfo save = node("android:id/button1"); assertFalse(save.isEnabled()); save.recycle();
        instrumentation.runOnMainSync(() -> testConfirmation.setSaving(false));
        click("android:id/button2");
        instrumentation.runOnMainSync(() -> assertEquals(1, retakes[0]));
    }

    private void confirmSyntheticCapture(String feature) {
        Instrumentation.ActivityMonitor monitor = instrumentation.addMonitor(UVCCameraFaceEnrollmentActivity.class.getName(), null, false);
        instrumentation.runOnMainSync(() -> {
            UvcEnrollmentState state = new androidx.lifecycle.ViewModelProvider((androidx.appcompat.app.AppCompatActivity) enrollment)
                    .get(UvcEnrollmentState.class);
            state.pending = new com.hiface.sdk.capture.FaceCaptureResult(new byte[333 * 333 * 4], feature);
            state.requested = false;
            enrollment.recreate();
        });
        enrollment = monitor.waitForActivityWithTimeout(5000); instrumentation.removeMonitor(monitor);
        assertNotNull(enrollment); instrumentation.waitForIdleSync();
        node("uvcEnrollId").recycle();
    }

    private void awaitText(String expected) {
        long deadline = SystemClock.uptimeMillis() + 5000;
        do {
            AccessibilityNodeInfo root = instrumentation.getUiAutomation().getRootInActiveWindow();
            if (root != null) {
                List<AccessibilityNodeInfo> found = root.findAccessibilityNodeInfosByText(expected);
                root.recycle();
                if (!found.isEmpty()) { for (AccessibilityNodeInfo node : found) node.recycle(); return; }
            }
            SystemClock.sleep(25);
        } while (SystemClock.uptimeMillis() < deadline);
        fail("Expected enrollment prompt was not shown");
    }

    private void awaitEnrollmentExit() {
        long deadline = SystemClock.uptimeMillis() + 5000;
        boolean[] finished = {false};
        do {
            instrumentation.runOnMainSync(() -> finished[0] = enrollment.isFinishing());
            if (finished[0]) { instrumentation.waitForIdleSync(); return; }
            SystemClock.sleep(25);
        } while (SystemClock.uptimeMillis() < deadline);
        fail("Enrollment did not return to search after saving");
    }

    private static String syntheticBasisFeature(boolean secondAxis) {
        // Core's encoded basis vectors [1, 0, ...] and [0, 1, ...]. The tail packs 504 zeros.
        // Build the fixture in memory so the test needs no image or feature asset.
        byte[] payload = new byte[450];
        byte[] prefix = {0x24, 0x10, (byte) (secondAxis ? 0x7f : 0xfc),
                (byte) (secondAxis ? 0xf9 : 0xfd), (byte) 0xfb, (byte) 0xf7, (byte) 0xef, (byte) 0xdf, (byte) 0xbf};
        byte[] zeros = {0x7e, (byte) 0xfd, (byte) 0xfb, (byte) 0xf7, (byte) 0xef, (byte) 0xdf, (byte) 0xbf};
        System.arraycopy(prefix, 0, payload, 0, prefix.length);
        for (int i = prefix.length; i < payload.length; i += zeros.length)
            System.arraycopy(zeros, 0, payload, i, zeros.length);
        return "HF1:" + android.util.Base64.encodeToString(payload, android.util.Base64.URL_SAFE | android.util.Base64.NO_WRAP);
    }

    @Test public void uvcEnrollmentSavesToSharedLibraryAndRequiresExplicitOverwrite() {
        Context target = instrumentation.getTargetContext();
        org.junit.Assume.assumeTrue("Synthetic writes require the isolated development app",
                target.getPackageName().endsWith(".rgbirdev"));
        String first = syntheticBasisFeature(false), replacement = syntheticBasisFeature(true);
        String id = "uvc-regression-" + java.util.UUID.randomUUID();
        launch();
        try (FaceSearchDatabase db = HiFaceSdk.openSearchDatabase(target).requireValue()) {
            try {
                enterEnrollment(); confirmSyntheticCapture(first);
                input("uvcEnrollId", id); input("uvcEnrollGroup", "first-group"); click("android:id/button1");
                awaitEnrollmentExit();
                FaceSearchEntry initial = db.get(id).requireValue();
                assertEquals("first-group", initial.getGroup()); assertTrue(first.equals(initial.getFeature()));
                assertTrue(db.updateMetadata(id, null, "retained-tag", 0).isSuccess());
                enterEnrollment(); confirmSyntheticCapture(replacement);
                input("uvcEnrollId", id); input("uvcEnrollGroup", "replacement-group"); click("android:id/button1");
                awaitText(target.getString(R.string.search_exists));
                assertTrue(first.equals(db.get(id).requireValue().getFeature()));
                click("android:id/button2"); // Cancelling the overwrite keeps the pending enrollment and old record.
                node("uvcEnrollId").recycle();
                assertEquals("first-group", db.get(id).requireValue().getGroup());
                click("android:id/button1"); awaitText(target.getString(R.string.search_exists));
                click("android:id/button1"); awaitEnrollmentExit();
                FaceSearchEntry updated = db.get(id).requireValue();
                assertEquals("replacement-group", updated.getGroup()); assertEquals("retained-tag", updated.getTag());
                assertTrue(replacement.equals(updated.getFeature()));
            } finally { assertTrue(db.delete(id).isSuccess()); }
        }
    }

    @Test public void syntheticNv21FrameFeedsRealGuidedCaptureWithRotationAndNoFaceData() {
        CountDownLatch progress = new CountDownLatch(1);
        AtomicReference<HiFaceError> error = new AtomicReference<>();
        try (HiFaceSdk sdk = HiFaceSdk.builder(instrumentation.getTargetContext()).build()) {
            com.hiface.sdk.common.FaceRequest request = sdk.capture().startCameraCapture(new com.hiface.sdk.capture.FaceCaptureListener() {
                @Override public void onProgress(com.hiface.sdk.flow.FaceFlowProgress value) {
                    if (value.getStage() == com.hiface.sdk.flow.FaceFlowStage.WAITING_FOR_FACE) progress.countDown();
                }
                @Override public void onResult(com.hiface.sdk.capture.FaceCaptureResult value) { fail("Blank frame cannot be enrolled"); }
                @Override public void onError(HiFaceError value) { error.set(value); progress.countDown(); }
            });
            try {
                ByteBuffer nv21 = ByteBuffer.allocateDirect(640 * 480 * 3 / 2);
                for (int i = 0; i < 640 * 480; i++) nv21.put((byte)16);
                while (nv21.hasRemaining()) nv21.put((byte)128); nv21.flip();
                com.facesdkpro.uvccamera.Nv21Planes planes = com.facesdkpro.uvccamera.Nv21Planes.from(nv21, 640, 480);
                long deadline = SystemClock.uptimeMillis() + 20_000;
                boolean accepted = false;
                while ((progress.getCount() != 0 || !accepted) && SystemClock.uptimeMillis() < deadline) {
                    HiFaceResult<FaceDetectionResult> result = sdk.processFrame(new Yuv420Frame(planes.y(), planes.u(), planes.v(),
                            640, 480, planes.yRowStride, planes.uRowStride, planes.vRowStride, planes.uvPixelStride,
                            YuvColorRange.VIDEO, YuvColorMatrix.BT601, 90, false));
                    if (result.isSuccess()) accepted = true;
                    else assertTrue(result.requireError().getCode().name(),
                            result.requireError().getCode() == HiFaceErrorCode.NOT_READY || result.requireError().getCode() == HiFaceErrorCode.BUSY);
                    SystemClock.sleep(110);
                }
                assertTrue("Rotated NV21 must cross the real frame entry", accepted);
                assertEquals(0, progress.getCount()); assertNull(error.get());
            } finally { request.cancel(); }
        }
    }

    @Test public void portraitAndLandscapeKeepActionsReachable() {
        launch();
        for(int orientation:new int[]{ActivityInfo.SCREEN_ORIENTATION_PORTRAIT,ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE}){
            int expected=orientation==ActivityInfo.SCREEN_ORIENTATION_PORTRAIT?Configuration.ORIENTATION_PORTRAIT:Configuration.ORIENTATION_LANDSCAPE;
            if(activity.getResources().getConfiguration().orientation!=expected){
                Instrumentation.ActivityMonitor monitor=instrumentation.addMonitor(UVCCameraFaceSearchActivity.class.getName(),null,false);
                instrumentation.runOnMainSync(()->activity.setRequestedOrientation(orientation));
                activity=monitor.waitForActivityWithTimeout(5000);instrumentation.removeMonitor(monitor);
                assertNotNull(activity);instrumentation.waitForIdleSync();
            }
            assertEquals(expected,activity.getResources().getConfiguration().orientation);
            AccessibilityNodeInfo start=node("uvcStart");assertTrue(start.isVisibleToUser());start.recycle();
            screenshot(expected==Configuration.ORIENTATION_PORTRAIT?"portrait":"landscape");
        }
    }
    @Test public void emptyDiagnosticsFormatInBothLanguagesWithoutFakeTimings() {
        RgbIrSearchStats stats=new RgbIrSearchStats();stats.start(1,0);
        for(String tag:new String[]{"en-US","zh-CN"}){
            Context app=instrumentation.getTargetContext();
            Configuration config=new Configuration(app.getResources().getConfiguration());config.setLocale(Locale.forLanguageTag(tag));
            String text=RgbIrDiagnosticsFormatter.format(app.createConfigurationContext(config),stats.snapshot(1),null);
            assertTrue(text.contains("P95"));assertTrue(text.contains("—"));assertFalse(text.contains("null"));
        }
    }
    @Test public void syntheticBlankPairCrossesRealCoreJniWithPerStageDiagnostics() {
        AtomicReference<InfraredSearchInfo> observed=new AtomicReference<>();
        AtomicReference<HiFaceError> failure=new AtomicReference<>();
        CountDownLatch done=new CountDownLatch(1);
        try(HiFaceSdk sdk=HiFaceSdk.builder(instrumentation.getTargetContext()).build()){
            InfraredSearchConfig ir=new InfraredSearchConfig(.5f,new float[]{1,0,0,0,1,0,0,0,1},.25f,80,50,150);
            try(FaceSearchSession session=sdk.search().startCameraSearch(FaceSearchSessionConfig.builder()
                    .infraredLiveness(ir).build(),new FaceSearchListener(){
                @Override public void onFrame(FaceSearchFrame frame){
                    InfraredSearchInfo info=frame.getInfrared();
                    if(info!=null&&info.getDiagnostics().getDurationMicros(InfraredSearchDiagnostics.Stage.RGB_DETECTION)!=null){
                        observed.set(info);done.countDown();
                    }
                }
                @Override public void onProgress(FaceSearchProgress progress){}
                @Override public void onResult(FaceSearchResult result){assertNotEquals(FaceSearchResult.EndReason.MATCH_FOUND,result.getEndReason());}
                @Override public void onError(HiFaceError error){failure.set(error);done.countDown();}
            })){
                Yuv420Frame rgb=new Yuv420Frame(constantPlane(640*480,16),constantPlane(320*240,128),
                        constantPlane(320*240,128),640,480,640,320,320,1,YuvColorRange.VIDEO,YuvColorMatrix.BT601,0,false);
                ByteBuffer gray=constantPlane(640*480,0);
                long deadline=SystemClock.uptimeMillis()+20000,sequence=0;
                while(done.getCount()!=0&&SystemClock.uptimeMillis()<deadline){
                    long now=SystemClock.elapsedRealtime();++sequence;
                    HiFaceResult<FaceDetectionResult> result=sdk.processFrame(new RgbIrFrame(rgb,gray,640,480,640,
                            17,sequence,sequence,sequence,now,now));
                    if(result.isFailure())assertTrue(result.requireError().getCode().name(),
                            result.requireError().getCode()==HiFaceErrorCode.NOT_READY||result.requireError().getCode()==HiFaceErrorCode.BUSY);
                    SystemClock.sleep(110);
                }
                assertNull(failure.get());assertNotNull("No native RGB/IR diagnostic sample",observed.get());
                InfraredSearchInfo info=observed.get();
                assertEquals(17,info.getSourceId());assertTrue(info.getPairId()>0);
                assertEquals(640,info.getDiagnostics().getImageWidth());assertEquals(480,info.getDiagnostics().getImageHeight());
                assertEquals(InfraredSearchInfo.Status.NOT_EVALUATED,info.getStatus());
                assertNull(info.getRealScore());assertFalse(info.isPassed());
                assertNull(info.getDiagnostics().getDurationMicros(InfraredSearchDiagnostics.Stage.IR_LIVENESS));
            }
        }
    }
    private static ByteBuffer constantPlane(int size,int value){
        ByteBuffer buffer=ByteBuffer.allocateDirect(size);
        while(buffer.hasRemaining())buffer.put((byte)value);
        buffer.rewind();return buffer;
    }
}
