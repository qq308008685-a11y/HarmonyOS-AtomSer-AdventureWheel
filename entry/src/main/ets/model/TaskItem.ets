/**
 * 任务数据模型
 * 定义真心话/大冒险任务的核心数据结构
 */

export enum TaskType {
  TRUTH = 'truth',
  DARE = 'dare'
}

export enum RiskLevel {
  LIGHT = 'light',
  MEDIUM = 'medium',
  DEEP = 'deep'
}

export interface TaskItem {
  /** 唯一标识，如 "truth-001" */
  id: string
  /** 任务类型：真心话或大冒险 */
  type: TaskType
  /** 风险等级 */
  level: RiskLevel
  /** 任务完整文本，自定义任务不超过30字 */
  text: string
  /** 标签数组，如 ["搞笑", "模仿", "回忆"] */
  tags: string[]
  /** 是否为玩家自定义任务 */
  isCustom: boolean
}
