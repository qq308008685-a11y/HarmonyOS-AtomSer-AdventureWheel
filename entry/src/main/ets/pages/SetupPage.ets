import { GameConfig, GameMode } from '../model/GameConfig';
import { RiskLevel, TaskItem, TaskType } from '../model/TaskItem';
import { LocalTaskMapper, LocalTaskRecord } from '../model/LocalTaskRecord';
import { Constants } from '../common/Constants';
import { ModeSelector } from '../components/ModeSelector';
import { TaskCountSlider } from '../components/TaskCountSlider';
import { PreferenceStore } from '../store/PreferenceStore';
import { LocalTaskStore } from '../store/LocalTaskStore';
import { TaskEngine } from '../engine/TaskEngine';
import { getAllBuiltInTasks } from '../data/task-source';

@Entry
@Component
struct SetupPage {
  @State mode: GameMode = GameMode.MIXED;
  @State taskCount: number = Constants.DEFAULT_TASK_COUNT;
  @State riskLevel: RiskLevel = RiskLevel.MEDIUM;
  @State customTaskCount: number = 0;
  @State enabledTaskCount: number = 0;
  @State isPressed: boolean = false;
  @State previewVisible: boolean = false;
  @State previewTasks: TaskItem[] = [];
  @State setupStatusText: string = '';
  private pendingConfig: GameConfig | null = null;
  private engine: TaskEngine = new TaskEngine();
  private builtInTaskCount: number = getAllBuiltInTasks().length;

  aboutToAppear(): void {
    this.loadLocalState();
  }

  private async loadLocalState(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        throw new Error('无法获取页面上下文');
      }
      await PreferenceStore.init(context);
      await LocalTaskStore.init(context);
      this.mode = await PreferenceStore.getLastMode();
      this.taskCount = await PreferenceStore.getLastCount();
      this.riskLevel = await PreferenceStore.getRiskLevel();
      const records = await LocalTaskStore.list();
      this.customTaskCount = records.length;
      this.enabledTaskCount = records.filter((item: LocalTaskRecord) => item.enabled).length;
    } catch (error) {
      console.error(`SetupPage: 加载本地状态失败 ${JSON.stringify(error)}`);
    }
  }

  private async generateTaskPreview(): Promise<void> {
    try {
      const records = await LocalTaskStore.list();
      const customTasks: TaskItem[] = records
        .filter((item: LocalTaskRecord) => item.enabled)
        .map((item: LocalTaskRecord): TaskItem => LocalTaskMapper.toTaskItem(item));
      const config: GameConfig = {
        mode: this.mode,
        taskCount: this.taskCount,
        riskFilter: this.riskLevel,
        customTasks: customTasks,
        wheelTasks: []
      };
      const wheelTasks = this.engine.pickForWheel(config);
      config.wheelTasks = wheelTasks;
      await PreferenceStore.setLastMode(this.mode);
      await PreferenceStore.setLastCount(this.taskCount);
      await PreferenceStore.setRiskLevel(this.riskLevel);
      this.previewTasks = wheelTasks;
      this.pendingConfig = config;
      this.setupStatusText = '';
      this.previewVisible = true;
    } catch (error) {
      this.setupStatusText = '暂时无法生成任务，请稍后重试';
      console.error(`SetupPage: 无法生成任务 ${JSON.stringify(error)}`);
    }
  }

  private async confirmStartGame(): Promise<void> {
    if (!this.pendingConfig || this.previewTasks.length === 0) {
      this.setupStatusText = '请先生成本局任务';
      this.previewVisible = false;
      return;
    }
    try {
      this.pendingConfig.wheelTasks = this.previewTasks;
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/WheelPage',
        params: { config: this.pendingConfig }
      });
      this.previewVisible = false;
    } catch (error) {
      this.setupStatusText = '暂时无法进入转盘，请重试';
      console.error(`SetupPage: 无法开始游戏 ${JSON.stringify(error)}`);
    }
  }

  private openTaskLibrary(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/TaskLibraryPage' }).catch((error: Error) => {
      console.error(`SetupPage: 无法打开任务库 ${JSON.stringify(error)}`);
    });
  }

  private modeSummary(): string {
    if (this.mode === GameMode.TRUTH_ONLY) {
      return '真心话专场';
    }
    if (this.mode === GameMode.DARE_ONLY) {
      return '大冒险专场';
    }
    return '真心话与大冒险混合';
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

  private typeLabel(type: TaskType): string {
    return type === TaskType.TRUTH ? '真心话' : '大冒险';
  }

  @Builder
  private riskButton(level: RiskLevel) {
    Button(this.riskLabel(level))
      .layoutWeight(1)
      .height(40)
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.riskLevel === level ? Constants.COLOR_WHITE : Constants.COLOR_TEXT_SUB)
      .backgroundColor(this.riskLevel === level ? Constants.COLOR_INK : Constants.COLOR_NEUTRAL)
      .borderRadius(Constants.RADIUS_SM)
      .margin({ right: level === RiskLevel.DEEP ? 0 : 8 })
      .onClick(() => this.riskLevel = level)
  }

  @Builder
  private previewTaskRow(task: TaskItem, index: number) {
    Row() {
      Text(`${index + 1}`)
        .width(30)
        .height(30)
        .textAlign(TextAlign.Center)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_WHITE)
        .backgroundColor(Constants.COLOR_INK)
        .borderRadius(Constants.RADIUS_PILL)

      Column() {
        Row() {
          Text(this.typeLabel(task.type))
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(task.type === TaskType.TRUTH ? Constants.COLOR_TEAL : Constants.COLOR_ORANGE)
          Text(`${this.riskLabel(task.level)}${task.isCustom ? ' · 我添加的' : ''}`)
            .fontSize(11)
            .fontColor(Constants.COLOR_TEXT_MUTED)
            .margin({ left: 9 })
        }
        .width('100%')

        Text(task.text)
          .width('100%')
          .fontSize(15)
          .lineHeight(22)
          .fontColor(Constants.COLOR_INK)
          .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(Constants.COLOR_SURFACE)
    .borderRadius(Constants.RADIUS_SM)
    .border({ width: 1, color: Constants.COLOR_LINE })
  }

  @Builder
  private taskPreviewPanel() {
    Column() {
      Row() {
        Column() {
          Text('确认本局任务')
            .width('100%')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_INK)
          Text('本局任务如下')
            .width('100%')
            .fontSize(12)
            .fontColor(Constants.COLOR_TEXT_MUTED)
            .margin({ top: 5 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('关闭')
          .height(44)
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .backgroundColor(Constants.COLOR_NEUTRAL)
          .borderRadius(Constants.RADIUS_PILL)
          .onClick(() => this.previewVisible = false)
      }
      .width('100%')

      Row() {
        Text(this.modeSummary())
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEAL)
        Blank()
        Text(`${this.previewTasks.length} 个任务 · 挑战程度：${this.riskLabel(this.riskLevel)}`)
          .fontSize(12)
          .fontColor(Constants.COLOR_TEXT_SUB)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 11, bottom: 11 })
      .margin({ top: 16 })
      .backgroundColor(Constants.COLOR_TRUTH_LIGHT)
      .borderRadius(Constants.RADIUS_SM)

      Text('不想做可以跳过。注意安全，别打扰没参加的人。')
        .width('100%')
        .fontSize(12)
        .lineHeight(18)
        .fontColor(Constants.COLOR_TEXT_MUTED)
        .margin({ top: 12, bottom: 10 })

      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.previewTasks, (task: TaskItem, index: number) => {
            this.previewTaskRow(task, index)
          }, (task: TaskItem) => task.id)
        }
        .width('100%')
        .padding({ bottom: 6 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)

      Row() {
        Button('重新生成')
          .layoutWeight(1)
          .height(50)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .backgroundColor(Constants.COLOR_NEUTRAL)
          .borderRadius(Constants.RADIUS_SM)
          .onClick(() => this.generateTaskPreview())
        Button('确认开局')
          .layoutWeight(1)
          .height(50)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_WHITE)
          .backgroundColor(Constants.COLOR_ORANGE)
          .borderRadius(Constants.RADIUS_SM)
          .margin({ left: 12 })
          .onClick(() => this.confirmStartGame())
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('calc(100% - 24vp)')
    .height('84%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, top: 22, bottom: 20 })
    .backgroundColor(Constants.COLOR_PAPER)
    .borderRadius(Constants.RADIUS_LG)
    .shadow({ radius: 30, color: 'rgba(36,17,23,0.28)', offsetX: 0, offsetY: 12 })
    .margin({ bottom: 10 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
      Column() {
        Row() {
          Text('真心话 · 大冒险')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_GOLD)
            .letterSpacing(1.8)
          Blank()
          Text('朋友聚会')
            .fontSize(11)
            .fontColor(Constants.COLOR_DARK_SUB)
        }
        .width('100%')

        Text('冒险大转盘')
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_WHITE)
          .margin({ top: 18 })
          .width('100%')

        Text('选好玩法，生成转盘，大家轮流来。')
          .fontSize(15)
          .lineHeight(23)
          .fontColor(Constants.COLOR_DARK_MUTED)
          .margin({ top: 10 })
          .width('100%')
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 26, bottom: 26 })
      .backgroundColor(Constants.COLOR_INK)

      Scroll() {
        Column() {
          Text('这局怎么玩')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_SUB)
            .letterSpacing(1.2)
            .width('100%')
            .margin({ bottom: 12 })

          ModeSelector({
            selectedMode: this.mode,
            onChange: (value: GameMode) => this.mode = value
          })

          Text(this.modeSummary())
            .fontSize(12)
            .fontColor(Constants.COLOR_TEXT_MUTED)
            .width('100%')
            .margin({ top: 9, left: 2 })

          TaskCountSlider({
            count: this.taskCount,
            onChange: (value: number) => this.taskCount = value
          })
          .margin({ top: 20 })

          Column() {
            Row() {
              Text('挑战程度')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(Constants.COLOR_INK)
              Blank()
              Text('最多会抽到这个程度的任务')
                .fontSize(11)
                .fontColor(Constants.COLOR_TEXT_MUTED)
            }
            .width('100%')
            .margin({ bottom: 14 })
            Row() {
              this.riskButton(RiskLevel.LIGHT)
              this.riskButton(RiskLevel.MEDIUM)
              this.riskButton(RiskLevel.DEEP)
            }
            .width('100%')
          }
          .width('100%')
          .padding(20)
          .margin({ top: 20 })
          .backgroundColor(Constants.COLOR_SURFACE)
          .borderRadius(Constants.RADIUS_MD)
          .border({ width: 1, color: Constants.COLOR_LINE })

          Row() {
            Column() {
              Text('任务库')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(Constants.COLOR_INK)
                .width('100%')
              Text(`内置 ${this.builtInTaskCount} 条 · 我添加的 ${this.customTaskCount} 条`)
                .fontSize(13)
                .fontColor(Constants.COLOR_TEXT_SUB)
                .margin({ top: 7 })
                .width('100%')
              Text(`我添加的任务中，已启用 ${this.enabledTaskCount} 条。`)
                .fontSize(12)
                .lineHeight(19)
                .fontColor(Constants.COLOR_TEXT_MUTED)
                .margin({ top: 12 })
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Button('查看')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_TEAL)
              .backgroundColor(Constants.COLOR_TRUTH_LIGHT)
              .borderRadius(Constants.RADIUS_PILL)
              .height(40)
              .onClick(() => this.openTaskLibrary())
          }
          .width('100%')
          .padding(20)
          .margin({ top: 20, bottom: 18 })
          .borderRadius(Constants.RADIUS_MD)
          .backgroundColor(Constants.COLOR_SURFACE)
          .border({ width: 1, color: Constants.COLOR_LINE })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 22 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      if (this.setupStatusText.length > 0) {
        Text(this.setupStatusText)
          .width('calc(100% - 36vp)')
          .fontSize(12)
          .fontColor(Constants.COLOR_DANGER)
          .margin({ bottom: 4 })
      }

      Button('立即开始')
        .width('calc(100% - 36vp)')
        .height(56)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_WHITE)
        .backgroundColor(Constants.COLOR_ORANGE)
        .borderRadius(Constants.RADIUS_SM)
        .shadow(this.isPressed ? {
          radius: Constants.SHADOW_PRESS_RADIUS,
          color: Constants.SHADOW_PRESS_COLOR,
          offsetX: 0,
          offsetY: Constants.SHADOW_PRESS_OFFSET_Y
        } : {
          radius: Constants.SHADOW_SM_RADIUS,
          color: Constants.SHADOW_SM_COLOR,
          offsetX: 0,
          offsetY: Constants.SHADOW_SM_OFFSET_Y
        })
        .scale(this.isPressed ? { x: 0.98, y: 0.98 } : { x: 1, y: 1 })
        .margin({ bottom: 24, top: 8 })
        .onClick(() => this.generateTaskPreview())
        .onTouch((event: TouchEvent) => this.isPressed = event.type === TouchType.Down)
        .animation({ duration: Constants.CLAY_ANIM_FAST, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Constants.COLOR_PAPER)

      if (this.previewVisible) {
        Column() {}
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(36,17,23,0.72)')
        this.taskPreviewPanel()
      }
    }
    .width('100%')
    .height('100%')
  }
}
