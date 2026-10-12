package com.hiface.sdk.demo.camera;

import com.hiface.sdk.common.FaceRequest;

import java.util.Objects;

/** 单次相机请求的所有权。状态在主线程修改，分析线程只读取 active。 */
public final class CameraFlowRequest {
    /** Demo 支持 API 23，不依赖 API 24 才提供的 java.util.function.Supplier。 */
    @FunctionalInterface
    public interface Starter {
        FaceRequest start();
    }

    private volatile boolean active;
    private FaceRequest request;

    boolean isActive() {
        return active;
    }

    boolean start(Starter starter) {
        if (active) return false;
        active = true;
        try {
            FaceRequest next = Objects.requireNonNull(starter.start(), "request");
            // 即便启动时同步失败/完成/取消，也不能重新持有已经失效的句柄。
            if (active) request = next;
            else next.cancel();
            return true;
        } catch (RuntimeException | Error error) {
            cancel();
            throw error;
        }
    }

    boolean finish() {
        if (!active) return false;
        active = false;
        request = null;
        return true;
    }

    void cancel() {
        active = false;
        FaceRequest previous = request;
        request = null;
        if (previous != null) previous.cancel();
    }
}
