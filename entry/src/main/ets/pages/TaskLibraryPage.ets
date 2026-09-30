import { Constants } from '../common/Constants';
import { getAllBuiltInTasks } from '../data/task-source';
import { LocalTaskRecord } from '../model/LocalTaskRecord';
import { RiskLevel, TaskItem, TaskType } from '../model/TaskItem';
import { LocalTaskStore } from '../store/LocalTaskStore';
import { ImportPreview } from '../model/LocalTaskRecord';
import { TaskTransferService } from '../service/TaskTransferService';
import { TaskTextRules } from '../service/TaskTextRules';

enum LibraryTab {
  PRESET = 'preset',
  CUSTOM = 'custom'
}

@Entry
@Component
struct TaskLibraryPage {
  @State activeTab: LibraryTab = LibraryTab.PRESET;
  @State keyword: string = '';
  @State typeFilter: string = 'all';
  @State riskFilter: string = 'all';
  @State localTasks: LocalTaskRecord[] = [];
  @State editorVisible: boolean = false;
  @State editorId: string = '';
  @State editorText: string = '';
  @State editorType: TaskType = TaskType.TRUTH;
  @State editorLevel: RiskLevel = RiskLevel.LIGHT;
  @State editorEnabled: boolean = true;
  @State statusText: string = '';
  private presetTasks: TaskItem[] = getAllBuiltInTasks();

  aboutToAppear(): void {
    this.reloadLocalTasks();
  }

  private async reloadLocalTasks(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        throw new Error('无法获取页面上下文');
      }
      await LocalTaskStore.init(context);
      this.localTasks = await LocalTaskStore.list();
    } catch (error) {
      this.statusText = '暂时无法读取本地任务';
      console.error(`TaskLibraryPage: ${JSON.stringify(error)}`);
    }
  }

  private visiblePresets(): TaskItem[] {
    const key = this.keyword.trim().toLowerCase();
    return this.presetTasks.filter((task: TaskItem) => {
      const typeMatched = this.typeFilter === 'all' || task.type === this.typeFilter;
      const riskMatched = this.riskFilter === 'all' || task.level === this.riskFilter;
      return typeMatched && riskMatched && (key.length === 0 || task.text.toLowerCase().includes(key));
    });
  }

  private visibleCustomTasks(): LocalTaskRecord[] {
    const key = this.keyword.trim().toLowerCase();
    return this.localTasks.filter((task: LocalTaskRecord) => {
      const typeMatched = this.typeFilter === 'all' || task.type === this.typeFilter;
      const riskMatched = this.riskFilter === 'all' || task.level === this.riskFilter;
      return typeMatched && riskMatched && (key.length === 0 || task.text.toLowerCase().includes(key));
    });
  }

  private typeLabel(type: TaskType): string {
    return type === TaskType.TRUTH ? '真心话' : '大冒险';
  }

  private levelLabel(level: RiskLevel): string {
    if (level === RiskLevel.LIGHT) {
      return '轻松';
    }
    if (level === RiskLevel.MEDIUM) {
      return '适中';
    }
    return '深入';
  }

  private openCreateEditor(): void {
    this.editorId = '';
    this.editorText = '';
    this.editorType = TaskType.TRUTH;
    this.editorLevel = RiskLevel.LIGHT;
    this.editorEnabled = true;
    this.statusText = '';
    this.editorVisible = true;
  }

  private openEditEditor(task: LocalTaskRecord): void {
    this.editorId = task.id;
    this.editorText = task.text;
    this.editorType = task.type;
    this.editorLevel = task.level;
    this.editorEnabled = task.enabled;
    this.statusText = '';
    this.editorVisible = true;
  }

  private async saveEditor(): Promise<void> {
    const text = this.editorText.trim();
    const editorId = this.editorId;
    const editorType = this.editorType;
    const editorLevel = this.editorLevel;
    const editorEnabled = this.editorEnabled;
    if (text.length === 0) {
      this.statusText = '请输入任务内容';
      return;
    }
    if (TaskTextRules.count(text) > Constants.CUSTOM_TASK_MAX_LENGTH) {
      this.statusText = `任务内容最多 ${Constants.CUSTOM_TASK_MAX_LENGTH} 个字`;
      return;
    }
    if (await LocalTaskStore.hasDuplicate(editorType, text, editorId)) {
      this.statusText = '同类型中已经有相同任务';
      return;
    }
    if (editorId.length === 0) {
      await LocalTaskStore.add(editorType, editorLevel, text, editorEnabled);
    } else {
      const original = this.localTasks.find((item: LocalTaskRecord) => item.id === editorId);
      if (original) {
        const record: LocalTaskRecord = {
          id: original.id,
          type: editorType,
          level: editorLevel,
          text: text,
          enabled: editorEnabled,
          createdAt: original.createdAt,
          updatedAt: Date.now()
        };
        await LocalTaskStore.update(record);
      }
    }
    this.editorVisible = false;
    await this.reloadLocalTasks();
  }

  private requestDelete(task: LocalTaskRecord): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除这条任务？',
      message: task.text,
      buttons: [
        { text: '取消', color: Constants.COLOR_TEXT_SUB },
        { text: '删除', color: Constants.COLOR_DANGER }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.deleteTask(task.id);
      }
    }).catch((error: Error) => {
      console.error(`TaskLibraryPage: 删除确认框失败 ${error.message}`);
    });
  }

  private async deleteTask(id: string): Promise<void> {
    await LocalTaskStore.remove(id);
    await this.reloadLocalTasks();
  }

  private async toggleTask(task: LocalTaskRecord, enabled: boolean): Promise<void> {
    await LocalTaskStore.setEnabled(task.id, enabled);
    await this.reloadLocalTasks();
  }

  private async importTasks(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        throw new Error('无法获取页面上下文');
      }
      const preview = await TaskTransferService.selectImport(context, this.localTasks);
      this.showImportPreview(preview);
    } catch (error) {
      this.statusText = `导入未完成：${(error as Error).message}`;
    }
  }

  private showImportPreview(preview: ImportPreview): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '要导入这些任务吗？',
      message: `可以添加 ${preview.validCount} 条。重复的 ${preview.duplicateCount} 条、不符合要求的 ${preview.invalidCount} 条会自动跳过。`,
      buttons: [
        { text: '取消', color: Constants.COLOR_TEXT_SUB },
        { text: '确认导入', color: Constants.COLOR_TEAL }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.confirmImport(preview);
      }
    }).catch((error: Error) => {
      this.statusText = `导入确认未完成：${error.message}`;
    });
  }

  private async confirmImport(preview: ImportPreview): Promise<void> {
    const added = await LocalTaskStore.mergeImported(preview.validTasks);
    await this.reloadLocalTasks();
    this.activeTab = LibraryTab.CUSTOM;
    this.statusText = `已导入 ${added} 条任务`;
  }

  private async exportTasks(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        throw new Error('无法获取页面上下文');
      }
      const count = await TaskTransferService.exportTasks(context, this.localTasks);
      this.statusText = `已导出 ${count} 条任务`;
    } catch (error) {
      this.statusText = `导出未完成：${(error as Error).message}`;
    }
  }

  private async shareTasks(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) {
        throw new Error('无法获取页面上下文');
      }
      await TaskTransferService.shareTasks(context, this.localTasks);
      this.statusText = '';
    } catch (error) {
      this.statusText = `分享未完成：${(error as Error).message}`;
    }
  }

  @Builder
  private filterButton(label: string, value: string) {
    Button(label)
      .height(34)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.typeFilter === value ? Constants.COLOR_WHITE : Constants.COLOR_TEXT_SUB)
      .backgroundColor(this.typeFilter === value ? Constants.COLOR_TEAL : Constants.COLOR_NEUTRAL)
      .borderRadius(Constants.RADIUS_PILL)
      .onClick(() => this.typeFilter = value)
  }

  @Builder
  private riskFilterButton(label: string, value: string) {
    Button(label)
      .height(30)
      .fontSize(12)
      .fontColor(this.riskFilter === value ? Constants.COLOR_INK : Constants.COLOR_TEXT_MUTED)
      .backgroundColor(this.riskFilter === value ? Constants.COLOR_GOLD : Color.Transparent)
      .borderRadius(Constants.RADIUS_PILL)
      .onClick(() => this.riskFilter = value)
  }

  @Builder
  private presetRow(task: TaskItem) {
    Column() {
      Row() {
        Text(this.typeLabel(task.type))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(task.type === TaskType.TRUTH ? Constants.COLOR_TEAL : Constants.COLOR_ORANGE)
        Text(this.levelLabel(task.level))
          .fontSize(11)
          .fontColor(Constants.COLOR_TEXT_MUTED)
          .margin({ left: 10 })
      }
      .width('100%')

      Text(task.text)
        .fontSize(15)
        .lineHeight(22)
        .fontColor(Constants.COLOR_INK)
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 15, bottom: 15 })
    .backgroundColor(Constants.COLOR_SURFACE)
    .borderRadius(Constants.RADIUS_SM)
    .border({ width: 1, color: Constants.COLOR_LINE })
  }

  @Builder
  private customRow(task: LocalTaskRecord) {
    Row() {
      Column() {
        Row() {
          Text(this.typeLabel(task.type))
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(task.type === TaskType.TRUTH ? Constants.COLOR_TEAL : Constants.COLOR_ORANGE)
          Text(this.levelLabel(task.level))
            .fontSize(11)
            .fontColor(Constants.COLOR_TEXT_MUTED)
            .margin({ left: 10 })
        }
        .width('100%')
        Text(task.text)
          .fontSize(15)
          .lineHeight(22)
          .fontColor(task.enabled ? Constants.COLOR_INK : Constants.COLOR_TEXT_MUTED)
          .width('100%')
          .margin({ top: 7 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column() {
        Toggle({ type: ToggleType.Switch, isOn: task.enabled })
          .selectedColor(Constants.COLOR_TEAL)
          .onChange((value: boolean) => this.toggleTask(task, value))
        Row() {
          Button('编辑')
            .fontSize(12)
            .height(30)
            .fontColor(Constants.COLOR_TEAL)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.openEditEditor(task))
          Button('删除')
            .fontSize(12)
            .height(30)
            .fontColor(Constants.COLOR_DANGER)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.requestDelete(task))
        }
        .margin({ top: 8 })
      }
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 16, right: 10, top: 15, bottom: 12 })
    .backgroundColor(Constants.COLOR_SURFACE)
    .borderRadius(Constants.RADIUS_SM)
    .border({ width: 1, color: Constants.COLOR_LINE })
  }

  @Builder
  private editorPanel() {
    Column() {
      Row() {
        Text(this.editorId.length === 0 ? '添加任务' : '编辑任务')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_INK)
        Blank()
        Button('关闭')
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_SUB)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.editorVisible = false)
      }
      .width('100%')

      Text('任务类型')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT_SUB)
        .width('100%')
        .margin({ top: 20, bottom: 8 })
      Row() {
        Button('真心话')
          .layoutWeight(1)
          .fontColor(this.editorType === TaskType.TRUTH ? Constants.COLOR_WHITE : Constants.COLOR_TEAL)
          .backgroundColor(this.editorType === TaskType.TRUTH ? Constants.COLOR_TEAL : Constants.COLOR_TRUTH_LIGHT)
          .onClick(() => this.editorType = TaskType.TRUTH)
        Button('大冒险')
          .layoutWeight(1)
          .margin({ left: 10 })
          .fontColor(this.editorType === TaskType.DARE ? Constants.COLOR_WHITE : Constants.COLOR_ORANGE)
          .backgroundColor(this.editorType === TaskType.DARE ? Constants.COLOR_ORANGE : Constants.COLOR_DARE_LIGHT)
          .onClick(() => this.editorType = TaskType.DARE)
      }
      .width('100%')

      Text('任务内容')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT_SUB)
        .width('100%')
        .margin({ top: 18, bottom: 8 })
      TextArea({ text: this.editorText, placeholder: '写一个大家都愿意玩的任务' })
        .height(110)
        .fontSize(15)
        .maxLength(Constants.CUSTOM_TASK_MAX_LENGTH)
        .backgroundColor(Constants.COLOR_INPUT)
        .borderRadius(Constants.RADIUS_SM)
        .onChange((value: string) => {
          this.editorText = TaskTextRules.limit(value);
          if (this.statusText.startsWith('任务内容')) {
            this.statusText = '';
          }
        })

      Row() {
        Text(`最多 ${Constants.CUSTOM_TASK_MAX_LENGTH} 个字`)
          .fontSize(11)
          .fontColor(Constants.COLOR_TEXT_MUTED)
        Blank()
        Text(`${TaskTextRules.count(this.editorText)}/${Constants.CUSTOM_TASK_MAX_LENGTH}`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_SUB)
      }
      .width('100%')
      .margin({ top: 6 })

      Text('不想做可以跳过。别做危险的事，也不要打扰没参加的人。')
        .width('100%')
        .fontSize(11)
        .lineHeight(17)
        .fontColor(Constants.COLOR_TEXT_MUTED)
        .margin({ top: 6 })

      Text('挑战程度')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT_SUB)
        .width('100%')
        .margin({ top: 18, bottom: 8 })
      Row() {
        ForEach([RiskLevel.LIGHT, RiskLevel.MEDIUM, RiskLevel.DEEP], (level: RiskLevel) => {
          Button(this.levelLabel(level))
            .layoutWeight(1)
            .height(38)
            .fontSize(13)
            .fontColor(this.editorLevel === level ? Constants.COLOR_WHITE : Constants.COLOR_TEXT_SUB)
            .backgroundColor(this.editorLevel === level ? Constants.COLOR_INK : Constants.COLOR_NEUTRAL)
            .margin({ right: level === RiskLevel.DEEP ? 0 : 8 })
            .onClick(() => this.editorLevel = level)
        })
      }
      .width('100%')

      Row() {
        Text('加入转盘')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT_SUB)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.editorEnabled })
          .selectedColor(Constants.COLOR_TEAL)
          .onChange((value: boolean) => this.editorEnabled = value)
      }
      .width('100%')
      .margin({ top: 18 })

      if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(12)
          .fontColor(Constants.COLOR_DANGER)
          .width('100%')
          .margin({ top: 12 })
      }

      Button('保存任务')
        .width('100%')
        .height(50)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_WHITE)
        .backgroundColor(Constants.COLOR_ORANGE)
        .borderRadius(Constants.RADIUS_SM)
        .margin({ top: 22 })
        .onClick(() => this.saveEditor())
    }
    .width('calc(100% - 32vp)')
    .padding(22)
    .borderRadius(Constants.RADIUS_LG)
    .backgroundColor(Constants.COLOR_SURFACE)
    .shadow({ radius: 28, color: 'rgba(36,17,23,0.24)', offsetX: 0, offsetY: 12 })
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
          Column() {
            Text('任务库')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_WHITE)
              .width('100%')
            Text('看看内置任务，也可以添加自己的任务')
              .fontSize(11)
              .fontColor(Constants.COLOR_DARK_SUB)
              .margin({ top: 4 })
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 8, right: 14, top: 18, bottom: 18 })
        .backgroundColor(Constants.COLOR_INK)

        Row() {
          Button(`内置任务 ${this.presetTasks.length}`)
            .layoutWeight(1)
            .height(42)
            .fontColor(this.activeTab === LibraryTab.PRESET ? Constants.COLOR_WHITE : Constants.COLOR_TEXT_SUB)
            .backgroundColor(this.activeTab === LibraryTab.PRESET ? Constants.COLOR_TEAL : Color.Transparent)
            .onClick(() => this.activeTab = LibraryTab.PRESET)
          Button(`我添加的 ${this.localTasks.length}`)
            .layoutWeight(1)
            .height(42)
            .fontColor(this.activeTab === LibraryTab.CUSTOM ? Constants.COLOR_WHITE : Constants.COLOR_TEXT_SUB)
            .backgroundColor(this.activeTab === LibraryTab.CUSTOM ? Constants.COLOR_TEAL : Color.Transparent)
            .onClick(() => this.activeTab = LibraryTab.CUSTOM)
        }
        .width('calc(100% - 32vp)')
        .padding(3)
        .borderRadius(Constants.RADIUS_SM)
        .backgroundColor(Constants.COLOR_NEUTRAL)
        .margin({ top: 16 })

        TextInput({ text: this.keyword, placeholder: '搜索任务内容' })
          .width('calc(100% - 32vp)')
          .height(44)
          .fontSize(14)
          .backgroundColor(Constants.COLOR_SURFACE)
          .borderRadius(Constants.RADIUS_SM)
          .border({ width: 1, color: Constants.COLOR_LINE })
          .margin({ top: 12 })
          .onChange((value: string) => this.keyword = value)

        Row() {
          this.filterButton('全部', 'all')
          this.filterButton('真心话', TaskType.TRUTH)
          this.filterButton('大冒险', TaskType.DARE)
          Blank()
          if (this.activeTab === LibraryTab.CUSTOM) {
            Button('添加')
              .height(34)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_WHITE)
              .backgroundColor(Constants.COLOR_ORANGE)
              .onClick(() => this.openCreateEditor())
          }
        }
        .width('calc(100% - 32vp)')
        .margin({ top: 10, bottom: 10 })

        Row() {
          Text('挑战')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_MUTED)
            .margin({ right: 6 })
          this.riskFilterButton('全部', 'all')
          this.riskFilterButton('轻松', RiskLevel.LIGHT)
          this.riskFilterButton('适中', RiskLevel.MEDIUM)
          this.riskFilterButton('深入', RiskLevel.DEEP)
        }
        .width('calc(100% - 32vp)')
        .margin({ bottom: 8 })

        if (this.activeTab === LibraryTab.CUSTOM) {
          Row({ space: 8 }) {
            Button('导入任务')
              .layoutWeight(1)
              .height(38)
              .fontSize(12)
              .fontColor(Constants.COLOR_TEAL)
              .backgroundColor(Constants.COLOR_TRUTH_LIGHT)
              .onClick(() => this.importTasks())
            Button('导出任务')
              .layoutWeight(1)
              .height(38)
              .fontSize(12)
              .fontColor(Constants.COLOR_TEAL)
              .backgroundColor(Constants.COLOR_TRUTH_LIGHT)
              .onClick(() => this.exportTasks())
            Button('分享我的任务')
              .layoutWeight(1.35)
              .height(38)
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_WHITE)
              .backgroundColor(Constants.COLOR_ORANGE)
              .enabled(this.localTasks.length > 0)
              .opacity(this.localTasks.length > 0 ? 1 : 0.45)
              .onClick(() => this.shareTasks())
          }
          .width('calc(100% - 32vp)')
          .margin({ bottom: 10 })
        }

        if (this.statusText.length > 0 && !this.editorVisible) {
          Text(this.statusText)
            .width('calc(100% - 32vp)')
            .fontSize(12)
            .fontColor(Constants.COLOR_TEXT_SUB)
            .padding({ bottom: 8 })
        }

        if ((this.activeTab === LibraryTab.PRESET && this.visiblePresets().length === 0) ||
          (this.activeTab === LibraryTab.CUSTOM && this.visibleCustomTasks().length === 0)) {
          Column() {
            Text(this.activeTab === LibraryTab.CUSTOM && this.localTasks.length === 0 ? '还没有自己添加的任务' : '没有符合条件的任务')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_INK)
            Text(this.activeTab === LibraryTab.CUSTOM && this.localTasks.length === 0 ? '添加一条，或者把以前导出的任务导进来。' : '换个关键词或筛选条件试试。')
              .fontSize(13)
              .fontColor(Constants.COLOR_TEXT_MUTED)
              .margin({ top: 8 })
            if (this.activeTab === LibraryTab.CUSTOM && this.localTasks.length === 0) {
              Row() {
                Button('添加任务')
                  .fontColor(Constants.COLOR_WHITE)
                  .backgroundColor(Constants.COLOR_ORANGE)
                  .onClick(() => this.openCreateEditor())
                Button('导入任务')
                  .fontColor(Constants.COLOR_TEAL)
                  .backgroundColor(Constants.COLOR_TRUTH_LIGHT)
                  .margin({ left: 10 })
                  .onClick(() => this.importTasks())
              }
              .margin({ top: 18 })
            }
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 10 }) {
          if (this.activeTab === LibraryTab.PRESET) {
            ForEach(this.visiblePresets(), (task: TaskItem) => {
              ListItem() { this.presetRow(task) }
            }, (task: TaskItem) => task.id)
          } else {
            ForEach(this.visibleCustomTasks(), (task: LocalTaskRecord) => {
              ListItem() { this.customRow(task) }
            }, (task: LocalTaskRecord) => task.id)
          }
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Constants.COLOR_PAPER)

      if (this.editorVisible) {
        Column() {}
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(36,17,23,0.56)')
          .onClick(() => this.editorVisible = false)
        this.editorPanel()
      }
    }
    .width('100%')
    .height('100%')
  }
}
