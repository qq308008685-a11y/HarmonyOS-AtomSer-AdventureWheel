import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { fileUri } from '@kit.CoreFileKit';
import { common, Want, wantConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ImportPreview, LocalTaskRecord } from '../model/LocalTaskRecord';
import { TaskTransferPackageBuilder } from './TaskTransferPackageBuilder';
import { TaskTransferValidator } from './TaskTransferValidator';

export class TaskTransferService {
  private static readonly MAX_FILE_SIZE = 1024 * 1024;

  static async selectImport(context: Context, existing: LocalTaskRecord[]): Promise<ImportPreview> {
    if (canIUse('SystemCapability.FileManagement.UserFileService')) {
      try {
        const documentPicker = new picker.DocumentViewPicker(context);
        const options = new picker.DocumentSelectOptions();
        options.fileSuffixFilters = ['任务文件|.json,.txt'];
        options.maxSelectNumber = 1;
        const uris = await documentPicker.select(options);
        if (uris.length === 0) {
          throw new Error('未选择文件');
        }
        const file = await fs.open(uris[0], fs.OpenMode.READ_ONLY);
        try {
          const fileStat = await fs.stat(file.fd);
          if (fileStat.size > TaskTransferService.MAX_FILE_SIZE) {
            throw new Error('导入文件不能超过 1 MiB（1,048,576 字节）');
          }
          const buffer = new ArrayBuffer(fileStat.size);
          const bytesRead = await fs.read(file.fd, buffer);
          const decoder = util.TextDecoder.create('utf-8');
          const content = decoder.decodeToString(new Uint8Array(buffer, 0, bytesRead));
          return TaskTransferValidator.parse(content, existing);
        } finally {
          await fs.close(file);
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : '文件读取失败';
        throw new Error(message);
      }
    }
    throw new Error('当前设备暂不支持选择文件');
  }

  static async exportTasks(context: Context, tasks: LocalTaskRecord[]): Promise<number> {
    if (tasks.length === 0) {
      throw new Error('还没有自己添加的任务可导出');
    }
    if (canIUse('SystemCapability.FileManagement.UserFileService')) {
      try {
        const documentPicker = new picker.DocumentViewPicker(context);
        const options = new picker.DocumentSaveOptions();
        options.newFileNames = [`adventure-wheel-tasks-${Date.now()}.json`];
        options.fileSuffixChoices = ['JSON|.json'];
        const uris = await documentPicker.save(options);
        if (uris.length === 0) {
          throw new Error('未选择保存位置');
        }
        const file = await fs.open(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try {
          await fs.write(file.fd, TaskTransferPackageBuilder.stringify(tasks));
        } finally {
          await fs.close(file);
        }
        return tasks.length;
      } catch (error) {
        const message = error instanceof Error ? error.message : '文件写入失败';
        throw new Error(message);
      }
    }
    throw new Error('当前设备暂不支持保存文件');
  }

  static async shareTasks(context: Context, tasks: LocalTaskRecord[]): Promise<number> {
    if (tasks.length === 0) {
      throw new Error('还没有自己添加的任务可分享');
    }
    try {
      const path = `${context.filesDir}/adventure-wheel-my-tasks.txt`;
      const file = await fs.open(path,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        await fs.write(file.fd, TaskTransferPackageBuilder.stringify(tasks));
      } finally {
        await fs.close(file);
      }
      const uri = fileUri.getUriFromPath(path);
      const sendWant: Want = {
        action: 'ohos.want.action.sendData',
        uri: uri,
        type: 'text/plain',
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
        parameters: {
          'ability.params.stream': [uri],
          'ohos.extra.param.key.contentTitle': '冒险大转盘 · 我的任务',
          'ohos.extra.param.key.shareAbstract': `共 ${tasks.length} 条任务`
        }
      };
      await (context as common.UIAbilityContext).startAbility(sendWant);
      return tasks.length;
    } catch (error) {
      const code = (error as BusinessError).code;
      if (code === 16000001 || code === 16000019) {
        throw new Error('没有可接收任务文件的应用');
      }
      if (code === 16000018) {
        throw new Error('当前元服务暂时无法打开接收应用');
      }
      const message = error instanceof Error ? error.message : '分享启动失败';
      throw new Error(message);
    }
  }
}
