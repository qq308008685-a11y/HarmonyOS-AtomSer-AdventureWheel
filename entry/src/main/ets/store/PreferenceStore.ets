import preferences from '@ohos.data.preferences';
import { Constants } from '../common/Constants';
import { GameMode } from '../model/GameConfig';
import { RiskLevel } from '../model/TaskItem';

export class PreferenceStore {
  private static store: preferences.Preferences | null = null;

  static async init(context: Context): Promise<void> {
    if (PreferenceStore.store !== null) {
      return;
    }
    try {
      PreferenceStore.store = await preferences.getPreferences(context, 'adventure_wheel_prefs');
    } catch (error) {
      console.error('PreferenceStore: 初始化失败');
      throw new Error('偏好存储初始化失败');
    }
  }

  static async setLastMode(mode: GameMode): Promise<void> {
    await PreferenceStore.put(Constants.PREF_LAST_MODE, mode);
  }

  static async getLastMode(): Promise<GameMode> {
    try {
      const value = await PreferenceStore.store?.get(Constants.PREF_LAST_MODE, GameMode.MIXED) as string;
      return value as GameMode;
    } catch (error) {
      console.error('PreferenceStore: 读取游戏模式失败');
      return GameMode.MIXED;
    }
  }

  static async setLastCount(count: number): Promise<void> {
    await PreferenceStore.put(Constants.PREF_LAST_COUNT, count);
  }

  static async getLastCount(): Promise<number> {
    try {
      return await PreferenceStore.store?.get(Constants.PREF_LAST_COUNT, Constants.DEFAULT_TASK_COUNT) as number;
    } catch (error) {
      console.error('PreferenceStore: 读取任务数量失败');
      return Constants.DEFAULT_TASK_COUNT;
    }
  }

  static async setRiskLevel(level: RiskLevel): Promise<void> {
    await PreferenceStore.put(Constants.PREF_RISK_LEVEL, level);
  }

  static async getRiskLevel(): Promise<RiskLevel> {
    try {
      const value = await PreferenceStore.store?.get(Constants.PREF_RISK_LEVEL, RiskLevel.MEDIUM) as string;
      return value as RiskLevel;
    } catch (error) {
      console.error('PreferenceStore: 读取任务尺度失败');
      return RiskLevel.MEDIUM;
    }
  }

  static async setSoundEnabled(enabled: boolean): Promise<void> {
    await PreferenceStore.put(Constants.PREF_SOUND_ENABLED, enabled);
  }

  static async getSoundEnabled(): Promise<boolean> {
    try {
      return await PreferenceStore.store?.get(Constants.PREF_SOUND_ENABLED, true) as boolean;
    } catch (error) {
      console.error('PreferenceStore: 读取音效设置失败');
      return true;
    }
  }

  static async setDisclaimerAccepted(accepted: boolean): Promise<void> {
    await PreferenceStore.put(Constants.PREF_DISCLAIMER_ACCEPTED, accepted);
  }

  static async isDisclaimerAccepted(): Promise<boolean> {
    try {
      return await PreferenceStore.store?.get(Constants.PREF_DISCLAIMER_ACCEPTED, false) as boolean;
    } catch (error) {
      console.error('PreferenceStore: 读取安全提示状态失败');
      return false;
    }
  }

  private static async put(key: string, value: preferences.ValueType): Promise<void> {
    try {
      await PreferenceStore.store?.put(key, value);
      await PreferenceStore.store?.flush();
    } catch (error) {
      console.error('PreferenceStore: 写入失败');
      throw new Error('偏好设置写入失败');
    }
  }
}
