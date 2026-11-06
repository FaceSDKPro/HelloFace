package com.hiface.sdk.demo.search.uvc;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.Set;

/** 主线程上的应用内 USB 关闭屏障；搜索、录入和重建后的页面都等待旧采集排空。 */
final class UvcCameraCloseBarrier {
    private static int pending;
    private static final Set<UvcCameraCloseBarrier> listeners = new LinkedHashSet<>();
    private int ownPending;
    private Runnable ready;

    boolean isClosing() { return pending != 0; }
    void closing() { ++ownPending; ++pending; }

    // 只在页面可见期间注册；onStop 移除，不由静态集合保留后台 Activity。
    void listen(Runnable listener) {
        ready = listener;
        if (listener == null) listeners.remove(this); else listeners.add(this);
    }

    void closed() {
        // 重复/无配对的回调不能替另一页面解除尚未完成的关闭。
        if (ownPending == 0) return;
        --ownPending;
        if (--pending != 0) return;
        for (UvcCameraCloseBarrier owner : new ArrayList<>(listeners))
            if (owner.ready != null) owner.ready.run();
    }
}
