import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';

// 执行真实页面的状态方法；虚拟时钟不渲染ArkUI，也不代替设备操作。
const root = path.resolve(import.meta.dirname, '..');
const sourceArg = process.argv.indexOf('--source');
const sourceFile = sourceArg < 0 ?
  path.join(root, 'entry/src/main/ets/pages/WheelPage.ets') :
  path.resolve(process.argv[sourceArg + 1]);
const source = fs.readFileSync(sourceFile, 'utf8');
const buildIndex = source.indexOf('\n  build() {');
assert(buildIndex > 0, '未找到WheelPage的UI边界');
const stateSource = source.slice(0, buildIndex)
  .replace(/^import .+;\r?$/gm, '')
  .replace(/@(?:Entry|Component)\s*\r?\n/g, '')
  .replace(/@State\s+/g, '')
  .replace(/\bstruct WheelPage\b/, 'class WheelPage') +
  '\n}\nglobalThis.WheelPage = WheelPage;';
const sdk = process.env.DEVECO_SDK_HOME || 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk';
const ts = createRequire(import.meta.url)(path.join(sdk,
  'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const output = ts.transpileModule(stateSource, {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  reportDiagnostics: true,
  fileName: 'WheelPage-state.ts'
});
const errors = output.diagnostics.filter(item => item.category === ts.DiagnosticCategory.Error);
assert.equal(errors.length, 0, errors.map(item => ts.flattenDiagnosticMessageText(item.messageText, '\n')).join('\n'));

function createPage() {
  let now = 0;
  let nextId = 0;
  let backCalls = 0;
  const timers = new Map();
  const clock = {
    setTimeout(callback, delay) {
      const id = ++nextId;
      timers.set(id, { callback, at: now + delay });
      return id;
    },
    clearTimeout(id) { timers.delete(id); },
    advance(duration) {
      const until = now + duration;
      while (true) {
        const next = [...timers].filter(([, value]) => value.at <= until)
          .sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
        if (!next) break;
        timers.delete(next[0]);
        now = next[1].at;
        next[1].callback();
      }
      now = until;
    },
    get pending() { return timers.size; }
  };
  const context = {
    GameMode: { MIXED: 'mixed', TRUTH_ONLY: 'truth', DARE_ONLY: 'dare' },
    RiskLevel: { LIGHT: 'light', MEDIUM: 'medium', DEEP: 'deep' },
    TaskEngine: class { pickForWheel() { return []; } },
    setTimeout: clock.setTimeout,
    clearTimeout: clock.clearTimeout
  };
  vm.runInNewContext(output.outputText, context, { filename: sourceFile });
  const page = new context.WheelPage();
  page.getUIContext = () => ({ getRouter: () => ({ back() { backCalls++; } }) });
  page.currentTasks = [task('a'), task('b'), task('c')];
  return { page, clock, get backCalls() { return backCalls; } };
}

function task(id) {
  return { id, type: 'truth', level: 'light', text: id, tags: [], isCustom: false };
}

let passed = 0;
let failed = 0;
function test(name, run) {
  try {
    run();
    passed++;
    console.log(`PASS ${name}`);
  } catch (error) {
    failed++;
    console.error(`FAIL ${name}: ${error.message}`);
  }
}

test('double handoff completes one task and advances one participant', () => {
  const { page, clock } = createPage();
  page.onResult(task('a'));
  clock.advance(500);
  page.closeResult(true);
  page.closeResult(true);
  clock.advance(1000);
  assert.equal(page.turnNumber, 2);
  assert.equal(page.completedTaskIds.join(','), 'a');
  assert.equal(page.showResult, false);
  assert.equal(page.resultClosing, false);
});

test('ending twice returns once without advancing the round', () => {
  const state = createPage();
  state.page.onResult(task('a'));
  state.page.closeResult(false);
  state.page.closeResult(false);
  state.clock.advance(1000);
  assert.equal(state.backCalls, 1);
  assert.equal(state.page.turnNumber, 1);
  assert.equal(state.page.completedTaskIds.length, 0);
});

test('the first action wins when handoff and end are pressed together', () => {
  const state = createPage();
  state.page.onResult(task('a'));
  state.page.closeResult(true);
  state.page.closeResult(false);
  state.clock.advance(1000);
  assert.equal(state.page.turnNumber, 2);
  assert.equal(state.backCalls, 0);
});

test('last task keeps the existing finish-and-return behavior', () => {
  const state = createPage();
  state.page.currentTasks = [task('a'), task('b')];
  state.page.completedTaskIds = ['a'];
  state.page.turnNumber = 2;
  state.page.onResult(task('b'));
  assert.equal(state.page.isLastRemainingTask(), true);
  state.page.closeResult(!state.page.isLastRemainingTask());
  state.page.closeResult(!state.page.isLastRemainingTask());
  state.clock.advance(1000);
  assert.equal(state.backCalls, 1);
  assert.equal(state.page.turnNumber, 2);
  assert.equal(state.page.completedTaskIds.join(','), 'a');
});

test('leaving during close cancels delayed navigation and state changes', () => {
  const state = createPage();
  state.page.onResult(task('a'));
  state.page.closeResult(false);
  state.page.aboutToDisappear();
  state.clock.advance(1000);
  assert.equal(state.clock.pending, 0);
  assert.equal(state.backCalls, 0);
  assert.equal(state.page.showResult, false);
  assert.equal(state.page.resultTask, null);
});

test('leaving during entry cancels all result animation callbacks', () => {
  const { page, clock } = createPage();
  page.onResult(task('a'));
  page.aboutToDisappear();
  clock.advance(1000);
  assert.equal(clock.pending, 0);
  assert.equal(page.dialogOpacity, 0);
  assert.equal(page.showResult, false);
});

test('a new result replaces stale callbacks and resets the closing lock', () => {
  const { page, clock } = createPage();
  page.onResult(task('a'));
  page.closeResult(true);
  clock.advance(100);
  page.onResult(task('b'));
  clock.advance(1000);
  assert.equal(page.resultTask.id, 'b');
  assert.equal(page.showResult, true);
  assert.equal(page.turnNumber, 1);
  page.closeResult(true);
  clock.advance(1000);
  assert.equal(page.completedTaskIds.join(','), 'b');
  assert.equal(page.turnNumber, 2);
});

test('closing without an active result has no side effects', () => {
  const state = createPage();
  state.page.closeResult(false);
  state.clock.advance(1000);
  assert.equal(state.backCalls, 0);
  assert.equal(state.clock.pending, 0);
});

console.log(`${passed} passed; ${failed} failed; host state/timer regression only`);
if (failed) process.exitCode = 1;
