import { RiskLevel, TaskItem, TaskType } from './TaskItem';

export interface LocalTaskRecord {
  id: string
  type: TaskType
  level: RiskLevel
  text: string
  enabled: boolean
  createdAt: number
  updatedAt: number
}

export interface TaskTransferPackage {
  format: string
  version: number
  tasks: TransferTaskRecord[]
}

export interface TransferTaskRecord {
  type: TaskType
  level: RiskLevel
  text: string
  enabled: boolean
}

export interface ImportPreview {
  validTasks: LocalTaskRecord[]
  validCount: number
  duplicateCount: number
  invalidCount: number
}

export class LocalTaskMapper {
  static toTaskItem(record: LocalTaskRecord): TaskItem {
    return {
      id: record.id,
      type: record.type,
      level: record.level,
      text: record.text,
      tags: ['自定义'],
      isCustom: true
    };
  }
}
