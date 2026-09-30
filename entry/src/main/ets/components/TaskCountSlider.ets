/**
 * 任务数量滑块控件
 * 范围 2~20，默认 6
 * 紧凑的任务数量控制卡片
 */
import { Constants } from '../common/Constants';

@Component
export struct TaskCountSlider {
  @Prop count: number = Constants.DEFAULT_TASK_COUNT;
  onChange?: (count: number) => void;

  build() {
    Column() {
      Row() {
        Text('转盘任务数')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_INK)
        Blank()
        Text(`${this.count} 个`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_ORANGE)
      }
      .width('100%')
      .margin({ bottom: 14 })

      Slider({
        value: this.count,
        min: Constants.MIN_TASK_COUNT,
        max: Constants.MAX_TASK_COUNT,
        step: 1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .blockColor(Constants.COLOR_ORANGE)
        .trackColor(Constants.COLOR_NEUTRAL)
        .selectedColor(Constants.COLOR_ORANGE)
        .onChange((value: number) => {
          if (this.onChange) {
            this.onChange(value);
          }
        })

      Row() {
        Text(`${Constants.MIN_TASK_COUNT}`)
          .fontSize(12)
          .fontColor(Constants.COLOR_TEXT_MUTED)
        Blank()
        Text(`${Constants.MAX_TASK_COUNT}`)
          .fontSize(12)
          .fontColor(Constants.COLOR_TEXT_MUTED)
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding(20)
    .borderRadius(Constants.RADIUS_MD)
    .backgroundColor(Constants.COLOR_SURFACE)
    .border({ width: 1, color: Constants.COLOR_LINE })
    .shadow({
      radius: 8,
      color: 'rgba(36,17,23,0.08)',
      offsetX: 0,
      offsetY: Constants.CLAY_SHADOW_SM_OFFSET_Y
    })
  }
}
