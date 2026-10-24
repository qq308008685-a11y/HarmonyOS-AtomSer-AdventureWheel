import preferences from '@ohos.data.preferences';
import { LocalTaskRecord } from '../model/LocalTaskRecord';
import { RiskLevel, TaskType } from '../model/TaskItem';
import { TaskTextRules } from '../service/TaskTextRules';

const STORE_NAME = 'adventure_wheel_local_tasks';
const TASKS_KEY = 'custom_tasks_v1';

export class LocalTaskStore {
  private static store: preferences.Preferences | null = null;
  private static operationQueue: Promise<void> = Promise.resolve();
  private static restoreRaw: string | null = null;

  static async init(context: Context): Promise<void> {
    return LocalTaskStore.enqueue(async (): Promise<void> => {
      if (LocalTaskStore.store !== null) {
        return;
      }
      try {
        LocalTaskStore.store = await preferences.getPreferences(context, STORE_NAME);
      } catch (error) {
        console.error('LocalTaskStore: 初始化失败');
        throw new Error('本地任务存储初始化失败');
      }
    });
  }

  static async list(): Promise<LocalTaskRecord[]> {
    return LocalTaskStore.enqueue((): Promise<LocalTaskRecord[]> => LocalTaskStore.read());
  }

  private static async read(): Promise<LocalTaskRecord[]> {
    try {
      const store = LocalTaskStore.requireStore();
      await LocalTaskStore.restoreIfNeeded(store);
      const raw = await store.get(TASKS_KEY, '[]') as string;
      const tasks = JSON.parse(raw) as LocalTaskRecord[];
      if (!Array.isArray(tasks)) {
        throw new Error('本地任务格式不正确');
      }
      return tasks;
    } catch (error) {
      console.error('LocalTaskStore: 读取失败');
      throw new Error('本地任务读取失败，请重试');
    }
  }

  static async add(type: TaskType, level: RiskLevel, text: string, enabled: boolean = true): Promise<LocalTaskRecord> {
    return LocalTaskStore.enqueue(async (): Promise<LocalTaskRecord> => {
      const normalizedText = TaskTextRules.ensure(text);
      const tasks = await LocalTaskStore.read();
      LocalTaskStore.ensureUnique(tasks, type, normalizedText);
      const now = Date.now();
      const record: LocalTaskRecord = {
        id: `local-${now}-${Math.floor(Math.random() * 100000)}`,
        type: type,
        level: level,
        text: normalizedText,
        enabled: enabled,
        createdAt: now,
        updatedAt: now
      };
      tasks.unshift(record);
      await LocalTaskStore.save(tasks);
      return record;
    });
  }

  static async hasDuplicate(type: TaskType, text: string, excludeId: string = ''): Promise<boolean> {
    const tasks = await LocalTaskStore.list();
    const normalized = LocalTaskStore.normalize(text);
    return tasks.some((item: LocalTaskRecord) => item.id !== excludeId && item.type === type &&
      LocalTaskStore.normalize(item.text) === normalized);
  }

  static async update(record: LocalTaskRecord): Promise<void> {
    return LocalTaskStore.enqueue(async (): Promise<void> => {
      const tasks = await LocalTaskStore.read();
      if (!tasks.some((item: LocalTaskRecord) => item.id === record.id)) {
        throw new Error('这条任务已不存在，请关闭编辑后重新读取');
      }
      const normalizedText = TaskTextRules.ensure(record.text);
      LocalTaskStore.ensureUnique(tasks, record.type, normalizedText, record.id);
      const next = tasks.map((item: LocalTaskRecord): LocalTaskRecord => {
        if (item.id !== record.id) {
          return item;
        }
        return {
          id: item.id,
          type: record.type,
          level: record.level,
          text: normalizedText,
          enabled: record.enabled,
          createdAt: item.createdAt,
          updatedAt: Date.now()
        };
      });
      await LocalTaskStore.save(next);
    });
  }

  static async setEnabled(id: string, enabled: boolean): Promise<void> {
    return LocalTaskStore.enqueue(async (): Promise<void> => {
      const tasks = await LocalTaskStore.read();
      if (!tasks.some((item: LocalTaskRecord) => item.id === id)) {
        throw new Error('这条任务已不存在，请重新读取');
      }
      const next = tasks.map((item: LocalTaskRecord): LocalTaskRecord => {
        if (item.id !== id) {
          return item;
        }
        return {
          id: item.id,
          type: item.type,
          level: item.level,
          text: item.text,
          enabled: enabled,
          createdAt: item.createdAt,
          updatedAt: Date.now()
        };
      });
      await LocalTaskStore.save(next);
    });
  }

  static async remove(id: string): Promise<void> {
    return LocalTaskStore.enqueue(async (): Promise<void> => {
      const tasks = await LocalTaskStore.read();
      await LocalTaskStore.save(tasks.filter((item: LocalTaskRecord) => item.id !== id));
    });
  }

  static async mergeImported(imported: LocalTaskRecord[]): Promise<number> {
    return LocalTaskStore.enqueue(async (): Promise<number> => {
      const tasks = await LocalTaskStore.read();
      let added = 0;
      imported.forEach((candidate: LocalTaskRecord) => {
        const normalized = LocalTaskStore.normalize(candidate.text);
        const duplicated = tasks.some((item: LocalTaskRecord) =>
          item.type === candidate.type && LocalTaskStore.normalize(item.text) === normalized);
        if (!duplicated) {
          tasks.unshift(candidate);
          added++;
        }
      });
      await LocalTaskStore.save(tasks);
      return added;
    });
  }

  private static async save(tasks: LocalTaskRecord[]): Promise<void> {
    const store = LocalTaskStore.requireStore();
    const previousRaw = await store.get(TASKS_KEY, '[]') as string;
    try {
      await store.put(TASKS_KEY, JSON.stringify(tasks));
      await store.flush();
    } catch (error) {
      console.error('LocalTaskStore: 写入失败');
      // put 可能已更新 Preferences 缓存；恢复原值后才允许下一次读改写。
      LocalTaskStore.restoreRaw = previousRaw;
      try {
        await LocalTaskStore.restoreIfNeeded(store);
      } catch (restoreError) {
        console.error('LocalTaskStore: 原值待恢复，下次读取时重试');
      }
      throw new Error('本地任务写入失败，请重试');
    }
  }

  private static async restoreIfNeeded(store: preferences.Preferences): Promise<void> {
    const raw = LocalTaskStore.restoreRaw;
    if (raw !== null) {
      await store.put(TASKS_KEY, raw);
      await store.flush();
      LocalTaskStore.restoreRaw = null;
    }
  }

  private static requireStore(): preferences.Preferences {
    const store = LocalTaskStore.store;
    if (store === null) {
      throw new Error('本地任务存储尚未初始化');
    }
    return store;
  }

  private static enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const result = LocalTaskStore.operationQueue.then(operation);
    // 队尾只负责继续调度；原始 result 的拒绝仍交给调用者处理。
    LocalTaskStore.operationQueue = result.then((): void => {}, (): void => {});
    return result;
  }

  private static ensureUnique(tasks: LocalTaskRecord[], type: TaskType, text: string, excludeId: string = ''): void {
    const normalized = LocalTaskStore.normalize(text);
    if (tasks.some((item: LocalTaskRecord) => item.id !== excludeId && item.type === type &&
      LocalTaskStore.normalize(item.text) === normalized)) {
      throw new Error('同类型中已经有相同任务');
    }
  }

  private static normalize(text: string): string {
    return text.trim().toLowerCase().replace(/\s+/g, '');
  }
}
