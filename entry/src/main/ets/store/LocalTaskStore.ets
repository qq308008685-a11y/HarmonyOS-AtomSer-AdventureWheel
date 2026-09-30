import preferences from '@ohos.data.preferences';
import { LocalTaskRecord } from '../model/LocalTaskRecord';
import { RiskLevel, TaskType } from '../model/TaskItem';
import { TaskTextRules } from '../service/TaskTextRules';

const STORE_NAME = 'adventure_wheel_local_tasks';
const TASKS_KEY = 'custom_tasks_v1';

export class LocalTaskStore {
  private static store: preferences.Preferences | null = null;

  static async init(context: Context): Promise<void> {
    if (LocalTaskStore.store !== null) {
      return;
    }
    try {
      LocalTaskStore.store = await preferences.getPreferences(context, STORE_NAME);
    } catch (error) {
      console.error('LocalTaskStore: 初始化失败');
      throw new Error('本地任务存储初始化失败');
    }
  }

  static async list(): Promise<LocalTaskRecord[]> {
    try {
      const raw = await LocalTaskStore.store?.get(TASKS_KEY, '[]') as string;
      if (!raw) {
        return [];
      }
      return JSON.parse(raw) as LocalTaskRecord[];
    } catch (error) {
      console.error(`LocalTaskStore: 无法读取本地任务 ${JSON.stringify(error)}`);
      return [];
    }
  }

  static async add(type: TaskType, level: RiskLevel, text: string, enabled: boolean = true): Promise<LocalTaskRecord> {
    const now = Date.now();
    const normalizedText = TaskTextRules.ensure(text);
    const record: LocalTaskRecord = {
      id: `local-${now}-${Math.floor(Math.random() * 100000)}`,
      type: type,
      level: level,
      text: normalizedText,
      enabled: enabled,
      createdAt: now,
      updatedAt: now
    };
    const tasks = await LocalTaskStore.list();
    tasks.unshift(record);
    await LocalTaskStore.save(tasks);
    return record;
  }

  static async hasDuplicate(type: TaskType, text: string, excludeId: string = ''): Promise<boolean> {
    const tasks = await LocalTaskStore.list();
    const normalized = LocalTaskStore.normalize(text);
    return tasks.some((item: LocalTaskRecord) => item.id !== excludeId && item.type === type &&
      LocalTaskStore.normalize(item.text) === normalized);
  }

  static async update(record: LocalTaskRecord): Promise<void> {
    const tasks = await LocalTaskStore.list();
    const normalizedText = TaskTextRules.ensure(record.text);
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
  }

  static async setEnabled(id: string, enabled: boolean): Promise<void> {
    const tasks = await LocalTaskStore.list();
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
  }

  static async remove(id: string): Promise<void> {
    const tasks = await LocalTaskStore.list();
    await LocalTaskStore.save(tasks.filter((item: LocalTaskRecord) => item.id !== id));
  }

  static async mergeImported(imported: LocalTaskRecord[]): Promise<number> {
    const tasks = await LocalTaskStore.list();
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
  }

  private static async save(tasks: LocalTaskRecord[]): Promise<void> {
    try {
      await LocalTaskStore.store?.put(TASKS_KEY, JSON.stringify(tasks));
      await LocalTaskStore.store?.flush();
    } catch (error) {
      console.error('LocalTaskStore: 写入失败');
      throw new Error('本地任务写入失败');
    }
  }

  private static normalize(text: string): string {
    return text.trim().toLowerCase().replace(/\s+/g, '');
  }
}
