# HiFace Android SDK API 指南

## 快速开始

使用 Android 6.0 / API 23 或更高版本的 ARM64 或 ARMv7 设备。

当前接入示例版本为 `0.8.14`。将随包提供的 `maven-repository` 加入项目的 Gradle 仓库配置，保留 `google()` 和 `mavenCentral()` 下载依赖。通过 Maven Central 获取 HiFace 前请确认同版本已上架。在应用模块添加：

```kotlin
dependencies {
    implementation("io.github.facesdkpro:hiface-android:0.8.14")
}
android {
    androidResources { noCompress += "bphfm" }
}
```

保留 [SDK 许可](../LICENSE) 和 AAR 自带的 R8 规则。在 Java 应用中用下面的类替换启动 Activity，包名与 Manifest 一致。在支持的设备运行，空白图应显示 `IMAGE_NO_FACE`，无需相机权限。

```java
package com.example.hiface;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.Bundle;
import android.widget.TextView;
import com.hiface.sdk.HiFaceSdk;

public final class MainActivity extends Activity {
    private HiFaceSdk sdk;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        TextView output = new TextView(this);
        setContentView(output);

        sdk = HiFaceSdk.builder(this).build();
        Bitmap image = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888);
        image.eraseColor(Color.BLACK);
        sdk.capture().extractFeature(image, result -> output.setText(result.isSuccess()
                ? "Feature extracted"
                : result.requireError().getCode().name()));
        image.recycle();
    }

    @Override
    protected void onDestroy() {
        sdk.close();
        super.onDestroy();
    }
}
```

## API 参考

```text
HiFaceSdk
├── builder(Context)
├── processFrame(Yuv420Frame)
├── processFrame(Yuv420Frame, FaceDetectionConfig)
├── processFrame(RgbIrFrame)
├── capture()
├── liveness()
├── verification()
├── search()
├── openSearchDatabase(Context)
└── close()
```

### 人脸检测

调用 `sdk.processFrame(frame, config)`。成功返回人脸框、置信度和关键点，无人脸时返回空列表。坐标以旋转后、未镜像的画面为准。

| `FaceDetectionConfig` 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `maxFaces` | 1–10，默认 1 | 限制返回的人脸数。 |
| `detailedLandmarks` | 布尔值，默认关闭 | 开启后附带详细轮廓和头部角度。 |

相机分析帧要求偶数宽高，长边不超过 1920、短边不超过 1080，旋转为 0°、90°、180° 或 270°。
提供 `Yuv420Frame` 的实际平面步长、色彩范围和矩阵及旋转角度。同步调用返回前保持缓冲区有效。连续搜索时从搜索监听器读取身份与分数。

### 人脸录入与照片采集

| 接口 | 返回结果 |
|---|---|
| `capture().extractFeature(bitmap, callback)` | 提取最大人脸的特征，无人脸返回 `IMAGE_NO_FACE`，人脸宽或高不足 100 像素返回 `IMAGE_FACE_TOO_SMALL`。 |
| `capture().fromBitmap(bitmap, callback)` | 返回 `getFeature()` 和可选对齐预览 `getAlignedFace()`。应用确认录入后再保存特征。 |
| `capture().facesFromBitmap(bitmap, callback)` | 返回最多 10 张脸的位置及各自的采集结果。没有人脸时成功返回空列表，小脸只影响对应条目。 |
| `capture().startCameraCapture(listener)` | 引导用户采集人脸，通过回调交付结果。 |

照片调用前先处理图像方向。每个 SDK 的静态队列可同时处理一个任务，另有四个等待名额。批量处理时逐张提交。照片接口无需相机权限，无活体判定。

```java
FaceRequest request = sdk.capture().startCameraCapture(new FaceCaptureListener() {
    @Override
    public void onProgress(@NonNull FaceFlowProgress progress) {
        // 更新引导。
    }
    @Override
    public void onResult(@NonNull FaceCaptureResult capture) {
        // 用户确认后保存 capture.getFeature()。
    }
    @Override
    public void onError(@NonNull HiFaceError error) {
        // 处理技术错误。
    }
});
```

### 活体与 1:1 验证

分别使用 `liveness().startCameraLiveness(config, listener)` 和 `verification().startCameraVerification(config, listener)` 启动流程，再持续送入相机帧。已有两份特征时，`verification().compare(left, right)` 返回 0–1 的相似度。相似度仅反映特征接近程度。

| 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `referenceFeature` | 1:1 验证必填 | 传入已录入的人脸特征。 |
| `threshold` | 0–1，默认 0.80 | 1:1 相似度门槛。低于门槛时，完成比对的流程返回身份不匹配。 |
| `actions` | 0–4 步，默认空 | 活体接口空动作时执行静默活体。 |
| `enableSilentLiveness` | 布尔值，1:1 验证默认关闭 | 开启后还要求静默活体通过。 |
| `allowMultipleFaces` | 布尔值，默认关闭 | 控制流程是否允许画面中出现多人。 |
| `actionTimeoutMillis` | 2,000–30,000 ms，默认 3,000 ms | 每步动作时限。 |
| `faceAcquisitionTimeoutMillis` | 1,000–60,000 ms，默认 10,000 ms | 首次取脸时限。 |

RGB 静默活体使用 SDK 固定门槛 0.90。活体和验证的 `onResult` 会交付通过或拒绝的结果，先读 `getOutcome()`。只有本轮执行了对应步骤才会返回相似度或活体分数。独立近红外活体使用 `liveness().evaluateInfrared(frame, threshold)`，传入真实 GRAY8 红外帧、图中人脸框和按设备标定的 0–1 阈值。阈值必填。

```java
FaceFlowListener listener = new FaceFlowListener() {
    @Override
    public void onProgress(@NonNull FaceFlowProgress progress) {
        // 更新动作或静默活体引导。
    }
    @Override
    public void onResult(@NonNull FaceFlowResult result) {
        // 先判断 result.isPassed() / result.getOutcome()，再读取附带数据。
    }
    @Override
    public void onError(@NonNull HiFaceError error) {
        // 处理技术错误。
    }
};
sdk.liveness().startCameraLiveness(FaceLivenessConfig.builder().build(), listener);
```

### 人脸库与搜索

用 `HiFaceSdk.openSearchDatabase(context)` 打开独立人脸库。通过 `saveFeature` 或 `saveFeatures` 按 Face ID 新增或更新，单批可保存 1–1,000 条。用 `search(feature, config)` 按特征查库。`list` / `listRecent` 返回元数据，`listFeatures` 分页读取含特征的记录。由调用方关闭显式打开的人脸库。在工作线程执行人脸库操作。

| 查库参数 | 范围与默认值 | 用途 |
|---|---|---|
| Face ID、`group`、`tag` | Face ID 为 1–1024 个 UTF-8 字节，分组和标签各最多 1024 字节，均不允许 NUL | 精确按分组和标签筛选，两项均指定时同时匹配，均未指定时搜索全库。 |
| `topK` | 1–100，默认 1 | 最多返回的匹配数。 |
| `threshold` | 0–1，默认 0.80 | 精确查库的相似度下限，低于门槛的记录不会返回。没有匹配时返回空列表。 |

连续搜索使用 `search().startCameraSearch(config, listener)`，它自行管理人脸库连接。

| 连续搜索参数 | 范围与默认值 | 用途 |
|---|---|---|
| `mode`、`needLiveness` | 默认单人且开启活体，多人模式不支持活体 | 决定每帧处理最大人脸还是多人。 |
| `threshold` | 0.75–0.85，默认 0.80 | 连续搜索的身份门槛。 |
| `searchIntervalMillis` | 0–3,000 ms，默认 0 | 匹配成功后到下一轮的间隔。 |
| `searchTimeoutMillis` | 1,000–3,000 ms，默认 3,000 ms | 从首次选中人脸开始计算的单轮时限。 |
| `maxFacesPerFrame` | 1–5，默认 3 | 多人模式处理上限。单人模式仅处理最大脸。 |

先看 `getEndReason()`。即使达到相似度门槛，`SPOOF_DETECTED` 也表示拒绝。`getFrameId()` 标识同一次采样。`getFrameJpeg()` 是可选的结束帧整图，绘制人脸框时按原始帧尺寸换算。

人脸特征应原样保存。更换为不兼容的模型时，从原照片重新提取并导入。应用负责取得用户同意，以及保护和删除照片和特征。

查库参数由 `FaceSearchConfig.builder().build()` 提供默认值。

## 错误处理与资源释放

通过 `HiFaceResult.isSuccess()` 判断后，再读取 `requireValue()` 或 `requireError().getCode()`。构建器参数无效会抛出 `IllegalArgumentException`。SDK 回调异步投递到主线程。页面复用同一个 SDK，退出时调用 `close()`，也可在主线程通过 `builder(...).lifecycleOwner(owner)` 自动关闭。

| 情况 | 处理方式 |
|---|---|
| `NOT_READY` | 模型初始化、运行时正忙或相机跳帧时，丢弃当前帧，继续送入最新帧。 |
| `BUSY` | 等静态任务完成，或先结束当前相机流程。 |
| `INVALID_ARGUMENT` | 检查参数、帧格式与缓冲区。 |
| `LICENSE_EXPIRED` | 核对授权有效期，必要时联系 SDK 支持。 |
| `CLOSED` | 停止向此实例继续提交任务。 |

采集、活体、验证和连续搜索共用一个相机流程槽。切换功能或退出页面时，先停止送帧，再取消请求或关闭搜索，然后关闭 SDK。`onError` 用于技术失败，业务结果读取对应结论。

当前模型不支持 12 周岁以下儿童人脸识别，不能用于金融场景。室外人脸搜索使用宽动态范围大于 100 dB 的相机。
