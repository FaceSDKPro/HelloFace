# HiFace Android SDK 使用与 Demo 指南

Demo 的应用标识为 `com.hiface.sdk.public`。

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

## Demo 能力与代码入口

| 能力 | 示例入口 | 集成时重点 |
| --- | --- | --- |
| 实时检测 | [FaceDetectionActivity](../demo/src/main/java/com/hiface/sdk/demo/detection/FaceDetectionActivity.java) | 普通逐帧检测、坐标绘制、多人和详细关键点 |
| 静态 1:1 | [FaceComparisonActivity](../demo/src/main/java/com/hiface/sdk/demo/comparison/FaceComparisonActivity.java) | 选图、解码、最大脸特征提取和相似度 |
| 人脸录入 | [FaceEnrollmentActivity](../demo/src/main/java/com/hiface/sdk/demo/verification/FaceEnrollmentActivity.java) | 引导采集、用户确认和参考特征保存 |
| 动态 1:1 | [FaceVerificationActivity](../demo/src/main/java/com/hiface/sdk/demo/verification/FaceVerificationActivity.java) | 参考特征、动作/静默活体和流程终态 |
| 活体检测 | [FaceLivenessActivity](../demo/src/main/java/com/hiface/sdk/demo/liveness/FaceLivenessActivity.java) | 动作挑战、静默活体和取消流程 |
| 人脸搜索 | [FaceSearchActivity](../demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchActivity.java) | 1:N/M:N Session、进度、结果和暂停恢复 |
| 搜索库录入 | [FaceSearchEnrollmentActivity](../demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchEnrollmentActivity.java) | 采集 HF1、Face ID、分组和覆盖确认 |
| 搜索库管理 | [FaceSearchLibraryActivity](../demo/src/main/java/com/hiface/sdk/demo/search/FaceSearchLibraryActivity.java) | 分页、查询、删除和批量导入 |

建议先阅读 [DemoHomeActivity](../demo/src/main/java/com/hiface/sdk/demo/DemoHomeActivity.java) 的功能入口，
再阅读 [CameraPreviewFragment](../demo/src/main/java/com/hiface/sdk/demo/camera/CameraPreviewFragment.java) 的 CameraX
送帧方式，最后查看所需能力页面。业务工程可以复用接入思路，无需照搬 Demo 的页面或存储结构。

两种录入、活体和动态 1:1 页共用
[CameraFlowActivity](../demo/src/main/java/com/hiface/sdk/demo/camera/CameraFlowActivity.java)：绑定相机/引导视图，
按需创建页面 SDK，首帧就绪后允许启动一个请求，终态暂停分析，后台取消未完成请求。
页面仍显式调用对应 SDK API，并独立管理结果、确认照片和保存逻辑；前后台切换不丢弃已展示的弹窗。
动态 1:1 在选好参考特征后才初始化 SDK，空库退出不启动相机。实时检测和搜索 Session 不使用单次请求封装。
搜索库管理以 Adapter 已提交的列表作为唯一界面数据源，按数据库偏移分页；合并生成新快照，
不原地修改正在显示的列表，Diff 提交完成后才继续预加载下一页。

## 摄像头参数设置

Demo 首页提供分辨率和额外坐标镜像设置，用于展示设备兼容处理：

- 默认分析分辨率为 640×480。高分辨率档位从设备实际支持的 YUV 尺寸中选择接近 1280×720 的候选，
  失败时继续回退到可用尺寸；送入 SDK 的宽高始终来自实际 `ImageAnalysis` 帧。
- Preview 与 ImageAnalysis 的尺寸可能不同，不能用预览控件尺寸代替分析帧尺寸。
- 部分定制设备或外接摄像头的坐标方向异常时，可以开启额外坐标镜像；正常前摄不应重复镜像。
- 搜索页活跃时请求 15 FPS，连续 10 秒无人脸后请求 5 FPS；优先设置支持目标的窄 AE 范围。
  不支持目标时请求较低的受支持硬件回退，并在像素包装前保留分析门禁；HAL 仍可能以更高帧率采集。

出现“不支持的相机分析分辨率”时，先确认传入的是设备实际输出尺寸，并改用 640×480。随后检查宽高是否
为偶数、是否超过 SDK 上限，以及 Preview + ImageAnalysis 的流组合是否被设备支持。设备差异应在目标机型验证，并记录 Preview 与 Analysis 的实际尺寸和组合。

## 人脸搜索与演示数据

`src/main/assets/face_search/` 内有两份演示清单：

- `features_10000.json`：新模型从 `face1W_333` 的 10,000 张真实人脸 PNG 提取的 HF1 特征，可离线导入；Face ID 对应图片文件名去掉 `.png`。
- `images_1000.json`：1,000 个 HTTPS 图片 URL，导入时需要网络并逐张提取特征。

当前模型使用 `hiface-feature-new-v1`，MMKV 参考特征按空间隔离，旧空间数据不参与比对。
本次名称清理未改变模型或一万条特征值；其他模型的旧特征不能混用。
JSON 保留 `group_test` / `group_A` / `group_B` 分组，数据来源与模型哈希记录在 `source`；
识别效果需使用对应人员的独立照片或重新采集验证，不能仅凭入库图片自匹配判断。

两份 JSON 只打包进 Demo APK，不进入 SDK AAR。它们只用于验证 API 和页面流程，生产环境必须换成
已获授权的业务数据、自己的服务地址以及可恢复的同步任务。Face ID、分组、标签、删除和保留期限也应由
业务系统定义。

## 数据安全

Demo 使用 MMKV 保存相机设置和 1:1 参考特征。代码中的固定加密密钥只用于演示 MMKV API，生产 App
必须改为 Android Keystore 或自身密钥系统，并根据业务要求实现用户授权、访问控制、备份排除、保留期限
和删除能力。人脸图片、HF1 特征、搜索结果和密钥都不应写入普通日志。

## 常见问题

| 现象 | 排查方式 |
| --- | --- |
| SDK 一直返回 `NOT_READY` | 初始化和模型加载是异步的；继续提交最新帧，并确认没有重复创建/关闭 SDK |
| 检测框左右颠倒或偏移 | 只在 Overlay 处理前摄镜像，使用结果中的图像宽高和与预览一致的缩放/裁剪策略 |
| 相机能预览但没有分析结果 | 检查 Analyzer 是否收到帧、实际格式/尺寸/旋转是否正确，以及帧是否在调用完成前被关闭 |
| 活体或验证无法启动 | 确认上一请求或搜索 Session 已取消/关闭，并等待当前页面真正开始出帧 |
| 搜索没有身份结果 | 先确认数据库已录入 HF1，再检查模式、分组、阈值和活体终态；不能只看单帧最高分放行 |
| Release 构建缺模型或 Native 库 | 确认依赖的是完整正式 AAR，并检查宿主的 ABI、R8 和资源打包配置 |
