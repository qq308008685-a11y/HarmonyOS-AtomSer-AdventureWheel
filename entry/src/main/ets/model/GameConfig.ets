/**
 * 游戏配置数据模型
 * 携带从设置页到转盘页的完整游戏参数
 */
import { RiskLevel, TaskItem } from './TaskItem';

export enum GameMode {
  TRUTH_ONLY = 'truth_only',
  DARE_ONLY = 'dare_only',
  MIXED = 'mixed'
}

export interface GameConfig {
  /** 游戏模式 */
  mode: GameMode
  /** 转盘上的任务数量 (2~20) */
  taskCount: number
  /** 风险过滤上限，默认 MEDIUM（深度任务不参与） */
  riskFilter: RiskLevel
  /** 已启用且参与本局抽取的本地自定义任务 */
  customTasks: TaskItem[]
  /** 用户在开局前已经确认的本局转盘任务 */
  wheelTasks: TaskItem[]
}
