import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { splitTaskBackup, writeBackupParts, MAX_FILE_BYTES } from './split-task-backup.mjs';

const make = count => ({ format: 'adventure-wheel-tasks', version: 1,
  tasks: Array.from({ length: count }, (_, i) => ({ type: 'dare', level: 'light', text: `测试任务${i}`, enabled: i % 2 === 0 })) });
let passed = 0;
function test(name, fn) { fn(); passed++; console.log('PASS ' + name); }
test('1000 tasks fit one file', () => assert.equal(splitTaskBackup(JSON.stringify(make(1000))).files.length, 1));
test('1001 tasks split to 1000 and 1 without changes', () => {
  const source = make(1001), result = splitTaskBackup(JSON.stringify(source));
  assert.deepEqual(result.files.map(s => JSON.parse(s).tasks.length), [1000, 1]);
  assert.deepEqual(result.files.flatMap(s => JSON.parse(s).tasks), source.tasks);
  result.files.forEach(s => assert(Buffer.byteLength(s) <= MAX_FILE_BYTES));
});
test('byte limit is respected before count limit', () => {
  const source = make(12); source.tasks.forEach(t => { t.extra = '字'.repeat(50000); });
  const result = splitTaskBackup(JSON.stringify(source));
  assert(result.files.length > 1);
  result.files.forEach(s => assert(Buffer.byteLength(s) <= MAX_FILE_BYTES));
  assert.deepEqual(result.files.flatMap(s => JSON.parse(s).tasks), source.tasks);
});
test('TXT JSON and BOM are accepted', () => assert.equal(splitTaskBackup('\uFEFF' + JSON.stringify(make(2))).sourceTasks.length, 2));
test('bad JSON is rejected', () => assert.throws(() => splitTaskBackup('{')));
test('unknown version is rejected', () => assert.throws(() => splitTaskBackup(JSON.stringify({ ...make(1), version: 2 }))));
test('empty tasks are rejected', () => assert.throws(() => splitTaskBackup(JSON.stringify(make(0)))));
test('invalid or long text is rejected without filtering', () => {
  const source = make(2); source.tasks[1].text = '长'.repeat(31);
  assert.throws(() => splitTaskBackup(JSON.stringify(source)), /第 2 条/);
});
const parent = path.resolve(import.meta.dirname, '../.local/案例刷新-20261015');
fs.mkdirSync(parent, { recursive: true });
const temp = fs.mkdtempSync(path.join(parent, '拆分测试-'));
try {
  const input = path.join(temp, 'original.txt'), output = path.join(temp, 'parts');
  const bytes = Buffer.from(JSON.stringify(make(1001)));
  fs.writeFileSync(input, bytes, { flag: 'wx' });
  test('files are created and original bytes preserved', () => {
    const result = writeBackupParts(input, output);
    assert.equal(result.files, 2); assert.equal(result.tasks, 1001);
    assert(fs.readFileSync(input).equals(bytes));
    assert.deepEqual(fs.readdirSync(output), ['adventure-wheel-tasks-001.json', 'adventure-wheel-tasks-002.json']);
  });
  test('existing output is never overwritten', () => {
    assert.throws(() => writeBackupParts(input, output), /已存在/);
    assert(fs.readFileSync(input).equals(bytes));
  });
} finally {
  // 清理本测试创建的明确文件，不递归删除目录。
  const output = path.join(temp, 'parts');
  for (const name of ['adventure-wheel-tasks-001.json', 'adventure-wheel-tasks-002.json']) {
    const file = path.join(output, name); if (fs.existsSync(file)) fs.unlinkSync(file);
  }
  if (fs.existsSync(output)) fs.rmdirSync(output);
  fs.unlinkSync(path.join(temp, 'original.txt')); fs.rmdirSync(temp);
}
console.log(`ALL ${passed} BACKUP SPLIT TESTS PASSED`);
