[English](DEMO.md) | 简体中文

# HiFace Android SDK 使用与 Demo 指南

开发 Demo 的应用标识为 `com.hiface.sdk.public`。

<!-- SDK-USER-GUIDE:BEGIN -->
## 支持与安装

当前为内测 Beta 版；北京时间 2026-12-26 零点起停止初始化和工作。
到期日志为“请升级SDK，详情见https://github.com/FaceSDKPro/”。

| 项目 | 当前范围 |
|---|---|
| 最低系统 | Android 6.0 / API 23 |
| ABI | `arm64-v8a`、`armeabi-v7a` |
| 入口 | Java `com.hiface.sdk.HiFaceSdk` |

候选版本为 `0.0.1`，正式上线状态以发布记录为准：

```kotlin
repositories {
    google()
    mavenCentral()
}
dependencies {
    implementation("io.github.facesdkpro:hiface-android:0.0.1")
}
android {
    androidResources { noCompress += "bphfm" }
}
```

最后一项配置应写在宿主 App 模块，使密文模型可直接 mmap 读取。保留 AAR 的 consumer R8 规则和
[SDK 许可](../LICENSE)、[第三方声明](../LICENSE)。

## 公开 API

```text
HiFaceSdk
├── builder(Context)
├── processFrame(Yuv420Frame)
├── processFrame(Yuv420Frame, FaceDetectionConfig)
├── capture()
│   ├── extractFeature(Bitmap, callback)
│   ├── extractFeatureBlocking(Bitmap)
│   ├── fromBitmap(Bitmap, callback)
│   ├── fromBitmapBlocking(Bitmap)
│   └── startCameraCapture(FaceCaptureListener)
├── liveness()
│   └── startCameraLiveness(config, FaceFlowListener)
├── verification()
│   ├── compareBlocking(Bitmap, Bitmap)
│   ├── compare(String, String)
│   └── startCameraVerification(config, FaceFlowListener)
├── search()
│   └── startCameraSearch(config, FaceSearchListener)
├── openSearchDatabase(Context)
└── close()
```

公开类型按 `frame`、`detection`、`capture`、`liveness`、`verification`、`search`、`flow`、`common`
分包。`internal` 和 `RestrictTo(LIBRARY_GROUP)` 成员不属于公开契约；算法与流程共用 Core C ABI v1。

## 创建、检测与关闭

```java
HiFaceSdk sdk = HiFaceSdk.builder(this)
        .lifecycleOwner(this)
        .build();

// 在单一相机分析线程调用。
HiFaceResult<FaceDetectionResult> result = sdk.processFrame(frame);
```

推荐页面级实例。`build()` 异步加载检测模型；能力模型按需准备，实时帧未就绪时返回 `NOT_READY`。
绑定 `LifecycleOwner` 后销毁时自动关闭，未绑定时手工调用 `sdk.close()`。
关闭和 `FaceRequest.cancel()` 会禁止旧回调，在途 Native 推理完成后释放资源，不阻塞页面销毁。

默认检测返回最多一张脸的框、置信度和五点；需要多人或轮廓/头姿时按帧配置：

```java
FaceDetectionConfig detection = FaceDetectionConfig.builder()
        .maxFaces(10)
        .detailedLandmarks(true)
        .build();
HiFaceResult<FaceDetectionResult> result = sdk.processFrame(frame, detection);
```

`maxFaces` 为 1..10，详细检测默认关闭；关闭时 mesh/pose 为空。检测配置仅控制公开检测结果，
采集、活体和验证自动准备所需能力。搜索运行时返回选中脸的框和五点，身份及评分由搜索监听器交付。

## 特征与采集

```java
sdk.capture().extractFeature(bitmap, result -> {
    if (result.isSuccess()) {
        String feature = result.requireValue();
        // 保存特征，或用于 1:1 / 人脸库查询。
    } else {
        HiFaceError error = result.requireError();
    }
});
```

需要对齐图时调用 `fromBitmap(bitmap, callback)`：结果提供 `getFeature()` 和 `getAlignedFace()`。
预览为独立的 333×333 Bitmap，每次 getter 都新建图片，应只取一次并及时释放。
静态入口选择最大脸，宽高均须至少 100 px；无脸或过小分别返回 `IMAGE_NO_FACE` / `IMAGE_FACE_TOO_SMALL`，
不执行活体或头姿门禁。图片不自动缩放，奇数边只裁去最右列/最下行，处理后每边为 2..4096。

异步入口返回前已复制像素，之后可回收原图；每实例最多一个运行请求和四个等待请求，超出返回 `BUSY`。
批量图片应在自己的单个工作线程逐张调用 `extractFeatureBlocking` 或 `fromBitmapBlocking`；
Blocking 入口借用输入至返回，期间不得回收或修改 Bitmap。

相机引导采集仍需持续送帧：

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

HF1 是固定 604 字符的 Q7/Base64URL 特征表示，不是加密。当前特征空间为 `hiface-feature-new-v1`；
旧模型特征和测试库需重新提取、导入。人脸图片和特征的授权、保护及删除由宿主负责。

## 活体与 1:1 验证

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

空动作列表仍执行七帧双模型静默活体；动作最多四步，允许重复。默认拒绝多人，
`allowMultipleFaces(true)` 允许处理主目标，但不额外保证动作前后的身份连续性。
活体业务拒绝通过 `onResult` 返回，技术失败通过 `onError` 返回；可空分数/图片表示本轮未产生该项，不能按零值解释。

已有 HF1 用 `verification().compare(left, right)` 同步比较；直接比图用工作线程上的 `compareBlocking`。
动态验证配置参考特征后启动：

```java
FaceVerificationConfig config = FaceVerificationConfig.builder()
        .referenceFeature(referenceFeature)
        .threshold(0.80f)
        .enableSilentLiveness(true)
        .actions(Arrays.asList(FaceAction.BLINK, FaceAction.NOD_HEAD))
        .build();
sdk.verification().startCameraVerification(config, listener);
```

采集、活体、验证和搜索共享一个相机流程槽，不能同时启动。相似度不是身份概率，
放行依据为最终业务结论；完整接入示例见 [FaceVerificationActivity](../demo/src/main/java/com/hiface/sdk/demo/verification/FaceVerificationActivity.java)。

## 人脸库与连续搜索

`HiFaceSdk.openSearchDatabase(context)` 独立开库，不初始化模型；SDK 管理应用私有路径。
所有库操作在工作线程执行，显式打开的连接由调用方关闭；连续搜索的连接由 Session 自动管理。

| 操作 | 用途 |
|---|---|
| `saveFeature` / `saveFeatures` | 按 Face ID 覆盖；批量每批最多 1000 条 |
| `contains` / `get` | 主键检查 / 返回完整 HF1 |
| `list` / `listRecent` | 元数据分页，不读取特征 |
| `listFeatures` | 完整特征分页导出 |
| `updateMetadata` | 只改 group/tag；null 保留、空串清空 |
| `search` | group/tag 过滤与精确 Top-K |
| `releaseMemory` / `close` | 释放范围缓存 / 关闭连接 |

数据库保存原始 450 字节 Q7 payload，返回 HF1 不重复量化；压缩不提供数据库加密。
`FaceFeatureFormat.FEATURE_SPACE_ID` 用于校验服务器特征兼容性，批量输入使用 `FaceSearchFeatureEntry`。

连续搜索使用 `search().startCameraSearch(config, listener)`，继续通过 `processFrame` 送帧。
Session 支持 `pause()`、`resume()`、`setConfig()`、`close()`；暂停释放范围缓存，恢复前重新预热，模型继续复用。
1:N 可启用同帧 S/M 静默活体，M:N 不执行活体；两者都不运行 468 点/头姿，要求人脸宽高均至少 100 px。
`frameId` 关联同次采样，未评分不表示未匹配；业务先看 `endReason`，`SPOOF_DETECTED` 即使命中身份也不能放行。
完整监听示例见 [FaceSearchActivity](../demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchActivity.java)。

## 帧、线程与错误

- `Yuv420Frame` 使用三平面 DirectByteBuffer，填写真实 stride、range、matrix、旋转和镜像。
  输入须为正偶数，长边最多 1920、短边最多 1080，旋转仅为 0/90/180/270；返回后不再借用 Buffer。
- 单线程送入最新帧并使用 `KEEP_ONLY_LATEST` 或等价背压；`NOT_READY` 表示当前帧未处理，应释放并继续送帧。
  连续 10 秒无人脸后按 200 ms 目标节奏分析，检出人脸后恢复；待机跳帧也使用 `NOT_READY`。
- SDK 异步回调统一在 API 返回后投递主线程；回调中不要执行耗时任务。
- `HiFaceResult` 成功时用 `requireValue()`，失败时用 `requireError()`；业务依赖稳定 `code`，
  `message` / `cause` 仅用于诊断。模型初始化失败保留原错误，不会一直退化为 `NOT_READY`。
- 技术错误与流程终态分开处理；`NOT_MATCHED`、`SPOOF_DETECTED`、超时等业务结论以 `outcome` / `endReason` 为准。

相机结果为旋转后、未镜像的像素坐标，预览缩放、裁剪和前摄镜像由宿主统一映射。
CameraX 适配与相机设置见下方示例入口；业务应记录实际采集/分析 FPS 与稳态耗时。

<!-- SDK-USER-GUIDE:END -->

## 运行 Demo

用 Android Studio 打开 `platforms/android`，在 ARM 手机运行 `demo` 并允许相机权限。首页提供检测、采集、活体、1:1 验证、搜索、图片比对和相机设置，并显示系统版本与设备型号。

| 模块 | 示例入口 |
|---|---|
| 相机 | [CameraPreviewFragment](../demo/src/main/java/com/hiface/sdk/demo/camera/CameraPreviewFragment.java) |
| 搜索 | [FaceSearchActivity](../demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchActivity.java) |
| 人脸库 | [FaceSearchLibraryActivity](../demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchLibraryActivity.java) |

标准档更省性能，高清适合较远人脸，不支持时自动回退。仅在标记与预览左右相反时开启镜像校正。修改参数后重新进入相机页。

## 语言与导入

系统地区为 CN/HK/MO/TW 时显示简体中文，其余显示英文；修改地区后重启 Demo。SDK 诊断保持中文，Demo 按错误码显示中英文提示。系统权限弹窗遵循系统设置。

`features_10000.json` 为 1 万条离线 HF1 特征；`images_1000.json` 为 1 千张网络图片清单，仅供演示。 这些文件不进入 SDK AAR。图片最多并发下载 5 张，串行提取，每 100 条成功特征保存一次；特征导入每 1000 条保存一次。

进度区分已处理和已保存数量。导入时返回，可选择“继续导入”或“停止并退出”。停止后完成当前操作、保存尾批，再显示已保存和失败数量。单张失败跳过；写库失败保留之前已保存的批次。关闭 SDK 或数据库前等待导入收尾。

## 数据安全

上线前替换演示身份、特征和图片地址。HF1 是编码，SDK SQLite 未加密；宿主负责数据保护、保留和删除。1:1 基准由 Demo 使用 MMKV 保存，固定演示密钥需替换为业务密钥。

模型加载失败时检查 SDK 模型资源；相机尺寸不支持时选择实际可用的偶数尺寸，且不超过 1920×1080。在目标手机验证权限恢复、旋转、前后台切换和各功能流程。
