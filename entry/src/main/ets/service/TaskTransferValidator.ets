import { ImportPreview, LocalTaskRecord, TaskTransferPackage, TransferTaskRecord } from '../model/LocalTaskRecord';
import { RiskLevel, TaskType } from '../model/TaskItem';
import { TaskTextRules } from './TaskTextRules';

export class TaskTransferValidator {
  static readonly FORMAT = 'adventure-wheel-tasks';
  static readonly VERSION = 1;
  static readonly MAX_TASKS = 1000;

  static parse(content: string, existing: LocalTaskRecord[]): ImportPreview {
    const data = JSON.parse(content) as TaskTransferPackage;
    if (!data || data.format !== TaskTransferValidator.FORMAT || data.version !== TaskTransferValidator.VERSION ||
      !Array.isArray(data.tasks)) {
      throw new Error('文件格式或版本不受支持');
    }
    if (data.tasks.length > TaskTransferValidator.MAX_TASKS) {
      throw new Error(`单次最多导入 ${TaskTransferValidator.MAX_TASKS} 条任务`);
    }

    const validTasks: LocalTaskRecord[] = [];
    let duplicateCount = 0;
    let invalidCount = 0;
    const knownKeys: string[] = existing.map((item: LocalTaskRecord) =>
      TaskTransferValidator.keyOf(item.type, item.text));

    data.tasks.forEach((item: TransferTaskRecord, index: number) => {
      if (!TaskTransferValidator.isValid(item)) {
        invalidCount++;
        return;
      }
      const key = TaskTransferValidator.keyOf(item.type, item.text);
      if (knownKeys.includes(key)) {
        duplicateCount++;
        return;
      }
      const now = Date.now();
      validTasks.push({
        id: `local-import-${now}-${index}-${Math.floor(Math.random() * 100000)}`,
        type: item.type,
        level: item.level,
        text: item.text.trim(),
        enabled: item.enabled,
        createdAt: now,
        updatedAt: now
      });
      knownKeys.push(key);
    });

    return {
      validTasks: validTasks,
      validCount: validTasks.length,
      duplicateCount: duplicateCount,
      invalidCount: invalidCount
    };
  }

  private static isValid(item: TransferTaskRecord): boolean {
    if (!item || typeof item.text !== 'string' || !TaskTextRules.isValid(item.text)) {
      return false;
    }
    if (item.type !== TaskType.TRUTH && item.type !== TaskType.DARE) {
      return false;
    }
    if (item.level !== RiskLevel.LIGHT && item.level !== RiskLevel.MEDIUM && item.level !== RiskLevel.DEEP) {
      return false;
    }
    return typeof item.enabled === 'boolean';
  }

  private static keyOf(type: TaskType, text: string): string {
    return `${type}:${text.trim().toLowerCase().replace(/\s+/g, '')}`;
  }
}
