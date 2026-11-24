[English](SDK.md) | **简体中文**

# HiFace Android SDK API 指南

## 快速开始

使用 Android 6.0 / API 23 或更高版本的 ARM64 或 ARMv7 设备。

当前接入示例版本为 `0.8.16`。将随包提供的 `maven-repository` 加入项目的 Gradle 仓库配置，保留 `google()` 和 `mavenCentral()` 下载依赖。通过 Maven Central 获取 HiFace 前请确认同版本已上架。在应用模块添加：

```kotlin
dependencies {
    implementation("io.github.facesdkpro:hiface-android:0.8.16")
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

创建 SDK 后会在后台初始化；静态图片请求会等待就绪，相机初始化期间返回 `NOT_READY` 时释放当前帧并继续送入新帧。SDK 不打开相机，也不申请宿主的相机权限。

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

`Yuv420Frame` 的三平面均须为直接 `ByteBuffer`，步长按相机平面填写。`range` 选择 `VIDEO` 或 `FULL`，`matrix` 选择 `BT601` 或 `BT709`，均以采集元数据为准。串行送帧，预览镜像由应用处理。开启详细关键点后，`getMesh()` 与 `getHeadPose()` 仍须分别判空，头部角度单位为度。

### 人脸录入与照片采集

| 接口 | 返回结果 |
|---|---|
| `capture().extractFeature(bitmap, callback)` | 提取最大人脸的特征，无人脸返回 `IMAGE_NO_FACE`，人脸宽或高不足 100 像素返回 `IMAGE_FACE_TOO_SMALL`。 |
| `capture().fromBitmap(bitmap, callback)` | 返回特征 `getFeature()` 和对齐预览 `getAlignedFace()`。应用确认录入后再保存特征。 |
| `capture().facesFromBitmap(bitmap, callback)` | 返回最多 10 张脸的位置及各自的采集结果。没有人脸时成功返回空列表，小脸只影响对应条目。 |
| `capture().startCameraCapture(listener)` | 引导用户采集人脸，通过回调交付结果。 |

照片调用前先处理图像方向。每个 SDK 的静态队列可同时处理一个任务，另有四个等待名额。批量处理时逐张提交。照片接口无需相机权限，无活体判定。

只要特征时优先使用 `extractFeature`；批量任务在工作线程逐张调用 `extractFeatureBlocking`，返回前不得修改或回收输入。每次 `getAlignedFace()` 都创建独立 `Bitmap`，应用不用时释放，避免反复取图。严格单人录入须用 `facesFromBitmap` 确认结果恰好一条且该条 `getCapture().isSuccess()`；最大脸接口本身不会拒绝多人照片。

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
| `threshold` | 建议 0.75–0.85，默认 0.80 | 1:1 相似度门槛。低于门槛时，完成比对的流程返回身份不匹配。 |
| `actions` | 0–4 步，默认空 | 活体接口空动作时执行静默活体。 |
| `enableSilentLiveness` | 布尔值，1:1 验证默认关闭 | 开启后还要求静默活体通过。 |
| `allowMultipleFaces` | 布尔值，默认关闭 | 控制流程是否允许画面中出现多人。 |
| `actionTimeoutMillis` | 2,000–30,000 ms，默认 3,000 ms | 每步动作时限。 |
| `faceAcquisitionTimeoutMillis` | 1,000–60,000 ms，默认 10,000 ms | 首次取脸时限。 |

`actions` 按列表顺序执行，允许重复，支持 `SHAKE_HEAD`（摇头）、`NOD_HEAD`（点头）、`BLINK`（眨眼）、`MOUTH_OPEN`（张嘴）。1:1 验证在动作为空且 `enableSilentLiveness=false` 时只验证身份，不包含活体。

相似度建议范围为 0.75–0.85，默认配置值为 0.80；1:1 验证和按特征查库的 API 实际允许 0–1，相机连续搜索仅允许 0.75–0.85。

RGB/IR 活体建议门槛为 0.80–0.99，建议值为 0.90。当前 RGB 静默活体固定使用 0.90，未开放门槛设置；IR 门槛须显式传入，没有隐式默认值。活体和验证的 `onResult` 会交付通过或拒绝的结果，先读 `getOutcome()`。只有本轮执行了对应步骤才会返回相似度或活体分数。独立近红外活体使用 `liveness().evaluateInfrared(frame, threshold)`，传入真实 GRAY8 红外帧、图中人脸框和按设备标定的阈值（建议 0.80–0.99，初始值 0.90，API 实际允许大于 0 且不超过 1）。阈值必填。

`FaceFlowResult.isPassed()` 才表示通过；`getSimilarity()`、`getLivenessScore()` 未产生时为 `null`，不能当作 0。`getAlignedFace()` 与 `getFrameJpeg()` 都可能为空，图片存在不代表通过。`getFrameWidth()` / `getFrameHeight()` 是 JPEG 的像素尺寸，无图时为 0；画框仍需按原检测图尺寸换算。

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

单库最多 50,000 条。`saveFeatures` 每批全部成功或全部回滚；同一批重复 Face ID 以最后一条为准。`contains` 成功值为是否存在，`get` 不存在时返回 `NOT_FOUND`，`delete` 成功值为是否实际删除。

分页的 `offset` 从 0 开始，`limit` 为 1–1,000；`list` / `listFeatures` 按 Face ID 排序，`listRecent` 按更新时间倒序。`updateTimeMillis` 为 Unix 毫秒时间，0 使用当前时间，负数无效。`updateMetadata` 的分组或标签传 `null` 表示保留、空串表示清空，至少指定一项。

**人脸记录与筛选**

| 参数 | 范围与默认值 | 用途 |
|---|---|---|
| Face ID | 必填，1–1024 个 UTF-8 字节，不允许 NUL，无默认值 | 应用指定的记录标识。保存相同 ID 会更新该记录；不是分组或标签筛选条件。 |
| `group` | 可选，最多 1024 个 UTF-8 字节，不允许 NUL；默认不筛选 | 人脸所属分组。查询时精确匹配该分组，`null` 或空串表示不限分组。 |
| `tag` | 可选，最多 1024 个 UTF-8 字节，不允许 NUL；默认不筛选 | 应用自定义的业务标签。查询时精确匹配该标签，`null` 或空串表示不限标签。 |

同时指定分组和标签时，两项都必须匹配；均不指定时搜索全库。

**按已有特征查库（`FaceSearchConfig`）**

| 参数 | 范围与默认值 | 用途 |
|---|---|---|
| `topK` | 1–100，默认 1 | 最多返回的匹配数。 |
| `threshold` | 建议 0.75–0.85，默认 0.80 | 仅用于按已有特征查库。返回相似度达到门槛的记录，无匹配时返回空列表；相机连续搜索使用下表的范围。 |

连续搜索使用 `search().startCameraSearch(config, listener)`，它自行管理人脸库连接。

| 连续搜索参数 | 范围与默认值 | 用途 |
|---|---|---|
| `mode` | `SINGLE_FACE` / `MULTI_FACE`，默认 `SINGLE_FACE` | 单人模式只处理最大人脸；多人模式按 `maxFacesPerFrame` 限制处理人数。 |
| `needLiveness` | `true` / `false`；单人默认 `true`，多人默认 `false` | 是否开启 RGB 静默活体；多人模式不能设为 `true`。双目 IR 搜索自动关闭 RGB 活体。 |
| `threshold` | 0.75–0.85（含端点），默认 0.80 | 相机连续搜索的身份匹配门槛；相似度大于等于该值才算身份匹配，活体仍须单独通过。 |
| `searchIntervalMillis` | 0–3,000 ms，默认 0 | 匹配成功后到下一轮的间隔。 |
| `searchTimeoutMillis` | 1,000–3,000 ms，默认 3,000 ms | 从首次选中人脸开始计算的单轮时限。 |
| `maxFacesPerFrame` | 1–5，默认 3 | 多人模式处理上限。单人模式仅处理最大脸。 |

`startCameraSearch` 立即返回 `FaceSearchSession`，准备期间继续送新帧。`pause()` 保留会话及相机流程占用，`resume()` 恢复，`setConfig()` 替换配置并使旧结果失效；切换采集或验证前需 `close()` 搜索会话。`onFrame` 用于显示，业务读取 `onResult`。开库或准备失败修复后可 `resume()`；因 SDK 关闭或流程冲突而被拒绝的会话须重新创建。

先看 `getEndReason()`。即使达到相似度门槛，`SPOOF_DETECTED` 也表示拒绝。`getFrameId()` 标识同一次采样。`getFrameJpeg()` 是可选的结束帧整图，绘制人脸框时按原始帧尺寸换算。

### RGB/IR 双目搜索

仅支持单人搜索。设置 `infraredLiveness` 后自动关闭默认 RGB 活体；不要同时设置 `needLiveness(true)`，否则 `build()` 拒绝配置。下面的 `calibratedRgbToIr` 必须来自实际双相机标定，不能把示例单位矩阵直接用于不同相机。

```java
InfraredSearchConfig infrared = new InfraredSearchConfig(
        0.90f, calibratedRgbToIr, 0.50f, 20, 50, 200);
FaceSearchSessionConfig config = FaceSearchSessionConfig.builder()
        .mode(FaceSearchMode.SINGLE_FACE)
        .infraredLiveness(infrared)
        .threshold(0.80f)
        .build();
// Pass config to sdk.search().startCameraSearch(config, listener).
// Feed each paired RGB/IR sample with sdk.processFrame(pair).
```

以下参数均必填，无默认值。

| 参数 | 范围 | 用途 |
|---|---|---|
| `realThreshold` | 必填；建议 0.80–0.99，初始值 0.90；实际允许 (0,1] | IR 活体门槛，按设备标定。 |
| `normalizedRgbToIr` | 9 个有限数值 | 行优先、非奇异 3×3 矩阵，映射旋转后未镜像的 RGB 到 IR 归一化坐标。 |
| `minimumFaceOverlap` | 大于 0 且不超过 1 | 映射后 RGB 框与 IR 框的交集面积占并集面积的比例门槛。 |
| `minimumFacePixels` | 10–4096 px | IR 人脸最小宽、高。 |
| `maxPairSkewMillis` | 1–200 ms | 两路帧时间戳的最大差值。 |
| `maxFrameAgeMillis` | `maxPairSkewMillis` 至 1,000 ms | 接受帧对时允许的最大帧龄。 |

`RgbIrFrame` 两路时间戳使用 `SystemClock.elapsedRealtime()` 的同一毫秒时钟域；每次打开设备使用新的正数 `sourceId`，同源 `pairId` 和两路序号严格递增。IR 使用真实、正向未镜像的 GRAY8 直接缓冲区；两路像素均保留到 `processFrame(pair)` 返回。无有效 IR 或活体拒绝时不能放行。

人脸特征应原样保存。更换为不兼容的模型时，从原照片重新提取并导入。应用负责取得用户同意，以及保护和删除照片和特征。

查库参数由 `FaceSearchConfig.builder().build()` 提供默认值。

## 错误处理与资源释放

通过 `HiFaceResult.isSuccess()` 判断后，再读取 `requireValue()` 或 `requireError().getCode()`。构建器数值越界会抛出 `IllegalArgumentException`；1:1 配置未设置 `referenceFeature` 时，`build()` 抛出 `IllegalStateException`。SDK 回调异步投递到主线程。页面复用同一个 SDK，退出时调用 `close()`，也可在主线程通过 `builder(...).lifecycleOwner(owner)` 自动关闭。

| 情况 | 处理方式 |
|---|---|
| `NOT_READY` | 模型初始化、运行时正忙或相机跳帧时，丢弃当前帧，继续送入最新帧。 |
| `BUSY` | 等静态任务完成，或先结束当前相机流程。 |
| `INVALID_ARGUMENT` | 检查参数、帧格式与缓冲区。 |
| `LICENSE_EXPIRED` | 核对授权有效期，必要时联系 SDK 支持。 |
| `CLOSED` | 停止向此实例继续提交任务。 |
| `RESOURCE_EXHAUSTED` | 减少并发任务并检查内存、磁盘和容量，处理后再重试。 |
| `DATABASE_ERROR` | 检查人脸库路径、权限及存储状态；保留原数据，避免自动删库。 |
| `INTERNAL_ERROR` | 停止本次请求，记录 SDK 版本及错误码并联系支持。 |

采集、活体、验证和连续搜索共用一个相机流程槽。切换功能或退出页面时，先停止送帧，再取消请求或关闭搜索，然后关闭 SDK。`onError` 用于技术失败，业务结果读取对应结论。

相机帧缓冲区借用到 `processFrame` 返回，返回后才可交还相机；静态图异步采集在方法返回前完成快照。取消会抑制尚未开始的回调，不补发终态；已开始的回调可能完成，应用仍应核对当前页面或请求标识。绑定 `lifecycleOwner` 后在主线程构建，`close()` 也在主线程调用；Fragment 仅服务当前视图时绑定其 View Lifecycle。

当前模型不支持 12 周岁以下儿童人脸识别，不能用于金融场景。室外人脸搜索使用宽动态范围大于 100 dB 的相机。
