import { TaskItem, TaskType } from '../model/TaskItem';
import { GameMode } from '../model/GameConfig';
import { generateSectorColors } from '../common/ColorPalette';
import { Constants } from '../common/Constants';
import { SoundEngine } from '../engine/SoundEngine';
import { WheelRoundState } from '../engine/WheelRoundState';

@Component
export struct WheelCanvas {
  @Prop @Watch('onTasksChange') tasks: TaskItem[] = [];
  @Prop mode: GameMode = GameMode.MIXED;
  @Prop @Watch('onRoundChange') round: number = 1;
  @Prop @Watch('onCompletedTasksChange') completedTaskIds: string[] = [];
  onResult?: (task: TaskItem) => void;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasWidth: number = 300;
  private canvasHeight: number = 300;
  private wheelRadius: number = 0;
  private centerRadius: number = 0;
  private cx: number = 0;
  private cy: number = 0;
  private currentAngle: number = 0;
  @State private isSpinning: boolean = false;
  @State private isSettling: boolean = false;
  private sectorColors: string[] = [];
  private animationTimer: number = -1;
  private animStartTime: number = 0;
  private startAngle: number = 0;
  private targetAngle: number = 0;
  private totalDuration: number = 0;
  private lastSectorIndex: number = -1;
  private selectedIndex: number = -1;
  private pointerOffsetY: number = 0;
  private resultTimer: number = -1;

  aboutToAppear(): void {
    this.sectorColors = generateSectorColors(this.tasks, this.mode);
  }

  onTasksChange(): void {
    this.sectorColors = generateSectorColors(this.tasks, this.mode);
    this.currentAngle = 0;
    this.selectedIndex = -1;
    this.isSettling = false;
    this.drawWheel();
  }

  onRoundChange(): void {
    if (this.resultTimer >= 0) {
      clearTimeout(this.resultTimer);
      this.resultTimer = -1;
    }
    this.selectedIndex = -1;
    this.pointerOffsetY = 0;
    this.isSettling = false;
    this.drawWheel();
  }

  onCompletedTasksChange(): void {
    this.selectedIndex = -1;
    this.pointerOffsetY = 0;
    this.drawWheel();
  }

  aboutToDisappear(): void {
    if (this.animationTimer >= 0) {
      clearInterval(this.animationTimer);
    }
    if (this.resultTimer >= 0) {
      clearTimeout(this.resultTimer);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .rotate({ x: 1, y: 0, z: 0, angle: 10, perspective: 650 })
        .hitTestBehavior(HitTestMode.None)
        .onReady(() => {
          this.canvasWidth = this.ctx.width;
          this.canvasHeight = this.ctx.height;
          const size = Math.min(this.canvasWidth, this.canvasHeight);
          this.wheelRadius = size * 0.39;
          this.centerRadius = this.wheelRadius * 0.2;
          this.cx = this.canvasWidth / 2;
          this.cy = this.canvasHeight / 2 - 4;
          this.drawWheel();
        })

      Button(this.isSpinning ? '转动' : this.isSettling ? '选中' :
        this.hasAvailableTasks() ? '开始' : '完成', { type: ButtonType.Circle })
        .width(64)
        .height(64)
        .padding(0)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isSpinning ? Constants.COLOR_DARK_TEXT : Constants.COLOR_INK)
        .backgroundColor(this.isSpinning || !this.hasAvailableTasks() ?
          Constants.COLOR_TEXT_SUB : Constants.COLOR_GOLD)
        .borderRadius(Constants.RADIUS_PILL)
        .border({ width: 4, color: Constants.COLOR_INK })
        .shadow({ radius: 12, color: 'rgba(36,17,23,0.34)', offsetX: 0, offsetY: 5 })
        .translate({ y: -4 })
        .enabled(!this.isSpinning && !this.isSettling && this.hasAvailableTasks())
        .onClick(() => this.startSpin())
    }
    .width('100%')
    .height('100%')
  }

  private drawWheel(): void {
    const count = this.tasks.length;
    if (count === 0 || this.cx === 0) {
      return;
    }
    this.ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    const sectorAngle = (2 * Math.PI) / count;

    this.ctx.save();
    this.ctx.shadowBlur = 28;
    this.ctx.shadowColor = 'rgba(36,17,23,0.42)';
    this.ctx.shadowOffsetY = 22;
    this.ctx.beginPath();
    this.ctx.arc(this.cx, this.cy + 13, this.wheelRadius, 0, 2 * Math.PI);
    this.ctx.fillStyle = '#32141D';
    this.ctx.fill();
    this.ctx.restore();

    for (let layer = 10; layer >= 1; layer--) {
      this.ctx.beginPath();
      this.ctx.arc(this.cx, this.cy + layer * 1.3, this.wheelRadius, 0, 2 * Math.PI);
      this.ctx.fillStyle = layer % 2 === 0 ? '#4A1D29' : '#35151E';
      this.ctx.fill();
    }

    for (let i = 0; i < count; i++) {
      const isSelected = i === this.selectedIndex;
      const isCompleted = this.isTaskCompleted(i);
      this.ctx.save();
      if (this.selectedIndex >= 0 && !isSelected) {
        this.ctx.globalAlpha = 0.42;
      }
      const start = this.toRadians(this.currentAngle) + i * sectorAngle - Math.PI / 2;
      const end = start + sectorAngle;
      this.ctx.beginPath();
      this.ctx.moveTo(this.cx, this.cy);
      this.ctx.arc(this.cx, this.cy, this.wheelRadius, start, end);
      this.ctx.closePath();
      this.ctx.fillStyle = isCompleted ? Constants.COLOR_COMPLETED_SECTOR :
        this.sectorColors[i % this.sectorColors.length];
      this.ctx.fill();
      this.ctx.strokeStyle = isSelected ? Constants.COLOR_GOLD :
        isCompleted ? Constants.COLOR_COMPLETED_BORDER : 'rgba(255,243,222,0.72)';
      this.ctx.lineWidth = isSelected ? 6 : 1.5;
      this.ctx.stroke();

      const mid = start + sectorAngle / 2;
      const labelRadius = this.wheelRadius * 0.66;
      const x = this.cx + labelRadius * Math.cos(mid);
      const y = this.cy + labelRadius * Math.sin(mid);
      this.ctx.save();
      this.ctx.translate(x, y);
      this.ctx.rotate(mid + Math.PI / 2);
      this.ctx.fillStyle = isCompleted ? Constants.COLOR_COMPLETED_TEXT : Constants.COLOR_WHITE;
      this.ctx.font = `bold ${count > 12 ? 13 : 15}px "HarmonyOS Sans SC"`;
      this.ctx.textAlign = 'center';
      this.ctx.textBaseline = 'middle';
      const type = this.tasks[i].type === TaskType.TRUTH ? '真心' : '冒险';
      const number = i + 1 < 10 ? `0${i + 1}` : `${i + 1}`;
      this.ctx.fillText(isCompleted ? `${number} 完成` : `${number} ${type}`, 0, 0);
      this.ctx.restore();
      this.ctx.restore();
    }

    this.ctx.beginPath();
    this.ctx.arc(this.cx, this.cy, this.wheelRadius, 0, 2 * Math.PI);
    this.ctx.strokeStyle = Constants.COLOR_GOLD;
    this.ctx.lineWidth = 5;
    this.ctx.stroke();

    this.drawCenterButton();
    this.drawPointer();
  }

  private drawPointer(): void {
    const top = this.cy - this.wheelRadius - 10 + this.pointerOffsetY;
    const size = Constants.POINTER_SIZE;
    this.ctx.save();
    this.ctx.shadowBlur = 10;
    this.ctx.shadowColor = 'rgba(36,17,23,0.42)';
    this.ctx.shadowOffsetY = 4;
    this.ctx.beginPath();
    this.ctx.moveTo(this.cx, top + size * 1.15);
    this.ctx.lineTo(this.cx - size * 0.62, top);
    this.ctx.lineTo(this.cx + size * 0.62, top);
    this.ctx.closePath();
    this.ctx.fillStyle = Constants.COLOR_GOLD;
    this.ctx.fill();
    this.ctx.strokeStyle = Constants.COLOR_SURFACE;
    this.ctx.lineWidth = 3;
    this.ctx.stroke();
    this.ctx.restore();
  }

  private drawCenterButton(): void {
    this.ctx.save();
    this.ctx.shadowBlur = 14;
    this.ctx.shadowColor = 'rgba(36,17,23,0.42)';
    this.ctx.shadowOffsetY = 5;
    this.ctx.beginPath();
    this.ctx.arc(this.cx, this.cy, this.centerRadius, 0, 2 * Math.PI);
    this.ctx.fillStyle = Constants.COLOR_INK;
    this.ctx.fill();
    this.ctx.restore();

    this.ctx.beginPath();
    this.ctx.arc(this.cx, this.cy, this.centerRadius * 0.72, 0, 2 * Math.PI);
    this.ctx.fillStyle = Constants.COLOR_SURFACE;
    this.ctx.fill();
  }

  private startSpin(): void {
    const targetIndex = WheelRoundState.pickAvailableIndex(
      this.tasks, this.completedTaskIds, Math.random());
    if (this.isSpinning || this.isSettling || targetIndex < 0) {
      return;
    }
    this.selectedIndex = -1;
    this.pointerOffsetY = 0;
    this.isSpinning = true;
    const rotations = Constants.SPIN_MIN_ROTATIONS + Math.floor(
      Math.random() * (Constants.SPIN_MAX_ROTATIONS - Constants.SPIN_MIN_ROTATIONS + 1));
    const sectorAngle = 360 / this.tasks.length;
    const jitter = (Math.random() - 0.5) * sectorAngle * 0.36;
    this.startAngle = this.currentAngle;
    const currentNormalized = ((this.startAngle % 360) + 360) % 360;
    const landingAngle = (360 - (targetIndex + 0.5) * sectorAngle + jitter + 360) % 360;
    const landingDelta = (landingAngle - currentNormalized + 360) % 360;
    this.targetAngle = this.startAngle + rotations * 360 + landingDelta;
    this.totalDuration = Constants.SPIN_MIN_DURATION +
      Math.random() * (Constants.SPIN_MAX_DURATION - Constants.SPIN_MIN_DURATION);
    this.animStartTime = Date.now();
    this.lastSectorIndex = -1;
    this.animationTimer = setInterval(() => this.onAnimationFrame(), 16);
  }

  private onAnimationFrame(): void {
    const elapsed = Date.now() - this.animStartTime;
    const progress = Math.min(elapsed / this.totalDuration, 1);
    const eased = this.easeOutQuart(progress);
    this.currentAngle = this.startAngle + (this.targetAngle - this.startAngle) * eased;
    this.drawWheel();

    const sectorIndex = this.getResultIndex();
    if (sectorIndex !== this.lastSectorIndex) {
      this.lastSectorIndex = sectorIndex;
      SoundEngine.playTick();
    }
    if (progress >= 1) {
      this.stopSpin();
    }
  }

  private stopSpin(): void {
    clearInterval(this.animationTimer);
    this.animationTimer = -1;
    this.isSpinning = false;
    this.isSettling = true;
    SoundEngine.playStop();
    this.selectedIndex = this.getResultIndex();
    this.pointerOffsetY = 6;
    this.drawWheel();
    const result = this.getResultTask();
    setTimeout(() => {
      this.pointerOffsetY = 0;
      this.drawWheel();
    }, 120);
    this.resultTimer = setTimeout(() => {
      this.resultTimer = -1;
      if (result && this.onResult) {
        this.onResult(result);
      }
    }, Constants.RESULT_REVEAL_DELAY);
  }

  private getResultTask(): TaskItem | null {
    if (this.tasks.length === 0) {
      return null;
    }
    return this.tasks[this.getResultIndex()];
  }

  private getResultIndex(): number {
    if (this.tasks.length === 0) {
      return -1;
    }
    const sectorAngle = 360 / this.tasks.length;
    const pointerAngle = (360 - this.currentAngle % 360 + 360) % 360;
    return Math.floor(pointerAngle / sectorAngle) % this.tasks.length;
  }

  private isTaskCompleted(index: number): boolean {
    return index >= 0 && index < this.tasks.length &&
      this.completedTaskIds.indexOf(this.tasks[index].id) >= 0;
  }

  private hasAvailableTasks(): boolean {
    return WheelRoundState.availableIndices(this.tasks, this.completedTaskIds).length > 0;
  }

  private easeOutQuart(value: number): number {
    return 1 - Math.pow(1 - value, 4);
  }

  private toRadians(degrees: number): number {
    return degrees * Math.PI / 180;
  }
}
