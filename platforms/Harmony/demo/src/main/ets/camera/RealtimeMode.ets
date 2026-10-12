/**
 * Demo 页面路由到共享相机宿主时使用的模式；不是 SDK API。
 * 每个枚举值分别对应 Android 的检测、采集、验证、活体、搜索或搜索录入页面。
 */
export enum RealtimeMode {
  DETECTION = 0,
  CAPTURE = 1,
  VERIFICATION = 2,
  LIVENESS = 3,
  SEARCH_SINGLE = 4,
  SEARCH_MULTI = 5,
  SEARCH_ENROLLMENT = 6
}
