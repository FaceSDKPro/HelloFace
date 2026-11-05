# 数据处理与隐私合规说明

[English](DATA_PROCESSING_AND_PRIVACY.md) · **简体中文** · [Español](DATA_PROCESSING_AND_PRIVACY.es.md) · [Português (Brasil)](DATA_PROCESSING_AND_PRIVACY.pt-BR.md)<br>
[Français](DATA_PROCESSING_AND_PRIVACY.fr.md) · [Deutsch](DATA_PROCESSING_AND_PRIVACY.de.md) · [日本語](DATA_PROCESSING_AND_PRIVACY.ja.md) · [한국어](DATA_PROCESSING_AND_PRIVACY.ko.md)

[返回首页](../../README.zh-CN.md)

适用范围：HelloFace SDK。本说明面向 SDK 集成方，介绍现有数据流程及接入方的数据管理责任，不替代接入方 App 或服务的隐私政策，也不表示任何具体部署已通过合规认证。

## 数据在何处处理

SDK 在运行设备上进行人脸检测、采集、特征提取、活体与比对、搜索计算，SDK本身不收集传输任何数据。
SDK 层不声明网络权限或网络能力，相机权限、相册选择和网络权限的用途应由宿主应用说明。 

## 涉及哪些数据

| 数据 | 用途和处理边界 |
|---|---|
| 相机帧、选择或导入的照片、人脸区域 | 检测、采集、活体、特征提取及页面预览；是否额外保存原图由应用实现决定 |
| 人脸特征、记录 ID、分组和标签 | 本机图库录入、查询和比对；录入或导入后可持久保存在终端本地 |
| SDK 本机运行状态、应用设置、日志 | 支持运行和排障；与业务人脸库分别管理，日志也需遵循最小化原则 |
| 操作系统版本，硬件型号 | 支持SDK内部根据不同系统和硬件配置选择更优化的运行方式 |


## SDK 接入方的责任

接入方应根据应用场景、数据处理方式及部署国家或地区的适用要求，负责集成 SDK 的 App 或服务中人脸数据的合法、合规处理与管理，包括数据的收集、使用、存储、访问、共享、传输和删除。接入方还应向用户提供清晰的数据处理说明、相关请求的受理渠道，并负责处理这些请求。

SDK 当前采用离线、本机处理架构，将人脸数据计算保留在设备内，从 SDK 架构层面尽可能保护用户数据，减少向外部服务暴露人脸数据的风险。App 或服务自行实现的数据保存、云端同步或其他处理流程，应由接入方落实相应的权限控制、存储保护、保存与删除机制，以及适用的告知、授权和安全管理措施。

当前 SDK 不支持 12 周岁以下儿童人脸识别，不能用于金融相关场景。

如需 SDK 集成支持或反馈 SDK 安全问题，接入方可联系 [FaceAISDK.Service@gmail.com](mailto:FaceAISDK.Service@gmail.com)。
