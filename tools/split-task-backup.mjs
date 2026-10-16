import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export const MAX_TASKS_PER_FILE = 1000;
export const MAX_FILE_BYTES = 1024 * 1024;
const FORMAT = 'adventure-wheel-tasks';

function serialize(tasks) {
  return JSON.stringify({ format: FORMAT, version: 1, tasks }, null, 2) + '\n';
}

// 只按原顺序分组，不删重、不修正文案，不改变任何任务字段。
export function splitTaskBackup(content) {
  const source = JSON.parse(content.replace(/^\uFEFF/, ''));
  if (!source || source.format !== FORMAT || source.version !== 1 || !Array.isArray(source.tasks)) {
    throw new Error('不是受支持的版本 1 自定义任务备份');
  }
  if (!source.tasks.length) throw new Error('备份中没有自定义任务');
  for (let index = 0; index < source.tasks.length; index++) {
    const task = source.tasks[index];
    if (!task || !['truth', 'dare'].includes(task.type) ||
        !['light', 'medium', 'deep'].includes(task.level) ||
        typeof task.text !== 'string' || !task.text.trim() ||
        Array.from(task.text.trim()).length > 30 || typeof task.enabled !== 'boolean') {
      throw new Error(`第 ${index + 1} 条任务不符合导入要求；未改动原文件`);
    }
  }
  const chunks = [];
  let current = [];
  for (const task of source.tasks) {
    const candidate = [...current, task];
    if (candidate.length > MAX_TASKS_PER_FILE || Buffer.byteLength(serialize(candidate)) > MAX_FILE_BYTES) {
      if (!current.length) throw new Error('单条记录超过文件大小限制；未改动原文件');
      chunks.push(serialize(current));
      current = [task];
      if (Buffer.byteLength(serialize(current)) > MAX_FILE_BYTES) {
        throw new Error('单条记录超过文件大小限制；未改动原文件');
      }
    } else {
      current = candidate;
    }
  }
  if (current.length) chunks.push(serialize(current));
  return { sourceTasks: source.tasks, files: chunks };
}

export function writeBackupParts(inputFile, outputDirectory) {
  const input = path.resolve(inputFile);
  const output = path.resolve(outputDirectory);
  if (fs.existsSync(output)) throw new Error('输出目录已存在；请选择新的空目录，避免覆盖');
  if (fs.statSync(input).size > 50 * 1024 * 1024) throw new Error('原文件超过工具的 50 MiB 安全读取上限');
  const result = splitTaskBackup(fs.readFileSync(input, 'utf8'));
  const parent = path.dirname(output);
  if (!fs.existsSync(parent)) throw new Error('输出目录的父目录不存在');
  const staging = path.join(parent, '.task-backup-' + randomUUID());
  fs.mkdirSync(staging);
  const created = [];
  try {
    result.files.forEach((text, index) => {
      const filename = `adventure-wheel-tasks-${String(index + 1).padStart(3, '0')}.json`;
      const destination = path.join(staging, filename);
      fs.writeFileSync(destination, text, { flag: 'wx', encoding: 'utf8' });
      created.push(destination);
    });
    const restored = created.flatMap(filename => JSON.parse(fs.readFileSync(filename, 'utf8')).tasks);
    if (JSON.stringify(restored) !== JSON.stringify(result.sourceTasks)) throw new Error('拆分内容核对不一致');
    if (fs.existsSync(output)) throw new Error('输出目录在操作期间被创建；未覆盖');
    fs.renameSync(staging, output);
  } catch (error) {
    // 仅清理本函数在随机暂存目录里创建的文件，不递归处理用户目录。
    for (const filename of created) if (fs.existsSync(filename)) fs.unlinkSync(filename);
    if (fs.existsSync(staging)) fs.rmdirSync(staging);
    throw error;
  }
  return { tasks: result.sourceTasks.length, files: result.files.length, output };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    if (process.argv.length !== 4) throw new Error('用法：node tools/split-task-backup.mjs "原备份.json或txt" "新的输出目录"');
    const result = writeBackupParts(process.argv[2], process.argv[3]);
    console.log(`已核对 ${result.tasks} 条，生成 ${result.files} 份；原文件未改动。`);
    console.log(`输出：${result.output}`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
