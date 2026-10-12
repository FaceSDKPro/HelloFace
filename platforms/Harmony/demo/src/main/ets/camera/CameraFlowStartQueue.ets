/** 跨页面串行启动 SDK 相机业务；旧请求返回句柄并完成取消后，才允许下一页启动。 */
export class CameraFlowStartQueue {
  private static tail: Promise<void> = Promise.resolve();

  static run<T>(start: () => Promise<T>, isCurrent: () => boolean,
    discard: (result: T) => void): Promise<T | undefined> {
    const task: Promise<T | undefined> = CameraFlowStartQueue.tail.then(async (): Promise<T | undefined> => {
      if (!isCurrent()) return undefined;
      const result: T = await start();
      if (!isCurrent()) {
        discard(result);
        return undefined;
      }
      return result;
    });
    CameraFlowStartQueue.tail = task.then(() => {}, () => {});
    return task;
  }
}
