package com.hiface.sdk.demo.camera;

import com.hiface.sdk.common.FaceRequest;
import java.util.Objects;

/**
 * Ownership of one camera request. The main thread mutates state; the analysis thread only reads
 * whether frames may be submitted.
 *
 * 单次相机请求的所有权。状态在主线程修改，分析线程只读取 active。
 */
public final class CameraFlowRequest {
    /**
     * The Demo supports API 23 and does not depend on java.util.function.Supplier, introduced in API 24.
     *
     * Demo 支持 API 23，不依赖 API 24 才提供的 java.util.function.Supplier。
     */
    @FunctionalInterface
    public interface Starter {
        FaceRequest start();
    }

    // The SDK may call back before start() returns its handle. STARTING admits frames in that interval.
    private static final FaceRequest STARTING = () -> {
    };
    private volatile FaceRequest request;

    boolean isActive() {
        return request != null;
    }

    boolean start(Starter starter) {
        if (isActive()) {
            return false;
        }
        request = STARTING;
        try {
            FaceRequest next = Objects.requireNonNull(starter.start(), "request");
            // A synchronous completion may already have started a retry with its own handle.
            if (request == STARTING) {
                request = next;
            } else {
                next.cancel();
            }
            return true;
        } catch (RuntimeException | Error error) {
            if (request == STARTING) {
                request = null;
            }
            throw error;
        }
    }

    boolean finish() {
        if (!isActive()) {
            return false;
        }
        request = null;
        return true;
    }

    void cancel() {
        FaceRequest previous = request;
        request = null;
        if (previous != null) {
            previous.cancel();
        }
    }
}
