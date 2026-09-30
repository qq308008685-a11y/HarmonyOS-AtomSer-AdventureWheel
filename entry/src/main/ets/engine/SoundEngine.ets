/**
 * 音效引擎
 * 管理转盘旋转的碰撞音效和停止音效
 */
export class SoundEngine {
  private static muted: boolean = false;
  private static initialized: boolean = false;

  /**
   * 初始化音效
   */
  static async init(_context: Context): Promise<void> {
    if (SoundEngine.initialized) {
      return;
    }
    SoundEngine.initialized = true;
  }

  /**
   * 播放碰撞音效
   */
  static playTick(): void {
    if (SoundEngine.muted) {
      return;
    }
  }

  /**
   * 播放停止音效
   */
  static playStop(): void {
    if (SoundEngine.muted) {
      return;
    }
  }

  /**
   * 切换静音
   */
  static setMuted(muted: boolean): void {
    SoundEngine.muted = muted;
  }

  /**
   * 是否静音
   */
  static get isMuted(): boolean {
    return SoundEngine.muted;
  }
}