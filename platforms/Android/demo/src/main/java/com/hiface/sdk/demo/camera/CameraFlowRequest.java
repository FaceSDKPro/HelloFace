package com.hiface.sdk.demo.camera;

import com.hiface.sdk.common.FaceRequest;
import java.util.Objects;

/** Main-thread ownership of one camera request. */
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

    // Reserve ownership so the SDK can complete synchronously before returning a handle.
    private static final FaceRequest STARTING = () -> {
    };
    private FaceRequest request;

    boolean isActive() {
        return request != null;
    }

    /** Return true when the caller can start feeding this request's frames. */
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
                return true;
            }
            next.cancel();
            return false;
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
