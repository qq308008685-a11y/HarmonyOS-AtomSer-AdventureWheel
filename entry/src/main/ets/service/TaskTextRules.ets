import { Constants } from '../common/Constants';

/** 自定义任务文本的统一规则，供编辑、导入和本地存储共同使用。 */
export class TaskTextRules {
  static count(text: string): number {
    return Array.from(text).length;
  }

  static limit(text: string): string {
    return Array.from(text).slice(0, Constants.CUSTOM_TASK_MAX_LENGTH).join('');
  }

  static isValid(text: string): boolean {
    const normalized = text.trim();
    const length = TaskTextRules.count(normalized);
    return length > 0 && length <= Constants.CUSTOM_TASK_MAX_LENGTH;
  }

  static ensure(text: string): string {
    const normalized = text.trim();
    if (TaskTextRules.count(normalized) === 0) {
      throw new Error('请输入任务内容');
    }
    if (TaskTextRules.count(normalized) > Constants.CUSTOM_TASK_MAX_LENGTH) {
      throw new Error(`任务内容最多 ${Constants.CUSTOM_TASK_MAX_LENGTH} 个字`);
    }
    return normalized;
  }
}
