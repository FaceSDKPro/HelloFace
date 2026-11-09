package com.hiface.sdk.demo.search.uvc;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.Set;

/** Main-thread close barrier shared across search, enrollment and recreation. 中文：等待旧采集完全排空。 */
final class UvcCameraCloseBarrier {
    // Global pending blocks all pages; per-owner counts prevent one owner releasing another.
    private static int pending;
    private static final Set<UvcCameraCloseBarrier> listeners = new LinkedHashSet<>();
    private int ownPending;
    private Runnable ready;

    boolean isClosing() { return pending != 0; }
    boolean isOwnerClosing() { return ownPending != 0; }

    void closing() {
        ++ownPending;
        ++pending;
    }

    // Subscribe only while visible; onStop removes the static reference to the background Activity.
    void listen(Runnable listener) {
        ready = listener;
        if (listener == null) listeners.remove(this);
        else listeners.add(this);
    }

    void closed() {
        // Duplicate or unmatched callbacks cannot release another owner's pending closure.
        if (ownPending == 0) return;
        --ownPending;
        if (--pending != 0) return;
        // Notify a snapshot because callbacks can navigate and change subscriptions.
        for (UvcCameraCloseBarrier owner : new ArrayList<>(listeners))
            if (owner.ready != null) owner.ready.run();
    }
}
