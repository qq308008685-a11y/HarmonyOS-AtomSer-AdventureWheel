/**
 * 全局常量与商业视觉令牌
 */
export class Constants {
  /** 转盘任务数最小/最大/默认值 */
  static readonly MIN_TASK_COUNT = 2;
  static readonly MAX_TASK_COUNT = 20;
  static readonly DEFAULT_TASK_COUNT = 6;

  /** 自定义任务占比上限 (50%) */
  static readonly CUSTOM_TASK_RATIO = 0.5;

  /** 自定义任务最大字数 */
  static readonly CUSTOM_TASK_MAX_LENGTH = 30;

  /** 转盘动画时长范围 (ms) */
  static readonly SPIN_MIN_DURATION = 2700;
  static readonly SPIN_MAX_DURATION = 3200;
  static readonly RESULT_REVEAL_DELAY = 520;

  /** 转盘最小旋转圈数 */
  static readonly SPIN_MIN_ROTATIONS = 4;
  static readonly SPIN_MAX_ROTATIONS = 6;

  /** 偏好存储 key */
  static readonly PREF_LAST_MODE = 'last_mode';
  static readonly PREF_LAST_COUNT = 'last_count';
  static readonly PREF_RISK_LEVEL = 'risk_level';
  static readonly PREF_SOUND_ENABLED = 'sound_enabled';
  static readonly PREF_DISCLAIMER_ACCEPTED = 'disclaimer_accepted';

  // ===== 商业视觉系统 =====
  // 樱桃可乐：午夜樱桃黑 / 香草奶油 / 蔓越莓红 / 冰川蓝 / 黄油黄
  static readonly COLOR_INK = '#241117';
  static readonly COLOR_PAPER = '#FFF3DE';
  static readonly COLOR_SURFACE = '#FFF9ED';
  static readonly COLOR_LINE = '#E1D2BC';
  static readonly COLOR_GLACIER = '#7FB4BF';
  static readonly COLOR_TEAL = '#3F7681';
  static readonly COLOR_TEAL_DARK = '#2E5D67';
  static readonly COLOR_ORANGE = '#B8324B';
  static readonly COLOR_GOLD = '#F0C95A';
  static readonly COLOR_TEXT_SUB = '#6B545A';
  static readonly COLOR_TEXT_MUTED = '#9B8487';
  static readonly COLOR_SUCCESS = '#4F7C6E';
  static readonly COLOR_DANGER = '#9E293F';
  static readonly COLOR_WHITE = '#FFF9EF';
  static readonly COLOR_NEUTRAL = '#F0E4D1';
  static readonly COLOR_INPUT = '#F6E8D2';
  static readonly COLOR_TRUTH_LIGHT = '#DCECEF';
  static readonly COLOR_DARE_LIGHT = '#F5DCE1';
  static readonly COLOR_DARK_TEXT = '#F7E9D7';
  static readonly COLOR_DARK_MUTED = '#D9BCC3';
  static readonly COLOR_DARK_SUB = '#BFA9AD';
  static readonly COLOR_COMPLETED_SECTOR = '#625158';
  static readonly COLOR_COMPLETED_BORDER = '#8B757C';
  static readonly COLOR_COMPLETED_TEXT = '#DDCDD0';

  static readonly RADIUS_LG = 22;
  static readonly RADIUS_MD = 16;
  static readonly RADIUS_SM = 10;
  static readonly RADIUS_PILL = 999;

  static readonly SHADOW_RADIUS = 24;
  static readonly SHADOW_COLOR = 'rgba(36,17,23,0.14)';
  static readonly SHADOW_OFFSET_Y = 10;
  static readonly SHADOW_SM_RADIUS = 10;
  static readonly SHADOW_SM_COLOR = 'rgba(36,17,23,0.12)';
  static readonly SHADOW_SM_OFFSET_Y = 4;
  static readonly SHADOW_PRESS_RADIUS = 3;
  static readonly SHADOW_PRESS_COLOR = 'rgba(36,17,23,0.18)';
  static readonly SHADOW_PRESS_OFFSET_Y = 2;

  /** 旧组件兼容别名；均映射到新视觉令牌。 */
  static readonly CLAY_BG = Constants.COLOR_PAPER;
  static readonly CLAY_SURFACE = Constants.COLOR_SURFACE;
  static readonly CLAY_CARD = Constants.COLOR_SURFACE;
  static readonly CLAY_CARD_BORDER = Constants.COLOR_LINE;
  static readonly CLAY_TEXT = Constants.COLOR_INK;
  static readonly CLAY_TEXT_SUB = Constants.COLOR_TEXT_SUB;
  static readonly CLAY_TEXT_MUTED = Constants.COLOR_TEXT_MUTED;
  static readonly CLAY_TRUTH = Constants.COLOR_TEAL;
  static readonly CLAY_TRUTH_LIGHT = Constants.COLOR_TRUTH_LIGHT;
  static readonly CLAY_DARE = Constants.COLOR_ORANGE;
  static readonly CLAY_DARE_LIGHT = Constants.COLOR_DARE_LIGHT;
  static readonly CLAY_ACCENT = Constants.COLOR_GOLD;
  static readonly CLAY_SUCCESS = Constants.COLOR_SUCCESS;
  static readonly CLAY_DANGER = Constants.COLOR_DANGER;
  static readonly CLAY_RADIUS_LG = Constants.RADIUS_LG;
  static readonly CLAY_RADIUS_MD = Constants.RADIUS_MD;
  static readonly CLAY_RADIUS_SM = Constants.RADIUS_SM;
  static readonly CLAY_PILL = Constants.RADIUS_PILL;
  static readonly CLAY_SHADOW_RADIUS = Constants.SHADOW_RADIUS;
  static readonly CLAY_SHADOW_COLOR = Constants.SHADOW_COLOR;
  static readonly CLAY_SHADOW_OFFSET_Y = Constants.SHADOW_OFFSET_Y;
  static readonly CLAY_SHADOW_SM_RADIUS = Constants.SHADOW_SM_RADIUS;
  static readonly CLAY_SHADOW_SM_COLOR = Constants.SHADOW_SM_COLOR;
  static readonly CLAY_SHADOW_SM_OFFSET_Y = Constants.SHADOW_SM_OFFSET_Y;
  static readonly CLAY_SHADOW_PRESS_RADIUS = Constants.SHADOW_PRESS_RADIUS;
  static readonly CLAY_SHADOW_PRESS_COLOR = Constants.SHADOW_PRESS_COLOR;
  static readonly CLAY_SHADOW_PRESS_OFFSET_Y = Constants.SHADOW_PRESS_OFFSET_Y;

  /** 间距节奏 */
  static readonly CLAY_SPACE_XS = 8;
  static readonly CLAY_SPACE_SM = 12;
  static readonly CLAY_SPACE_MD = 20;
  static readonly CLAY_SPACE_LG = 32;

  /** 动画时长 */
  static readonly CLAY_ANIM_FAST = 150;
  static readonly CLAY_ANIM_NORMAL = 250;
  static readonly CLAY_ANIM_SLOW = 400;

  /** 转盘 Canvas 相关 */
  static readonly WHEEL_STROKE_WIDTH = 2;
  static readonly WHEEL_LABEL_FONT_SIZE = 14;
  static readonly POINTER_SIZE = 22;
}
