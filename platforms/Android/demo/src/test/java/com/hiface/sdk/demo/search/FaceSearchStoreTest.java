package com.hiface.sdk.demo.search;

import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.common.HiFaceResult;
import com.hiface.sdk.search.FaceSearchDatabase;
import com.hiface.sdk.search.FaceSearchEntry;

import org.junit.Test;

import java.lang.reflect.Proxy;
import java.lang.reflect.Field;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Queue;
import java.util.concurrent.AbstractExecutorService;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.function.BiFunction;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

public final class FaceSearchStoreTest {
    @Test
    public void cancellingQueuedWorkImmediatelyReleasesCallbacksAndInputs() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> { throw new AssertionError("Cancelled work opened database"); });
        FaceSearchStore.Request<?> request = store.save("A", "feature", "group", false,
                result -> fail("Cancelled callback"));
        request.cancel();
        // 工作线程仍未推进，宿主也继续保存 Request；引用必须现在就释放。
        assertReleased(request);
        worker.drain();
        assertTrue(main.isEmpty());
    }

    @Test
    public void cancellingPostedResultImmediatelyRemovesItsPayloadAndCallback() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> HiFaceResult.success(database((method, args) -> HiFaceResult.success(entry()))));
        FaceSearchStore.Request<?> request = store.find("A", result -> fail("Cancelled result"));
        worker.drain();
        assertEquals(1, main.size());
        request.cancel();
        assertTrue(main.isEmpty());
        assertReleased(request);
    }

    @Test
    public void completedHandleDoesNotRetainPageOrResult() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> HiFaceResult.success(database((method, args) -> HiFaceResult.success(entry()))));
        List<String> delivered = new ArrayList<>();
        FaceSearchStore.Request<?> request = store.find("A", result -> delivered.add(result.requireValue().id));
        worker.drain();
        drain(main);
        assertEquals(Collections.singletonList("A"), delivered);
        assertReleased(request);
    }

    @Test
    public void slowMainQueueCoalescesImportProgressAndResumesPostingAfterDelivery() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> { throw new AssertionError("Test only advances progress"); });
        List<Integer> progress = new ArrayList<>();
        FaceSearchStore.Request<?> request = store.importFeatureDemo(
                value -> progress.add(value.processed), result -> fail("Unexpected completion"));
        for (int i = 1; i <= 1000; i++) request.postProgress(i, 1000);
        assertEquals(1, main.size());
        drain(main);
        assertEquals(Collections.singletonList(1000), progress);
        request.postProgress(1001, 1001);
        assertEquals(1, main.size());
        drain(main);
        assertEquals(Arrays.asList(1000, 1001), progress);
        request.cancel();
        request.postProgress(1002, 1002);
        assertReleased(request);
        assertTrue(main.isEmpty());
    }

    @Test
    public void closeReleasesEveryQueuedAndPostedRequestBeforeCleanupRuns() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        List<String> calls = new ArrayList<>();
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> HiFaceResult.success(database((method, args) -> {
                    calls.add(method);
                    return method.equals("get") ? HiFaceResult.success(entry()) : null;
                })));
        FaceSearchStore.Request<?> posted = store.find("A", result -> fail("Late result"));
        worker.drain();
        FaceSearchStore.Request<?> queued = store.delete("A", result -> fail("Late deletion"));
        FaceSearchStore.Request<?> progress = store.importFeatureDemo(
                value -> fail("Late progress"), result -> fail("Late import"));
        progress.postProgress(100, 1000);
        store.close();
        assertReleased(posted);
        assertReleased(queued);
        assertReleased(progress);
        assertTrue(main.isEmpty());
        worker.drain();
        assertEquals(Arrays.asList("get", "close"), calls);
    }

    @Test
    public void rejectedMainPostReleasesRequestReferences() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        QueuedDispatcher dispatcher = new QueuedDispatcher(main);
        dispatcher.reject = true;
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher,
                () -> HiFaceResult.success(database((method, args) -> HiFaceResult.success(entry()))));
        FaceSearchStore.Request<?> result = store.find("A", value -> fail("Rejected result"));
        worker.drain();
        assertReleased(result);
        FaceSearchStore.Request<?> progress = store.importFeatureDemo(
                value -> fail("Rejected progress"), value -> fail("Rejected completion"));
        progress.postProgress(1, 1000);
        assertReleased(progress);
        assertTrue(main.isEmpty());
    }

    @Test
    public void cancellingInFlightSqlClearsUiAndDoesNotPostItsLateResult() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        FaceSearchStore.Request<?>[] request = new FaceSearchStore.Request<?>[1];
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> HiFaceResult.success(database((method, args) -> {
                    request[0].cancel();
                    assertReleased(request[0]);
                    return HiFaceResult.success(entry());
                })));
        request[0] = store.find("A", result -> fail("Late SQL result"));
        worker.drain();
        assertTrue(main.isEmpty());
    }

    private static void assertReleased(FaceSearchStore.Request<?> request) {
        try {
            for (String name : Arrays.asList("task", "callback", "result", "progress",
                    "pendingProgress", "owner")) {
                Field field = FaceSearchStore.Request.class.getDeclaredField(name);
                field.setAccessible(true);
                assertNull(name + " still retains request resources", field.get(request));
            }
        } catch (ReflectiveOperationException error) {
            throw new AssertionError(error);
        }
    }

    private static FaceSearchStore.Dispatcher dispatcher(Queue<Runnable> queue) {
        return new QueuedDispatcher(queue);
    }

    private static final class QueuedDispatcher implements FaceSearchStore.Dispatcher {
        final Queue<Runnable> queue;
        boolean reject;
        QueuedDispatcher(Queue<Runnable> queue) { this.queue = queue; }
        @Override public boolean post(Object token, Runnable action) {
            if (reject) return false;
            queue.add(new Posted(token, action));
            return true;
        }
        @Override public void remove(Object token) {
            queue.removeIf(action -> ((Posted) action).token == token);
        }
    }

    private static final class Posted implements Runnable {
        final Object token;
        final Runnable action;
        Posted(Object token, Runnable action) { this.token = token; this.action = action; }
        @Override public void run() { action.run(); }
    }

    @Test
    public void cancelledReadSkipsDatabaseWorkWithoutCancellingTheNextRead() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        List<String> calls = new ArrayList<>();
        FaceSearchDatabase database = database((method, args) -> {
            assertEquals("get", method);
            calls.add((String) args[0]);
            return HiFaceResult.success(entry());
        });
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> HiFaceResult.success(database));
        FaceSearchStore.Request<?> oldRead = store.find("old", result -> fail("Stale query"));
        oldRead.cancel();
        List<String> delivered = new ArrayList<>();
        store.find("A", result -> delivered.add(result.requireValue().id));
        worker.drain();
        drain(main);
        assertEquals(Collections.singletonList("A"), calls);
        assertEquals(Collections.singletonList("A"), delivered);
    }

    @Test
    public void cancellingReadAfterSqlCompletesSuppressesItsPostedCallback() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        FaceSearchDatabase database = database((method, args) -> {
            assertEquals("get", method);
            return HiFaceResult.success(entry());
        });
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> HiFaceResult.success(database));
        FaceSearchStore.Request<?> read = store.find("A", result -> fail("Cancelled result"));
        worker.drain();
        assertEquals(1, main.size());
        read.cancel();
        drain(main);
    }

    @Test
    public void opensBeforeReadsAndDeliversPageOnlyOnMainQueue() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        List<String> calls = new ArrayList<>();
        FaceSearchDatabase database = database((method, args) -> {
            calls.add(method);
            if (method.equals("count")) {
                assertArrayEquals(new Object[]{null, null}, args);
                return HiFaceResult.success(21L);
            }
            assertEquals("listRecent", method);
            assertArrayEquals(new Object[]{null, null, 20, 20}, args);
            return HiFaceResult.success(Collections.singletonList(entry()));
        });
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main), () -> {
            calls.add("open");
            return HiFaceResult.success(database);
        });
        List<FaceSearchStore.Page> pages = new ArrayList<>();
        store.loadPage(20, 20, result -> pages.add(result.requireValue()));
        assertTrue(calls.isEmpty());
        worker.drain();
        assertEquals(Arrays.asList("open", "count", "listRecent"), calls);
        assertTrue(pages.isEmpty());
        main.remove().run();
        FaceSearchStore.Page page = pages.get(0);
        assertEquals(21L, page.total);
        assertEquals(1, page.people.size());
        assertEquals("A", page.people.get(0).id);
        assertEquals("1A", page.people.get(0).group);
        assertEquals("VIP", page.people.get(0).tag);
    }

    @Test
    public void firstPageIsAnIndependentReadOnlyAdapterSnapshot() {
        List<FaceSearchEntry> entries = new ArrayList<>(
                Collections.singletonList(entry("A", "VIP", "1A")));
        FaceSearchStore.Page page = new FaceSearchStore.Page(1, entries);
        entries.clear();
        assertEquals(1, page.people.size());
        assertEquals("A", page.people.get(0).id);
        try {
            page.people.clear();
            fail("The submitted page must not be modified in place");
        } catch (UnsupportedOperationException expected) {
            assertEquals(1, page.people.size());
        }
    }

    @Test
    public void mergePeopleUpdatesMetadataWithoutDuplicatingIds() {
        List<FaceSearchStore.Person> current = FaceSearchStore.people(Arrays.asList(
                entry("A", "old", "1A"), entry("B", "", "2B")));
        List<FaceSearchStore.Person> page = FaceSearchStore.people(Arrays.asList(
                entry("A", "new", "VIP"), entry("C", "guest", "3C")));

        List<FaceSearchStore.Person> merged = FaceSearchStore.mergePeople(current, page);

        assertEquals(3, merged.size());
        assertEquals(Arrays.asList("A", "B", "C"), Arrays.asList(
                merged.get(0).id, merged.get(1).id, merged.get(2).id));
        assertEquals("VIP", merged.get(0).group);
        assertEquals("new", merged.get(0).tag);
        // AsyncListDiffer 计算新旧列表期间，原快照必须保持不变。
        assertEquals("1A", current.get(0).group);
        assertEquals("old", current.get(0).tag);
        merged.clear();
        assertEquals(2, current.size());
        assertEquals(2, page.size());
    }

    @Test
    public void failedOpenCanBeRetriedByTheNextOperation() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        HiFaceError error = new HiFaceError(HiFaceErrorCode.DATABASE_ERROR, "cannot open", null);
        List<HiFaceError> errors = new ArrayList<>();
        int[] opens = {0};
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main), () -> {
            opens[0]++;
            return opens[0] == 1 ? HiFaceResult.failure(error)
                    : HiFaceResult.success(database((method, args) -> {
                        assertEquals("get", method);
                        return HiFaceResult.success(entry());
                    }));
        });
        store.loadPage(0, 20, result -> errors.add(result.requireError()));
        List<String> delivered = new ArrayList<>();
        store.find("A", result -> delivered.add(result.requireValue().id));
        store.find("A", result -> delivered.add(result.requireValue().id));
        worker.drain();
        assertTrue(errors.isEmpty());
        drain(main);
        assertEquals(2, opens[0]);
        assertEquals(Collections.singletonList(error), errors);
        assertEquals(Arrays.asList("A", "A"), delivered);
    }

    @Test
    public void cancellingDeleteWhileOpeningDatabasePreventsTheMutation() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        FaceSearchStore.Request<?>[] request = new FaceSearchStore.Request<?>[1];
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main), () -> {
            request[0].cancel();
            return HiFaceResult.success(database((method, args) -> {
                if (!method.equals("close")) fail("Cancelled delete reached SQL");
                return null;
            }));
        });
        request[0] = store.delete("A", result -> fail("Cancelled delete callback"));
        worker.drain();
        assertTrue(main.isEmpty());
        store.close();
        worker.drain();
    }

    @Test
    public void stoppingDownloadsDisconnectsActiveConnectionsAndRejectsLateDownloads() throws Exception {
        int[] disconnects = {0};
        HttpURLConnection connection = new HttpURLConnection(new URL("https://example.com/face.png")) {
            @Override public void disconnect() { disconnects[0]++; }
            @Override public boolean usingProxy() { return false; }
            @Override public void connect() { fail("Test must not access the network"); }
        };
        FaceSearchStore.Request<?> request = new FaceSearchStore.Request<>();
        assertTrue(request.trackDownload(connection));
        request.cancel();
        assertFalse(request.trackDownload(connection));
        request.stopDownloads();
        assertEquals(1, disconnects[0]);
        request.stopDownloads();
        assertEquals(1, disconnects[0]);
        FaceSearchStore.Request<?> completed = new FaceSearchStore.Request<>();
        assertTrue(completed.trackDownload(connection));
        completed.stopDownloads();
        assertFalse(completed.trackDownload(connection));
        assertEquals(2, disconnects[0]);
    }

    @Test
    public void countFailureStopsPageRead() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        HiFaceResult<Long> failure = HiFaceResult.failure(HiFaceErrorCode.DATABASE_ERROR, "count");
        FaceSearchDatabase database = database((method, args) -> {
            assertEquals("count", method);
            return failure;
        });
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> HiFaceResult.success(database));
        List<HiFaceError> errors = new ArrayList<>();
        store.loadPage(0, 20, result -> errors.add(result.requireError()));
        worker.drain();
        drain(main);
        assertEquals(Collections.singletonList(failure.requireError()), errors);
    }

    @Test
    public void listFailureDoesNotReturnPartialPage() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        HiFaceResult<?> failure = HiFaceResult.failure(HiFaceErrorCode.CLOSED, "list");
        FaceSearchDatabase database = database((method, args) -> {
            if (method.equals("count")) {
                return HiFaceResult.success(1L);
            }
            assertEquals("listRecent", method);
            return failure;
        });
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> HiFaceResult.success(database));
        List<HiFaceError> errors = new ArrayList<>();
        store.loadPage(0, 20, result -> errors.add(result.requireError()));
        worker.drain();
        drain(main);
        assertEquals(Collections.singletonList(failure.requireError()), errors);
    }

    @Test
    public void lookupPreservesNotFoundForTheEmptyResultUi() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        HiFaceResult<?> missing = HiFaceResult.failure(HiFaceErrorCode.NOT_FOUND, "missing");
        FaceSearchDatabase database = database((method, args) -> {
            assertEquals("get", method);
            assertArrayEquals(new Object[]{"A"}, args);
            return missing;
        });
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> HiFaceResult.success(database));
        List<HiFaceError> errors = new ArrayList<>();
        store.find("A", result -> errors.add(result.requireError()));
        worker.drain();
        drain(main);
        assertEquals(Collections.singletonList(missing.requireError()), errors);
    }

    @Test
    public void closeBeforeWorkStartsSkipsOpeningAndQueuedOperations() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        List<String> calls = new ArrayList<>();
        FaceSearchDatabase database = database((method, args) -> {
            calls.add(method);
            assertEquals("close", method);
            return null;
        });
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main), () -> {
            calls.add("open");
            return HiFaceResult.success(database);
        });
        store.delete("A", result -> fail("Closed page received a delete result"));
        store.close();
        store.close();
        store.find("A", result -> fail("Operation submitted after close"));
        worker.drain();
        assertTrue(calls.isEmpty());
        assertTrue(main.isEmpty());
        assertTrue(worker.isTerminated());
    }

    @Test
    public void closeSuppressesPostedCallbacksAndClosesAfterCompletedWork() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        List<String> calls = new ArrayList<>();
        FaceSearchDatabase database = database((method, args) -> {
            calls.add(method);
            if (method.equals("get")) {
                return HiFaceResult.success(entry());
            }
            assertEquals("close", method);
            return null;
        });
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> HiFaceResult.success(database));
        store.find("A", result -> fail("Late callback reached destroyed page"));
        worker.drain();
        assertFalse(main.isEmpty());
        store.close();
        assertEquals(Collections.singletonList("get"), calls);
        drain(main);
        worker.drain();
        assertEquals(Arrays.asList("get", "close"), calls);
    }

    @Test
    public void mutationsAndCallbacksRunInOrder() {
        QueuedExecutor worker = new QueuedExecutor();
        Queue<Runnable> main = new ArrayDeque<>();
        List<String> calls = new ArrayList<>();
        FaceSearchDatabase database = database((method, args) -> {
            calls.add(method);
            if (method.equals("contains")) {
                assertArrayEquals(new Object[]{"A"}, args);
                return HiFaceResult.success(false);
            } else if (method.equals("saveFeature")) {
                assertArrayEquals(new Object[]{"A", "feature", 0L, null, "1A"}, args);
            } else {
                assertEquals("delete", method);
                assertArrayEquals(new Object[]{"A"}, args);
            }
            return HiFaceResult.success(true);
        });
        FaceSearchStore store = new FaceSearchStore(worker, dispatcher(main),
                () -> HiFaceResult.success(database));
        List<String> delivered = new ArrayList<>();
        store.save("A", "feature", "1A", false, result -> {
            assertTrue(result.requireValue());
            delivered.add("save");
        });
        store.delete("A", result -> {
            assertTrue(result.requireValue());
            delivered.add("delete");
        });
        worker.drain();
        assertEquals(Arrays.asList("contains", "saveFeature", "delete"), calls);
        assertTrue(delivered.isEmpty());
        drain(main);
        assertEquals(Arrays.asList("save", "delete"), delivered);
    }

    private static FaceSearchEntry entry() {
        return entry("A", "VIP", "1A");
    }

    private static FaceSearchEntry entry(String id, String tag, String group) {
        String feature = "HF1:" + new String(new char[600]).replace('\0', 'A');
        return new FaceSearchEntry(id, feature, 0, tag, group);
    }

    private static FaceSearchDatabase database(BiFunction<String, Object[], Object> call) {
        return (FaceSearchDatabase) Proxy.newProxyInstance(FaceSearchDatabase.class.getClassLoader(),
                new Class<?>[]{FaceSearchDatabase.class},
                (proxy, method, args) -> call.apply(method.getName(), args));
    }

    private static void drain(Queue<Runnable> queue) {
        while (!queue.isEmpty()) {
            queue.remove().run();
        }
    }

    /** 分别推进数据库队列和主线程队列，以重现真实生命周期的交错。 */
    private static final class QueuedExecutor extends AbstractExecutorService {
        private final Queue<Runnable> queue = new ArrayDeque<>();
        private boolean shutdown;

        void drain() {
            FaceSearchStoreTest.drain(queue);
        }

        @Override
        public void execute(Runnable command) {
            if (shutdown) {
                throw new RejectedExecutionException();
            }
            queue.add(command);
        }

        @Override public void shutdown() { shutdown = true; }
        @Override public boolean isShutdown() { return shutdown; }
        @Override public boolean isTerminated() { return shutdown && queue.isEmpty(); }
        @Override public boolean awaitTermination(long timeout, TimeUnit unit) { return isTerminated(); }

        @Override
        public List<Runnable> shutdownNow() {
            shutdown = true;
            List<Runnable> pending = new ArrayList<>(queue);
            queue.clear();
            return pending;
        }
    }
}
