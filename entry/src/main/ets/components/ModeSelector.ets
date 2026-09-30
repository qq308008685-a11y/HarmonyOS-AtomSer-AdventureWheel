/**
 * 游戏模式选择器
 * 三选一：真心话 / 大冒险 / 混合
 * 编辑式分段选择器：信息简洁，状态清晰。
 */
import { GameMode } from '../model/GameConfig';
import { Constants } from '../common/Constants';

interface ModeItem {
  mode: GameMode;
  label: string;
  desc: string;
}

@Component
export struct ModeSelector {
  @Prop selectedMode: GameMode = GameMode.MIXED;
  onChange?: (mode: GameMode) => void;
  @State pressedMode: GameMode = GameMode.MIXED;
  @State isPressed: boolean = false;

  private modes: ModeItem[] = [
    { mode: GameMode.TRUTH_ONLY, label: '真心话', desc: '坦诚回答' },
    { mode: GameMode.DARE_ONLY, label: '大冒险', desc: '行动挑战' },
    { mode: GameMode.MIXED, label: '混合局', desc: '随机组合' }
  ];

  private modeColor(mode: GameMode): string {
    if (mode === GameMode.TRUTH_ONLY) {
      return Constants.COLOR_TEAL;
    }
    if (mode === GameMode.DARE_ONLY) {
      return Constants.COLOR_ORANGE;
    }
    return Constants.COLOR_INK;
  }

  build() {
    Row() {
      ForEach(this.modes, (item: ModeItem) => {
        Column() {
          Text(item.label)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.selectedMode === item.mode ? Constants.COLOR_WHITE : Constants.COLOR_INK)
          Text(item.desc)
            .fontSize(11)
            .fontColor(this.selectedMode === item.mode ? Constants.COLOR_WHITE : Constants.COLOR_TEXT_MUTED)
            .margin({ top: 4 })
        }
        .width('32%')
        .padding({ top: 14, bottom: 14 })
        .borderRadius(Constants.RADIUS_SM)
        .backgroundColor(this.selectedMode === item.mode ? this.modeColor(item.mode) : Constants.COLOR_SURFACE)
        .border({
          width: 1,
          color: this.selectedMode === item.mode ? this.modeColor(item.mode) : Constants.COLOR_LINE
        })
        .shadow(this.selectedMode === item.mode ? {
          radius: 8,
          color: Constants.SHADOW_SM_COLOR,
          offsetX: 0,
          offsetY: Constants.CLAY_SHADOW_SM_OFFSET_Y
        } : { radius: 0, color: 'transparent', offsetX: 0, offsetY: 0 })
        .scale(this.isPressed && this.pressedMode === item.mode ? { x: 0.96, y: 0.96 } : { x: 1, y: 1 })
        .onClick(() => {
          if (this.onChange) {
            this.onChange(item.mode);
          }
        })
        .onTouch((event: TouchEvent) => {
          this.pressedMode = item.mode;
          this.isPressed = event.type === TouchType.Down;
        })
        .animation({ duration: Constants.CLAY_ANIM_FAST, curve: Curve.EaseOut })
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
  }
}
