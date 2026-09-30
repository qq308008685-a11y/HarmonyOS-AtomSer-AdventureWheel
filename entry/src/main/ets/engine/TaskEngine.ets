/**
 * 任务抽取引擎
 * 负责：任务筛选、随机抽取、去重、自定义任务拼接、Fisher-Yates 洗牌
 */
import { TaskItem, TaskType, RiskLevel } from '../model/TaskItem';
import { GameConfig, GameMode } from '../model/GameConfig';
import { getAllBuiltInTasks } from '../data/task-source';
import { Constants } from '../common/Constants';

export class TaskEngine {
  /** 内置任务库 */
  private builtInTasks: TaskItem[] = [];

  /** 本局已抽 ID 集合 */
  private usedIds: Set<string> = new Set();

  constructor() {
    this.builtInTasks = getAllBuiltInTasks();
  }

  /**
   * 为一轮转盘抽取任务
   * @param config 游戏配置
   * @returns N 个任务数组
   */
  pickForWheel(config: GameConfig): TaskItem[] {
    // 1. 筛候选池：按模式 + 风险
    let candidatePool = this.filterByModeAndRisk(config.mode, config.riskFilter);

    // 2. 排除已抽 ID
    let available = candidatePool.filter(t => !this.usedIds.has(t.id));

    // 3. 自定义任务数量（不超过50%）
    const maxCustom = Math.floor(config.taskCount * Constants.CUSTOM_TASK_RATIO);
    const compatibleCustom = config.customTasks.filter((task: TaskItem) => {
      if (config.mode === GameMode.TRUTH_ONLY && task.type !== TaskType.TRUTH) {
        return false;
      }
      if (config.mode === GameMode.DARE_ONLY && task.type !== TaskType.DARE) {
        return false;
      }
      const riskOrder: RiskLevel[] = [RiskLevel.LIGHT, RiskLevel.MEDIUM, RiskLevel.DEEP];
      return riskOrder.indexOf(task.level) <= riskOrder.indexOf(config.riskFilter);
    });
    const customTasks = this.shuffle(compatibleCustom).slice(0, maxCustom);

    const neededBuiltIn = config.taskCount - customTasks.length;

    // 4. 若可用不够 → 软重置
    if (available.length < neededBuiltIn) {
      this.usedIds.clear();
      available = candidatePool;
    }

    // 5. Fisher-Yates 洗牌 + 取前 K
    const shuffled = this.shuffle(available).slice(0, neededBuiltIn);

    // 6. 拼接自定义任务 + 再次打乱
    const wheelTasks = this.shuffle([...shuffled, ...customTasks]);

    // 7. 记录已使用（只记录内置任务）
    shuffled.forEach(t => this.usedIds.add(t.id));

    return wheelTasks;
  }

  /**
   * 标记单个任务已使用
   */
  markUsed(task: TaskItem): void {
    if (!task.isCustom) {
      this.usedIds.add(task.id);
    }
  }

  /**
   * 重置本局状态
   */
  reset(): void {
    this.usedIds.clear();
  }

  /**
   * 按模式 + 风险筛选候选池
   */
  private filterByModeAndRisk(mode: GameMode, riskFilter: RiskLevel): TaskItem[] {
    const riskOrder: RiskLevel[] = [RiskLevel.LIGHT, RiskLevel.MEDIUM, RiskLevel.DEEP];
    const maxIndex = riskOrder.indexOf(riskFilter);

    return this.builtInTasks.filter(t => {
      // 模式过滤
      if (mode === GameMode.TRUTH_ONLY && t.type !== TaskType.TRUTH) {
        return false;
      }
      if (mode === GameMode.DARE_ONLY && t.type !== TaskType.DARE) {
        return false;
      }
      // 风险过滤
      const riskIndex = riskOrder.indexOf(t.level);
      return riskIndex <= maxIndex;
    });
  }

  /**
   * Fisher-Yates 洗牌算法
   * 时间复杂度 O(n)，均匀随机
   */
  private shuffle<T>(array: T[]): T[] {
    const result = [...array];
    for (let i = result.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const temp = result[i];
      result[i] = result[j];
      result[j] = temp;
    }
    return result;
  }

  /**
   * 获取候选池大小（调试用）
   */
  getPoolSize(config: GameConfig): PoolSizeInfo {
    const pool = this.filterByModeAndRisk(config.mode, config.riskFilter);
    const available = pool.filter(t => !this.usedIds.has(t.id));
    const result: PoolSizeInfo = { total: pool.length, available: available.length };
    return result;
  }
}

interface PoolSizeInfo {
  total: number;
  available: number;
}
