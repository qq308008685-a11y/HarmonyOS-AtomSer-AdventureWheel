import { GameConfig, GameMode } from '../model/GameConfig';
import { RiskLevel, TaskItem, TaskType } from '../model/TaskItem';
import { TaskEngine } from '../engine/TaskEngine';
import { WheelCanvas } from '../components/WheelCanvas';
import { Constants } from '../common/Constants';

@Entry
@Component
struct WheelPage {
  @State currentTasks: TaskItem[] = [];
  @State mode: GameMode = GameMode.MIXED;
  @State showResult: boolean = false;
  @State resultTask: TaskItem | null = null;
  @State backdropOpacity: number = 0;
  @State dialogOpacity: number = 0;
  @State sheetOffset: number = 24;
  @State resultCardScale: number = 0.92;
  @State resultBurstOpacity: number = 0;
  @State resultBurstScale: number = 0.55;
  @State turnNumber: number = 1;
  @State completedTaskIds: string[] = [];
  @State resultClosing: boolean = false;
  private config: GameConfig | null = null;
  private engine: TaskEngine = new TaskEngine();
  private resultTimers: number[] = [];

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>;
    if (params && params['config']) {
      this.config = params['config'] as GameConfig;
      this.mode = this.config.mode;
      this.currentTasks = this.config.wheelTasks.length > 0 ?
        this.config.wheelTasks : this.engine.pickForWheel(this.config);
    }
  }

  aboutToDisappear(): void {
    this.clearResultTimers();
    this.resultClosing = false;
    this.showResult = false;
    this.resultTask = null;
  }

  private scheduleResultTimer(callback: () => void, delay: number): void {
    const timer = setTimeout(() => {
      this.resultTimers = this.resultTimers.filter((id: number) => id !== timer);
      callback();
    }, delay);
    this.resultTimers.push(timer);
  }

  private clearResultTimers(): void {
    this.resultTimers.forEach((timer: number) => clearTimeout(timer));
    this.resultTimers = [];
  }

  private onResult(task: TaskItem): void {
    this.clearResultTimers();
    this.resultClosing = false;
    this.resultTask = task;
    this.backdropOpacity = 0;
    this.dialogOpacity = 0;
    this.sheetOffset = 24;
    this.resultCardScale = 0.92;
    this.resultBurstOpacity = 0;
    this.resultBurstScale = 0.55;
    this.showResult = true;
    this.scheduleResultTimer(() => {
      this.backdropOpacity = 1;
      this.resultBurstOpacity = 1;
      this.resultBurstScale = 1;
    }, 30);
    this.scheduleResultTimer(() => {
      this.resultBurstOpacity = 0;
      this.resultBurstScale = 1.55;
    }, 360);
    this.scheduleResultTimer(() => {
      this.dialogOpacity = 1;
      this.sheetOffset = 0;
      this.resultCardScale = 1;
    }, 420);
  }

  private closeResult(continueGame: boolean): void {
    if (this.resultClosing || !this.showResult || this.resultTask === null) {
      return;
    }
    this.resultClosing = true;
    this.clearResultTimers();
    const completedTaskId = continueGame && this.resultTask ? this.resultTask.id : '';
    this.backdropOpacity = 0;
    this.dialogOpacity = 0;
    this.sheetOffset = 18;
    this.resultCardScale = 0.96;
    this.resultBurstOpacity = 0;
    this.scheduleResultTimer(() => {
      this.showResult = false;
      this.resultTask = null;
      this.resultClosing = false;
      if (continueGame) {
        if (completedTaskId.length > 0 && this.completedTaskIds.indexOf(completedTaskId) < 0) {
          this.completedTaskIds = [...this.completedTaskIds, completedTaskId];
        }
        this.turnNumber += 1;
      } else {
        this.getUIContext().getRouter().back();
      }
    }, 280);
  }

  private modeLabel(): string {
    if (this.mode === GameMode.TRUTH_ONLY) {
      return '真心话专场';
    }
    if (this.mode === GameMode.DARE_ONLY) {
      return '大冒险专场';
    }
    return '混合挑战';
  }

  private riskLabel(level: RiskLevel): string {
    if (level === RiskLevel.LIGHT) {
      return '轻松';
    }
    if (level === RiskLevel.MEDIUM) {
      return '适中';
    }
    return '深入';
  }

  private remainingTaskCount(): number {
    return Math.max(0, this.currentTasks.length - this.completedTaskIds.length);
  }

  private isLastRemainingTask(): boolean {
    return this.currentTasks.length > 0 && this.remainingTaskCount() <= 1;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Button('返回')
            .fontSize(13)
            .fontColor(Constants.COLOR_DARK_TEXT)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.getUIContext().getRouter().back())
          Blank()
          Text(this.modeLabel())
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_GOLD)
            .letterSpacing(1)
        }
        .width('100%')
        .padding({ left: 8, right: 18, top: 16 })

        Column() {
          Text(`轮到第 ${this.turnNumber} 位`)
            .fontSize(27)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_WHITE)
          Text(`剩余 ${this.remainingTaskCount()} 个任务`)
            .fontSize(13)
            .fontColor(Constants.COLOR_DARK_SUB)
            .margin({ top: 8 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 24, right: 24, top: 16, bottom: 10 })

        WheelCanvas({
          tasks: this.currentTasks,
          mode: this.mode,
          round: this.turnNumber,
          completedTaskIds: this.completedTaskIds,
          onResult: (task: TaskItem) => this.onResult(task)
        })
          .layoutWeight(1)
          .width('100%')
          .margin({ bottom: 12 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Constants.COLOR_INK)

      if (this.showResult && this.resultTask) {
        Stack({ alignContent: Alignment.Center }) {
          Column() {}
            .width('100%')
            .height('100%')
            .backgroundColor(`rgba(36,17,23,${0.58 * this.backdropOpacity})`)
            .animation({ duration: 180, curve: Curve.EaseOut })

          Stack({ alignContent: Alignment.Center }) {
            Column() {}
              .width(92)
              .height(92)
              .borderRadius(46)
              .border({ width: 3, color: Constants.COLOR_GOLD })
            Text('命中')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_GOLD)
              .letterSpacing(2)
          }
          .width(104)
          .height(104)
          .opacity(this.resultBurstOpacity)
          .scale({ x: this.resultBurstScale, y: this.resultBurstScale })
          .animation({ duration: 360, curve: Curve.EaseOut })

          Column() {
          Row() {
            Text(`第 ${this.turnNumber} 位`)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_TEXT_MUTED)
            Blank()
            Text(this.resultTask.isCustom ? '我添加的任务' : '内置任务')
              .fontSize(11)
              .fontColor(Constants.COLOR_TEXT_MUTED)
          }
          .width('100%')

          Row() {
            Text(this.resultTask.type === TaskType.TRUTH ? '真心话' : '大冒险')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_WHITE)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(Constants.RADIUS_PILL)
              .backgroundColor(this.resultTask.type === TaskType.TRUTH ? Constants.COLOR_TEAL : Constants.COLOR_ORANGE)
            Text(this.riskLabel(this.resultTask.level))
              .fontSize(12)
              .fontColor(Constants.COLOR_TEXT_SUB)
              .margin({ left: 10 })
          }
          .width('100%')
          .margin({ top: 16 })

          Text(this.resultTask.text)
            .fontSize(25)
            .fontWeight(FontWeight.Bold)
            .lineHeight(36)
            .fontColor(Constants.COLOR_INK)
            .width('100%')
            .margin({ top: 18, bottom: 18 })

          Text('不想做可以跳过')
            .fontSize(12)
            .lineHeight(19)
            .fontColor(Constants.COLOR_TEXT_MUTED)
            .width('100%')
            .padding({ top: 14 })
            .border({ width: { top: 1 }, color: Constants.COLOR_LINE })

          Row() {
            Button('结束')
              .layoutWeight(1)
              .height(48)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_TEXT_SUB)
              .backgroundColor(Constants.COLOR_NEUTRAL)
              .borderRadius(Constants.RADIUS_SM)
              .enabled(!this.resultClosing)
              .onClick(() => this.closeResult(false))
            Button(this.isLastRemainingTask() ? '完成本局' : '交给下一位')
              .layoutWeight(1)
              .height(48)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_WHITE)
              .backgroundColor(Constants.COLOR_ORANGE)
              .borderRadius(Constants.RADIUS_SM)
              .margin({ left: 12 })
              .enabled(!this.resultClosing)
              .onClick(() => this.closeResult(!this.isLastRemainingTask()))
          }
          .width('100%')
          .margin({ top: 20 })
          }
          .width('calc(100% - 24vp)')
          .padding({ left: 22, right: 22, top: 20, bottom: 22 })
          .backgroundColor(Constants.COLOR_SURFACE)
          .borderRadius(Constants.RADIUS_LG)
          .shadow({ radius: 30, color: 'rgba(36,17,23,0.32)', offsetX: 0, offsetY: 14 })
          .translate({ y: this.sheetOffset })
          .scale({ x: this.resultCardScale, y: this.resultCardScale })
          .opacity(this.dialogOpacity)
          .animation({ duration: 360, curve: Curve.EaseOut })
        }
        .width('100%')
        .height('100%')
        .padding({ top: 20, bottom: 20 })
      }
    }
    .width('100%')
    .height('100%')
  }
}
