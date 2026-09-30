import { LocalTaskRecord, TaskTransferPackage, TransferTaskRecord } from '../model/LocalTaskRecord';
import { TaskTransferValidator } from './TaskTransferValidator';

export class TaskTransferPackageBuilder {
  static build(tasks: LocalTaskRecord[]): TaskTransferPackage {
    const transferTasks: TransferTaskRecord[] = tasks.map((item: LocalTaskRecord): TransferTaskRecord => {
      return {
        type: item.type,
        level: item.level,
        text: item.text,
        enabled: item.enabled
      };
    });
    return {
      format: TaskTransferValidator.FORMAT,
      version: TaskTransferValidator.VERSION,
      tasks: transferTasks
    };
  }

  static stringify(tasks: LocalTaskRecord[]): string {
    return JSON.stringify(TaskTransferPackageBuilder.build(tasks), null, 2);
  }
}
