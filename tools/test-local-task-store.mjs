import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';

// 主机回归：运行当前 ETS 存储和页面控制方法；Preferences、系统弹框和文件入口使用故障替身。
// 不渲染 ArkUI，不证明设备 Preferences、文件送达或重启恢复已经通过。
const root = path.resolve(import.meta.dirname, '..');
const nativeRequire = createRequire(import.meta.url);
const sdkRoot = process.env.DEVECO_SDK_HOME || 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk';
const ts = nativeRequire(path.join(sdkRoot, 'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const storeFile = path.join(root, 'entry/src/main/ets/store/LocalTaskStore.ets');
const pageFile = path.join(root, 'entry/src/main/ets/pages/TaskLibraryPage.ets');
const tick = () => new Promise(resolve => setImmediate(resolve));
const record = (id, text = id, enabled = true) => ({
  id, text, type: 'truth', level: 'light', enabled, createdAt: 1, updatedAt: 1
});

class MemoryPreferences {
  constructor(records = []) {
    this.raw = JSON.stringify(records);
    this.durableRaw = this.raw;
    this.failGet = 0;
    this.failPut = 0;
    this.failFlush = 0;
    this.blockFlush = false;
    this.failInit = 0;
  }
  async get() {
    await tick();
    if (this.failGet > 0) { this.failGet--; throw new Error('模拟读取失败'); }
    return this.raw;
  }
  async put(_key, value) {
    await tick();
    if (this.failPut > 0) { this.failPut--; throw new Error('模拟写入失败'); }
    this.raw = value;
  }
  async flush() {
    await tick();
    if (this.blockFlush) { throw new Error('模拟持续落盘失败'); }
    if (this.failFlush > 0) { this.failFlush--; throw new Error('模拟落盘失败'); }
    this.durableRaw = this.raw;
  }
}

function fixture(initial = []) {
  const backend = new MemoryPreferences(initial);
  const cache = new Map();
  const transfers = {
    selectImport: async () => ({ validTasks: [record('import', '导入任务')], validCount: 1,
      duplicateCount: 0, invalidCount: 0 }),
    exportTasks: async (_context, records) => records.length,
    shareTasks: async () => 1
  };
  const quietConsole = { error() {}, log() {} };
  function load(filename) {
    const absolute = path.resolve(filename);
    if (cache.has(absolute)) return cache.get(absolute).exports;
    let source = fs.readFileSync(absolute, 'utf8');
    if (absolute === pageFile) {
      // 保留原文件的字段和全部控制方法，去掉本测试不执行的 ArkUI 构建语法。
      const boundary = source.indexOf('  @Builder\n');
      assert.ok(boundary > 0, '页面控制方法边界不存在');
      source = source.slice(0, boundary).replace(/^@(Entry|Component)\s*$/gm, '')
        .replace('struct TaskLibraryPage', 'class TaskLibraryPage').replace(/@State /g, '') +
        '\n}\nexport { TaskLibraryPage };';
    }
    const compiled = ts.transpileModule(source, { compilerOptions: {
      module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true
    }, fileName: absolute, reportDiagnostics: true });
    assert.equal((compiled.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error).length,
      0, `源码转换失败：${path.basename(absolute)}`);
    const module = { exports: {} };
    cache.set(absolute, module);
    const localRequire = request => {
      if (request === '@ohos.data.preferences') return { getPreferences: async () => {
        if (backend.failInit > 0) { backend.failInit--; throw new Error('模拟初始化失败'); }
        return backend;
      } };
      if (request.endsWith('/TaskTransferService')) return { TaskTransferService: transfers };
      if (!request.startsWith('.')) return nativeRequire(request);
      return load(path.resolve(path.dirname(absolute), request + '.ets'));
    };
    const wrapper = vm.runInNewContext('(function(exports, require, module) {' + compiled.outputText + '\n})',
      { console: quietConsole, setTimeout, clearTimeout }, { filename: absolute });
    wrapper(module.exports, localRequire, module);
    return module.exports;
  }
  const { LocalTaskStore: store } = load(storeFile);
  const { TaskLibraryPage: Page } = load(pageFile);
  const page = new Page();
  const dialog = { index: 1, error: null };
  page.getUIContext = () => ({ getHostContext: () => ({}), getPromptAction: () => ({
    showDialog: async () => { await tick(); if (dialog.error) throw dialog.error; return { index: dialog.index }; }
  }) });
  return { backend, store, page, dialog, transfers };
}

const results = [];
const unhandled = [];
process.on('unhandledRejection', error => unhandled.push(String(error)));
async function test(name, fn) {
  try { await fn(); results.push({ name, status: 'pass' }); console.log(`PASS ${name}`); }
  catch (error) { results.push({ name, status: 'fail', error: error.message }); console.error(`FAIL ${name}: ${error.message}`); }
}

await test('并发新增全部保留并落盘', async () => {
  const { store, backend } = fixture(); await store.init({});
  await Promise.all(Array.from({ length: 12 }, (_, n) => store.add('truth', 'light', `并发任务${n}`)));
  assert.equal((await store.list()).length, 12);
  assert.equal(JSON.parse(backend.durableRaw).length, 12);
});
await test('并发新增编辑启停删除合并不会整数组覆盖', async () => {
  const { store } = fixture([record('a'), record('b'), record('c')]); await store.init({});
  await Promise.all([store.add('truth', 'light', '新增'), store.setEnabled('a', false),
    store.remove('b'), store.mergeImported([record('import')]), store.update(record('c', '编辑后'))]);
  const tasks = await store.list();
  assert.equal(tasks.length, 4);
  assert.equal(tasks.find(task => task.id === 'a').enabled, false);
  assert.equal(tasks.find(task => task.id === 'c').text, '编辑后');
  assert.ok(!tasks.some(task => task.id === 'b'));
  assert.ok(tasks.some(task => task.id === 'import'));
});
await test('读取按请求顺序等待前一写入', async () => {
  const { store } = fixture(); await store.init({});
  const first = store.add('truth', 'light', '甲'); const snapshot = store.list();
  const second = store.add('truth', 'light', '乙');
  await first; assert.equal((await snapshot).length, 1); await second;
  assert.equal((await store.list()).length, 2);
});
await test('并发同类型空白大小写重复在写事务内拒绝', async () => {
  const { store } = fixture(); await store.init({});
  const settled = await Promise.allSettled([store.add('truth', 'light', 'Hello World'),
    store.add('truth', 'light', 'hello world')]);
  assert.equal(settled.filter(item => item.status === 'fulfilled').length, 1);
  await store.add('dare', 'light', 'HELLO WORLD'); assert.equal((await store.list()).length, 2);
});
await test('编辑去重失败不会改变旧记录且队列继续', async () => {
  const { store } = fixture([record('a', '甲'), record('b', '乙')]); await store.init({});
  await assert.rejects(store.update(record('b', '甲')), /相同任务/);
  await store.setEnabled('a', false);
  assert.equal((await store.list()).find(task => task.id === 'b').text, '乙');
});
await test('未初始化读写拒绝而不伪装空库或成功', async () => {
  const { store } = fixture(); await assert.rejects(store.list(), /读取失败/);
  await assert.rejects(store.add('truth', 'light', '未初始化'), /读取失败/);
  await store.init({}); await store.add('truth', 'light', '初始化后'); assert.equal((await store.list()).length, 1);
});
await test('初始化失败后可重试且不毒化队尾', async () => {
  const { store, backend } = fixture(); backend.failInit = 1;
  await assert.rejects(store.init({}), /初始化失败/); await store.init({}); assert.equal((await store.list()).length, 0);
});
await test('读取失败不会以空数组覆盖现有数据', async () => {
  const { store, backend } = fixture([record('old')]); await store.init({}); backend.failGet = 1;
  await assert.rejects(store.add('truth', 'light', '第一次失败'), /读取失败/);
  await store.add('truth', 'light', '稍后成功'); assert.equal((await store.list()).length, 2);
});
await test('损坏JSON拒绝读写并保留原文', async () => {
  const { store, backend } = fixture(); await store.init({}); backend.raw = '{broken';
  await assert.rejects(store.list(), /读取失败/);
  await assert.rejects(store.add('truth', 'light', '不应覆盖'), /读取失败/); assert.equal(backend.raw, '{broken');
});
await test('put失败后原数据保留且下一个操作可执行', async () => {
  const { store, backend } = fixture([record('old')]); await store.init({}); backend.failPut = 1;
  await assert.rejects(store.add('truth', 'light', '失败项'), /写入失败/);
  await store.add('truth', 'light', '成功项'); const tasks = await store.list();
  assert.equal(tasks.length, 2); assert.ok(!tasks.some(task => task.text === '失败项'));
});
await test('flush失败恢复缓存原值，同一内容可以重试', async () => {
  const { store, backend } = fixture([record('old')]); await store.init({}); backend.failFlush = 1;
  await assert.rejects(store.add('truth', 'light', '重试项'), /写入失败/);
  assert.equal(JSON.parse(backend.raw).length, 1); assert.equal(JSON.parse(backend.durableRaw).length, 1);
  await store.add('truth', 'light', '重试项'); assert.equal((await store.list()).length, 2);
});
await test('回滚也失败时后续操作先恢复而不保存失败候选', async () => {
  const { store, backend } = fixture([record('old')]); await store.init({}); backend.failFlush = 2;
  await assert.rejects(store.add('truth', 'light', '失败候选'), /写入失败/);
  await store.add('truth', 'light', '恢复后'); const tasks = await store.list();
  assert.equal(tasks.length, 2); assert.ok(!tasks.some(task => task.text === '失败候选'));
});
await test('持续落盘故障阻止后续写入，恢复后队列可用', async () => {
  const { store, backend } = fixture([record('old')]); await store.init({}); backend.blockFlush = true;
  await assert.rejects(store.add('truth', 'light', '失败候选'), /写入失败/);
  await assert.rejects(store.add('truth', 'light', '故障中'), /读取失败/);
  backend.blockFlush = false; await store.add('truth', 'light', '恢复后'); assert.equal((await store.list()).length, 2);
});
await test('页面读取错误可见且重试后解除操作限制', async () => {
  const { page, backend } = fixture([record('old')]); backend.failGet = 1;
  await page.refreshLocalTasks(); assert.ok(page.localLoadFailed); assert.equal(page.localReady, false);
  assert.match(page.statusText, /重试读取/); assert.equal(page.isBusy, false);
  await page.refreshLocalTasks(); assert.ok(page.localReady); assert.equal(page.localTasks.length, 1);
});
await test('保存忙态阻止重复保存和重开编辑，成功才关闭', async () => {
  const { page, store } = fixture(); await page.refreshLocalTasks(); page.openCreateEditor(); page.editorText = '单击一次';
  const saving = page.saveEditor(); assert.ok(page.isBusy); page.openCreateEditor();
  assert.equal(page.editorText, '单击一次'); await page.saveEditor(); await saving;
  assert.equal((await store.list()).length, 1); assert.equal(page.isBusy, false); assert.equal(page.editorVisible, false);
});
await test('保存失败保留编辑正文与开关并允许直接重试', async () => {
  const { page, backend, store } = fixture(); await page.refreshLocalTasks(); page.openCreateEditor();
  page.editorText = '保存后重试'; page.editorEnabled = false; backend.failFlush = 1;
  await page.saveEditor(); assert.ok(page.editorVisible); assert.equal(page.editorText, '保存后重试');
  assert.equal(page.editorEnabled, false); assert.match(page.statusText, /保存未完成/); assert.equal(page.isBusy, false);
  await page.saveEditor(); assert.equal((await store.list()).length, 1); assert.equal(page.editorVisible, false);
});
await test('页面编辑重复错误可见且编辑内容不丢失', async () => {
  const { page } = fixture([record('a', '甲'), record('b', '乙')]); await page.refreshLocalTasks();
  page.openEditEditor(page.localTasks.find(task => task.id === 'b')); page.editorText = '甲';
  await page.saveEditor(); assert.ok(page.editorVisible); assert.equal(page.editorId, 'b');
  assert.match(page.statusText, /相同任务/); assert.equal(page.isBusy, false);
});
await test('删除确认后的异步失败被等待并显示', async () => {
  const { page, backend, store } = fixture([record('a')]); await page.refreshLocalTasks(); backend.failFlush = 1;
  await page.requestDelete(page.localTasks[0]); assert.match(page.statusText, /删除未完成/);
  assert.equal(page.isBusy, false); assert.equal((await store.list()).length, 1);
});
await test('删除取消及确认框失败都不写数据并释放忙态', async () => {
  const { page, dialog, store } = fixture([record('a')]); await page.refreshLocalTasks(); dialog.index = 0;
  await page.requestDelete(page.localTasks[0]); assert.equal((await store.list()).length, 1);
  dialog.error = new Error('确认框失败'); await page.requestDelete(page.localTasks[0]);
  assert.match(page.statusText, /删除未完成/); assert.equal(page.isBusy, false);
});
await test('启停失败保留原状态并显示可重试错误', async () => {
  const { page, backend, store } = fixture([record('a')]); await page.refreshLocalTasks(); backend.failPut = 1;
  await page.toggleTask(page.localTasks[0], false); assert.match(page.statusText, /启停未完成/);
  assert.equal(page.localTasks[0].enabled, true); assert.equal(page.isBusy, false);
  await page.toggleTask(page.localTasks[0], false); assert.equal((await store.list())[0].enabled, false);
});
await test('导入确认后的合并失败回到外层提示并可重试', async () => {
  const { page, backend, store } = fixture(); await page.refreshLocalTasks(); backend.failFlush = 1;
  await page.importTasks(); assert.match(page.statusText, /导入未完成/); assert.equal(page.isBusy, false);
  await page.importTasks(); assert.match(page.statusText, /已导入 1/); assert.equal((await store.list()).length, 1);
});
await test('导入取消不写入任务且解除忙态', async () => {
  const { page, dialog, store } = fixture(); await page.refreshLocalTasks(); dialog.index = 0;
  await page.importTasks(); assert.equal((await store.list()).length, 0); assert.equal(page.isBusy, false);
});
await test('写成功但刷新失败不会误报保存失败或重复写入', async () => {
  const { page, store } = fixture(); await page.refreshLocalTasks(); page.openCreateEditor(); page.editorText = '已成功保存';
  const originalList = store.list; let fail = true;
  store.list = async () => { if (fail) { fail = false; throw new Error('刷新失败'); } return originalList.call(store); };
  await page.saveEditor(); assert.equal(page.editorVisible, false); assert.equal(page.localReady, false);
  assert.match(page.statusText, /任务已保存.*刷新失败/); assert.equal(page.isBusy, false);
  await page.refreshLocalTasks(); assert.equal(page.localTasks.length, 1);
});
await test('导出和分享失败都显示错误且解除忙态', async () => {
  const { page, transfers } = fixture([record('a')]); await page.refreshLocalTasks();
  transfers.exportTasks = async () => { throw new Error('导出失败'); };
  await page.exportTasks(); assert.match(page.statusText, /导出未完成/); assert.equal(page.isBusy, false);
  transfers.shareTasks = async () => { throw new Error('分享失败'); };
  await page.shareTasks(); assert.match(page.statusText, /分享未完成/); assert.equal(page.isBusy, false);
});
await tick();
await test('所有控制链没有悬空的未处理拒绝', async () => assert.equal(unhandled.length, 0));

const report = {
  kind: 'host-regression-only', total: results.length,
  passed: results.filter(item => item.status === 'pass').length,
  failed: results.filter(item => item.status === 'fail').length,
  source: [storeFile, pageFile].map(file => ({ path: path.relative(root, file).replaceAll('\\', '/'),
    sha256: createHash('sha256').update(fs.readFileSync(file)).digest('hex') })),
  limits: ['Preferences 使用内存与故障替身；不是设备落盘或掉电原子性验证。',
    '页面只运行当前控制方法；ArkUI控件、系统选择器和重启恢复须在设备另验。'], results
};
const reportIndex = process.argv.indexOf('--report');
if (reportIndex >= 0) {
  assert.ok(process.argv[reportIndex + 1], '--report 需要目标路径');
  const reportFile = path.resolve(root, process.argv[reportIndex + 1]);
  assert.ok(reportFile.startsWith(path.join(root, '.local') + path.sep), '报告只写入本工程 .local/');
  fs.writeFileSync(reportFile, JSON.stringify(report, null, 2) + '\n');
}
console.log(`LOCAL TASK REGRESSION ${report.passed}/${report.total} PASSED; ${report.failed} FAILED`);
if (report.failed) process.exitCode = 1;
