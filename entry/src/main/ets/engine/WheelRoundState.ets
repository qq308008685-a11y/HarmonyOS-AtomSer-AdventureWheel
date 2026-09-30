import { TaskItem } from '../model/TaskItem';

/**
 * 单局转盘状态规则：已处理的任务不再参与本局抽取。
 */
export class WheelRoundState {
  static availableIndices(tasks: TaskItem[], completedTaskIds: string[]): number[] {
    const indices: number[] = [];
    tasks.forEach((task: TaskItem, index: number) => {
      if (completedTaskIds.indexOf(task.id) < 0) {
        indices.push(index);
      }
    });
    return indices;
  }

  static pickAvailableIndex(tasks: TaskItem[], completedTaskIds: string[], randomValue: number): number {
    const indices = WheelRoundState.availableIndices(tasks, completedTaskIds);
    if (indices.length === 0) {
      return -1;
    }
    const normalized = Math.max(0, Math.min(randomValue, 0.999999));
    return indices[Math.floor(normalized * indices.length)];
  }
}
