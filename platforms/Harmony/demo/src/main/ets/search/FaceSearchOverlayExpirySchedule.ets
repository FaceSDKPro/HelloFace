/** 延长期限保留较早检查；提前到期或清空才替换，检查后再安排当前期限。 */
export class FaceSearchOverlayExpirySchedule {
  private deadline: number = 0;

  replace(deadline: number): boolean {
    if (this.deadline === deadline || (this.deadline > 0 && deadline >= this.deadline)) return false;
    this.deadline = deadline;
    return true;
  }

  clear(): void {
    this.deadline = 0;
  }
}
