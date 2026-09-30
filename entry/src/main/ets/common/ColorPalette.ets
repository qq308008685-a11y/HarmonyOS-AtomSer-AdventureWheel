import { GameMode } from '../model/GameConfig';
import { TaskItem, TaskType } from '../model/TaskItem';
import { Constants } from './Constants';

const TRUTH_PALETTE: string[] = ['#2E5D67', '#3F7681', '#4F8793', '#5F98A4'];
const DARE_PALETTE: string[] = ['#7E2435', '#9E2B41', '#B8324B', '#C94E60'];

export function generateSectorColors(tasks: TaskItem[], mode: GameMode): string[] {
  const colors: string[] = [];
  for (let i = 0; i < tasks.length; i++) {
    const useDarePalette = mode === GameMode.DARE_ONLY ||
      (mode === GameMode.MIXED && tasks[i].type === TaskType.DARE);
    const palette = useDarePalette ? DARE_PALETTE : TRUTH_PALETTE;
    colors.push(palette[i % palette.length]);
  }
  return colors;
}

export function getModePrimaryColor(mode: GameMode): string {
  return mode === GameMode.DARE_ONLY ? Constants.COLOR_ORANGE : Constants.COLOR_TEAL;
}

export function getModeLightColor(mode: GameMode): string {
  return mode === GameMode.DARE_ONLY ? Constants.COLOR_DARE_LIGHT : Constants.COLOR_TRUTH_LIGHT;
}
