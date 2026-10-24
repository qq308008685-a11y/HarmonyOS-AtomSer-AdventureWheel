import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';

// 主机回归执行当前 ETS 控制方法。系统存储、路由和时钟为受控替身；不证明设备渲染已验。
const projectRoot = path.resolve(import.meta.dirname, '..');
const sourceRoot = path.resolve(process.env.LIFECYCLE_SOURCE_ROOT || projectRoot);
const nativeRequire = createRequire(import.meta.url);
const sdkRoot = process.env.DEVECO_SDK_HOME || 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk';
const ts = nativeRequire(path.join(sdkRoot,
  'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const setupFile = 'entry/src/main/ets/pages/SetupPage.ets';
const canvasFile = 'entry/src/main/ets/components/WheelCanvas.ets';
const quietConsole = { error() {}, log() {} };
const tick = () => new Promise(resolve => setImmediate(resolve));
const settle = async () => { for (let n = 0; n < 4; n++) await tick(); };
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
};

class Clock {
  now = 0;
  next = 0;
  timers = new Map();
  add(fn, delay, repeat = false) {
    const id = ++this.next;
    this.timers.set(id, { fn, due: this.now + delay, delay, repeat });
    return id;
  }
  advance(milliseconds) {
    const end = this.now + milliseconds;
    let turns = 0;
    while (true) {
      const first = [...this.timers].filter(([, item]) => item.due <= end)
        .sort((a, b) => a[1].due - b[1].due || a[0] - b[0])[0];
      if (!first) break;
      assert.ok(++turns < 10000, '虚拟时钟回调未收敛');
      const [id, item] = first;
      this.now = item.due;
      if (item.repeat) item.due += item.delay;
      else this.timers.delete(id);
      item.fn();
    }
    this.now = end;
  }
}

function fixture() {
  const cache = new Map();
  const clock = new Clock();
  const stores = new Map();
  const initCalls = new Map();
  const faults = { init: 0 };
  const sound = { ticks: 0, stops: 0 };
  function load(relative) {
    const absolute = path.resolve(sourceRoot, relative);
    if (cache.has(absolute)) return cache.get(absolute).exports;
    let source = fs.readFileSync(absolute, 'utf8').replace(/\r\n?/g, '\n');
    if (relative === setupFile) {
      const boundary = source.indexOf('\n  @Builder');
      assert.ok(boundary > 0, '找不到首页控制方法边界');
      source = source.slice(0, boundary).replace(/^@(Entry|Component)\s*$/gm, '')
        .replace(/@State\s+/g, '').replace('struct SetupPage', 'class SetupPage') +
        '\n}\nexport { SetupPage };';
    } else if (relative === canvasFile) {
      const start = source.indexOf('\n  build() {');
      const end = source.indexOf('\n  private drawWheel()', start);
      assert.ok(start > 0 && end > start, '找不到Canvas构建方法边界');
      source = (source.slice(0, start) + source.slice(end))
        .replace(/@Watch\('[^']+'\)\s*/g, '').replace(/@(?:Component|Prop|State)\s*/g, '')
        .replace('export struct WheelCanvas', 'export class WheelCanvas');
    }
    const compiled = ts.transpileModule(source, { compilerOptions: {
      target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS, esModuleInterop: true
    }, fileName: absolute, reportDiagnostics: true });
    assert.equal((compiled.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error).length,
      0, 'ETS控制方法转换失败');
    const module = { exports: {} };
    cache.set(absolute, module);
    function localRequire(request) {
      if (request === '@ohos.data.preferences') return { getPreferences: async (_context, name) => {
        initCalls.set(name, (initCalls.get(name) || 0) + 1);
        if (name === 'adventure_wheel_local_tasks' && faults.init > 0) {
          faults.init--; throw new Error('模拟初始化失败');
        }
        if (!stores.has(name)) stores.set(name, new Map());
        const values = stores.get(name);
        return { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
          put: async (key, value) => { values.set(key, value); }, flush: async () => {} };
      } };
      if (request.endsWith('/SoundEngine')) return { SoundEngine: {
        playTick() { sound.ticks++; }, playStop() { sound.stops++; }
      } };
      if (request.endsWith('/ModeSelector') || request.endsWith('/TaskCountSlider')) return {};
      if (!request.startsWith('.')) return nativeRequire(request);
      return load(path.relative(sourceRoot, path.resolve(path.dirname(absolute), request + '.ets')).replaceAll('\\', '/'));
    }
    class FakeDate extends Date { static now() { return clock.now; } }
    const wrapper = vm.runInNewContext('(function(exports, require, module) {' + compiled.outputText + '\n})', {
      console: quietConsole, Date: FakeDate,
      setTimeout: (fn, delay) => clock.add(fn, delay), clearTimeout: id => clock.timers.delete(id),
      setInterval: (fn, delay) => clock.add(fn, delay, true), clearInterval: id => clock.timers.delete(id),
      RenderingContextSettings: class {}, CanvasRenderingContext2D: class {}
    }, { filename: absolute });
    wrapper(module.exports, localRequire, module);
    return module.exports;
  }
  const { SetupPage } = load(setupFile);
  const { WheelCanvas } = load(canvasFile);
  const { LocalTaskStore } = load('entry/src/main/ets/store/LocalTaskStore.ets');
  const { GameMode } = load('entry/src/main/ets/model/GameConfig.ets');
  const { RiskLevel } = load('entry/src/main/ets/model/TaskItem.ets');
  const { Constants } = load('entry/src/main/ets/common/Constants.ets');
  const page = new SetupPage();
  page.getUIContext = () => ({ getHostContext: () => ({}),
    getRouter: () => ({ pushUrl: async () => {}, back() {} }) });
  const wheel = new WheelCanvas();
  wheel.tasks = [{ id: 'truth-test', type: 'truth', level: 'light', text: '生命周期测试' }];
  let draws = 0;
  const results = [];
  wheel.drawWheel = () => { draws++; };
  wheel.onResult = task => results.push(task.id);
  return { page, wheel, store: LocalTaskStore, clock, stores, initCalls, faults,
    GameMode, RiskLevel, Constants, results, draws: () => draws };
}

const tests = [];
async function test(name, fn) {
  try { await fn(); tests.push({ name, status: 'pass' }); console.log('PASS ' + name); }
  catch (error) { tests.push({ name, status: 'fail', error: error.message }); console.error('FAIL ' + name + ': ' + error.message); }
}
async function show(page) { page.onPageShow(); await settle(); }
async function returnTo(page) { page.onPageHide(); await show(page); }

await test('首次显示初始化并读取任务统计', async () => {
  const { page, initCalls } = fixture(); await show(page);
  assert.equal(page.customTaskCount, 0); assert.equal(page.enabledTaskCount, 0);
  assert.equal(initCalls.get('adventure_wheel_prefs'), 1);
  assert.equal(initCalls.get('adventure_wheel_local_tasks'), 1);
});
await test('新增返回刷新统计且不重置未保存的玩法选择', async () => {
  const { page, store, GameMode, RiskLevel } = fixture(); await show(page);
  page.mode = GameMode.DARE_ONLY; page.taskCount = 10; page.riskLevel = RiskLevel.DEEP;
  await store.add('truth', 'light', '新增测试任务'); await returnTo(page);
  assert.equal(page.customTaskCount, 1); assert.equal(page.enabledTaskCount, 1);
  assert.equal(page.mode, GameMode.DARE_ONLY); assert.equal(page.taskCount, 10);
  assert.equal(page.riskLevel, RiskLevel.DEEP);
});
await test('启停删除后每次返回均反映真实数量', async () => {
  const { page, store } = fixture(); await show(page);
  const a = await store.add('truth', 'light', '启停测试甲');
  const b = await store.add('dare', 'light', '启停测试乙'); await returnTo(page);
  assert.equal(page.customTaskCount, 2); assert.equal(page.enabledTaskCount, 2);
  await store.setEnabled(a.id, false); await returnTo(page);
  assert.equal(page.customTaskCount, 2); assert.equal(page.enabledTaskCount, 1);
  await store.setEnabled(a.id, true); await returnTo(page);
  assert.equal(page.enabledTaskCount, 2);
  await store.remove(b.id); await returnTo(page);
  assert.equal(page.customTaskCount, 1); assert.equal(page.enabledTaskCount, 1);
});
await test('重叠显示共享首次初始化而不重复打开存储', async () => {
  const { page, initCalls } = fixture(); page.onPageShow(); page.onPageShow(); await settle();
  assert.equal(initCalls.get('adventure_wheel_prefs'), 1);
  assert.equal(initCalls.get('adventure_wheel_local_tasks'), 1);
  assert.equal(page.setupStatusText, '');
});
await test('首次存储初始化失败后再次显示可以恢复', async () => {
  const { page, faults, initCalls, store } = fixture(); faults.init = 1; await show(page);
  assert.ok(page.setupStatusText.includes('读取失败'));
  await show(page); await store.add('truth', 'light', '恢复测试'); await returnTo(page);
  assert.equal(initCalls.get('adventure_wheel_local_tasks'), 2);
  assert.equal(page.customTaskCount, 1); assert.equal(page.setupStatusText, '');
});
await test('统计读取失败保留已有数量并在重试成功后清除自身错误', async () => {
  const { page, store } = fixture(); await show(page); await store.add('truth', 'light', '读取测试'); await returnTo(page);
  const list = store.list; store.list = async () => { throw new Error('模拟读取失败'); };
  await returnTo(page); assert.equal(page.customTaskCount, 1); assert.ok(page.setupStatusText.includes('读取失败'));
  store.list = list; await returnTo(page); assert.equal(page.customTaskCount, 1); assert.equal(page.setupStatusText, '');
});
await test('较早读取晚完成不能覆盖新页面显示的统计', async () => {
  const { page, store } = fixture(); await show(page); const older = deferred();
  store.list = () => older.promise; const pending = page.loadLocalState(); await settle();
  store.list = async () => [{ enabled: true }, { enabled: false }]; await page.loadLocalState();
  older.resolve([]); await pending;
  assert.equal(page.customTaskCount, 2); assert.equal(page.enabledTaskCount, 1);
});
await test('页面隐藏后旧读取结果和旧错误均不回写', async () => {
  for (const fail of [false, true]) {
    const { page, store } = fixture(); await show(page); const older = deferred();
    store.list = () => older.promise; const pending = page.loadLocalState(); await settle();
    page.onPageHide(); page.customTaskCount = 7; page.enabledTaskCount = 6;
    if (fail) older.reject(new Error('模拟隐藏后失败')); else older.resolve([]);
    await pending; assert.equal(page.customTaskCount, 7); assert.equal(page.enabledTaskCount, 6);
    assert.equal(page.setupStatusText, '');
  }
});
await test('成功刷新统计不清除其他操作的错误', async () => {
  const { page } = fixture(); await show(page); page.setupStatusText = '暂时无法进入转盘，请重试';
  await returnTo(page); assert.equal(page.setupStatusText, '暂时无法进入转盘，请重试');
});
await test('正常停转回弹与结果按时各执行一次并释放timer', () => {
  const { wheel, clock, Constants, results, draws } = fixture(); wheel.stopSpin();
  assert.equal(clock.timers.size, 2); assert.equal(wheel.pointerOffsetY, 6);
  clock.advance(120); assert.equal(wheel.pointerOffsetY, 0); assert.equal(wheel.reboundTimer, -1);
  assert.equal(draws(), 2); assert.equal(results.length, 0);
  clock.advance(Constants.RESULT_REVEAL_DELAY - 120);
  assert.equal(results.length, 1); assert.equal(results[0], 'truth-test');
  assert.equal(wheel.resultTimer, -1); assert.equal(clock.timers.size, 0);
});
for (const method of ['aboutToDisappear', 'onTasksChange', 'onRoundChange', 'onCompletedTasksChange']) {
  await test(method + '取消停转后的全部延迟回调', () => {
    const { wheel, clock, results, draws } = fixture(); wheel.stopSpin(); wheel[method]();
    const afterReset = draws(); assert.equal(clock.timers.size, 0);
    clock.advance(10000); assert.equal(draws(), afterReset); assert.equal(results.length, 0);
    assert.equal(wheel.isSpinning, false); assert.equal(wheel.isSettling, false);
    assert.equal(wheel.pointerOffsetY, 0);
  });
}
await test('旋转中退出取消动画interval并复位状态', () => {
  const { wheel, clock, draws, results } = fixture(); wheel.startSpin();
  assert.equal(clock.timers.size, 1); assert.equal(wheel.isSpinning, true);
  clock.advance(16); wheel.aboutToDisappear(); const before = draws();
  assert.equal(clock.timers.size, 0); clock.advance(10000);
  assert.equal(draws(), before); assert.equal(results.length, 0); assert.equal(wheel.isSpinning, false);
});
await test('新旋转清除旧回弹和结果只保留本轮interval', () => {
  const { wheel, clock, results } = fixture(); wheel.stopSpin(); wheel.isSettling = false;
  wheel.startSpin(); assert.equal(clock.timers.size, 1);
  clock.advance(600); assert.equal(results.length, 0);
  wheel.aboutToDisappear(); assert.equal(clock.timers.size, 0);
});
await test('重置后新一轮可正常揭晓且旧结果不会插入', () => {
  const { wheel, clock, Constants, results } = fixture(); wheel.stopSpin(); wheel.onRoundChange();
  wheel.startSpin(); wheel.stopSpin(); clock.advance(Constants.RESULT_REVEAL_DELAY);
  assert.equal(results.length, 1); assert.equal(clock.timers.size, 0);
});
await test('重复停止不会累计回弹或重复结果', () => {
  const { wheel, clock, Constants, results } = fixture(); wheel.stopSpin(); wheel.stopSpin();
  assert.equal(clock.timers.size, 2); clock.advance(Constants.RESULT_REVEAL_DELAY);
  assert.equal(results.length, 1); assert.equal(clock.timers.size, 0);
});

const sourceHashes = Object.fromEntries([setupFile, canvasFile].map(name => [name,
  createHash('sha256').update(fs.readFileSync(path.join(sourceRoot, name))).digest('hex')]));
const report = { kind: 'host-page-lifecycle-regression', sourceHashes,
  passed: tests.filter(item => item.status === 'pass').length, total: tests.length, tests,
  limits: ['执行真实ETS控制方法；移除不执行的ArkUI构建语法，系统存储、路由和时钟为替身。',
    '不渲染ArkUI或Canvas，不证明设备路由、真实Preferences、动画视觉或重启恢复已经通过。'] };
console.log(JSON.stringify(report, null, 2));
if (report.passed !== report.total) process.exitCode = 1;
