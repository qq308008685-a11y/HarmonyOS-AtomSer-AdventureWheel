import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';

const projectRoot = path.resolve(import.meta.dirname, '..');
const sdkRoot = process.env.DEVECO_SDK_HOME || 'C:\\Program Files\\Huawei\\DevEco Studio\\sdk';
const typescriptPath = path.join(sdkRoot, 'default', 'openharmony', 'ets', 'build-tools', 'ets-loader',
  'node_modules', 'typescript');
const nativeRequire = createRequire(import.meta.url);
const ts = nativeRequire(typescriptPath);
const moduleCache = new Map();

function resolveModule(request, parentFile) {
  if (!request.startsWith('.')) {
    return nativeRequire(request);
  }
  const base = path.resolve(path.dirname(parentFile), request);
  for (const candidate of [base, `${base}.ets`, `${base}.ts`, `${base}.js`]) {
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
      return candidate;
    }
  }
  throw new Error(`Cannot resolve ${request} from ${parentFile}`);
}

function loadEts(filename) {
  const absolute = path.resolve(filename);
  if (moduleCache.has(absolute)) {
    return moduleCache.get(absolute).exports;
  }
  const source = fs.readFileSync(absolute, 'utf8');
  const output = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020,
      esModuleInterop: true
    },
    fileName: absolute
  }).outputText;
  const module = { exports: {} };
  moduleCache.set(absolute, module);
  const localRequire = (request) => {
    const resolved = resolveModule(request, absolute);
    return typeof resolved === 'string' ? loadEts(resolved) : resolved;
  };
  const wrapper = new vm.Script(`(function(exports, require, module, __filename, __dirname) {${output}\n})`, {
    filename: absolute
  }).runInThisContext();
  wrapper(module.exports, localRequire, module, absolute, path.dirname(absolute));
  return module.exports;
}

let passed = 0;
function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`PASS ${name}`);
  } catch (error) {
    console.error(`FAIL ${name}: ${error.message}`);
    process.exitCode = 1;
  }
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function expectThrow(fn) {
  let thrown = false;
  try {
    fn();
  } catch (_) {
    thrown = true;
  }
  assert(thrown, 'expected function to throw');
}

const validatorModule = loadEts(path.join(projectRoot,
  'entry/src/main/ets/service/TaskTransferValidator.ets'));
const taskItemModule = loadEts(path.join(projectRoot, 'entry/src/main/ets/model/TaskItem.ets'));
const engineModule = loadEts(path.join(projectRoot, 'entry/src/main/ets/engine/TaskEngine.ets'));
const gameConfigModule = loadEts(path.join(projectRoot, 'entry/src/main/ets/model/GameConfig.ets'));
const taskSourceModule = loadEts(path.join(projectRoot, 'entry/src/main/ets/data/task-source.ets'));
const taskTextRulesModule = loadEts(path.join(projectRoot, 'entry/src/main/ets/service/TaskTextRules.ets'));
const transferPackageBuilderModule = loadEts(path.join(projectRoot,
  'entry/src/main/ets/service/TaskTransferPackageBuilder.ets'));
const wheelRoundStateModule = loadEts(path.join(projectRoot,
  'entry/src/main/ets/engine/WheelRoundState.ets'));

const { TaskTransferValidator } = validatorModule;
const { TaskType, RiskLevel } = taskItemModule;
const { TaskEngine } = engineModule;
const { GameMode } = gameConfigModule;
const { getAllBuiltInTasks } = taskSourceModule;
const { TaskTextRules } = taskTextRulesModule;
const { TaskTransferPackageBuilder } = transferPackageBuilderModule;
const { WheelRoundState } = wheelRoundStateModule;

function packageText(tasks, version = 1) {
  return JSON.stringify({ format: 'adventure-wheel-tasks', version, tasks });
}

function transferTask(text, type = TaskType.TRUTH, level = RiskLevel.LIGHT, enabled = true) {
  return { text, type, level, enabled };
}

function customTask(id, type = TaskType.TRUTH, level = RiskLevel.LIGHT) {
  return { id, type, level, text: id, tags: ['自定义'], isCustom: true };
}

test('validator accepts valid v1 package', () => {
  const result = TaskTransferValidator.parse(packageText([transferTask('测试任务')]), []);
  assert(result.validCount === 1 && result.invalidCount === 0, 'valid task was not accepted');
});

test('task transfer package keeps only portable task fields', () => {
  const local = [
    {
      id: 'local-1', type: TaskType.TRUTH, level: RiskLevel.LIGHT, text: '分享测试', enabled: true,
      createdAt: 10, updatedAt: 20
    },
    {
      id: 'local-2', type: TaskType.DARE, level: RiskLevel.DEEP, text: '关闭的挑战', enabled: false,
      createdAt: 30, updatedAt: 40
    }
  ];
  const serialized = TaskTransferPackageBuilder.stringify(local);
  const data = JSON.parse(serialized);
  assert(data.format === 'adventure-wheel-tasks' && data.version === 1, 'package metadata is incorrect');
  assert(data.tasks.length === 2 && data.tasks[0].text === '分享测试', 'portable task was not serialized');
  const imported = TaskTransferValidator.parse(serialized, []);
  assert(imported.validCount === 2 && imported.validTasks[1].type === TaskType.DARE &&
    imported.validTasks[1].level === RiskLevel.DEEP && !imported.validTasks[1].enabled,
    'portable task fields did not survive a round trip');
  assert(!serialized.includes('local-1') && !serialized.includes('createdAt') && !serialized.includes('updatedAt'),
    'local-only fields leaked into transfer package');
});

test('validator rejects broken JSON', () => {
  expectThrow(() => TaskTransferValidator.parse('{broken', []));
});

test('validator rejects unknown version', () => {
  expectThrow(() => TaskTransferValidator.parse(packageText([], 2), []));
});

test('validator skips local and in-file duplicates', () => {
  const existing = [{ id: '1', type: TaskType.TRUTH, level: RiskLevel.LIGHT, text: '相 同任务',
    enabled: true, createdAt: 1, updatedAt: 1 }];
  const result = TaskTransferValidator.parse(packageText([
    transferTask('相同 任务'),
    transferTask('新增任务'),
    transferTask('新 增任务')
  ]), existing);
  assert(result.validCount === 1 && result.duplicateCount === 2, 'duplicate statistics are incorrect');
});

test('validator reports invalid mixed records', () => {
  const invalid = { text: '', type: TaskType.TRUTH, level: RiskLevel.LIGHT, enabled: true };
  const result = TaskTransferValidator.parse(packageText([transferTask('有效任务'), invalid]), []);
  assert(result.validCount === 1 && result.invalidCount === 1, 'invalid statistics are incorrect');
});

test('custom task text keeps a thirty character limit', () => {
  const valid = '一'.repeat(30);
  const invalid = '一'.repeat(31);
  assert(TaskTextRules.isValid(valid), 'thirty characters should be accepted');
  assert(!TaskTextRules.isValid(invalid), 'thirty-one characters should be rejected');
  assert(TaskTextRules.count(TaskTextRules.limit(invalid)) === 30, 'input limit should keep thirty characters');
});

test('import validator rejects custom task text over thirty characters', () => {
  const result = TaskTransferValidator.parse(packageText([transferTask('一'.repeat(31))]), []);
  assert(result.validCount === 0 && result.invalidCount === 1, 'overlong imported task was not rejected');
});

test('engine returns requested count without custom tasks', () => {
  const result = new TaskEngine().pickForWheel({
    mode: GameMode.MIXED, taskCount: 6, riskFilter: RiskLevel.MEDIUM, customTasks: [], wheelTasks: []
  });
  assert(result.length === 6 && result.every(task => !task.isCustom), 'built-in selection failed');
});

test('engine caps custom tasks at fifty percent', () => {
  const customTasks = Array.from({ length: 8 }, (_, index) => customTask(`custom-${index}`));
  const result = new TaskEngine().pickForWheel({
    mode: GameMode.MIXED, taskCount: 6, riskFilter: RiskLevel.MEDIUM, customTasks, wheelTasks: []
  });
  assert(result.filter(task => task.isCustom).length === 3, 'custom ratio cap failed');
});

test('engine filters custom tasks by mode and risk', () => {
  const customTasks = [
    customTask('truth-light', TaskType.TRUTH, RiskLevel.LIGHT),
    customTask('dare-light', TaskType.DARE, RiskLevel.LIGHT),
    customTask('truth-deep', TaskType.TRUTH, RiskLevel.DEEP)
  ];
  const result = new TaskEngine().pickForWheel({
    mode: GameMode.TRUTH_ONLY, taskCount: 4, riskFilter: RiskLevel.LIGHT, customTasks, wheelTasks: []
  });
  const selected = result.filter(task => task.isCustom);
  assert(selected.length === 1 && selected[0].id === 'truth-light', 'mode or risk filtering failed');
});

test('engine randomizes custom selection before capping', () => {
  const customTasks = Array.from({ length: 8 }, (_, index) => customTask(`random-${index}`));
  const selectedIds = new Set();
  for (let index = 0; index < 24; index++) {
    const result = new TaskEngine().pickForWheel({
      mode: GameMode.MIXED, taskCount: 4, riskFilter: RiskLevel.MEDIUM, customTasks, wheelTasks: []
    });
    result.filter(task => task.isCustom).forEach(task => selectedIds.add(task.id));
  }
  assert(selectedIds.size > 2, 'custom selection appears fixed to the first records');
});

test('wheel round excludes completed tasks from available indices', () => {
  const tasks = [customTask('one'), customTask('two'), customTask('three')];
  const indices = WheelRoundState.availableIndices(tasks, ['two']);
  assert(indices.length === 2 && indices[0] === 0 && indices[1] === 2,
    'completed task remains available');
});

test('wheel round never picks a completed task', () => {
  const tasks = [customTask('one'), customTask('two'), customTask('three')];
  const completed = ['two'];
  [0, 0.25, 0.5, 0.999].forEach(value => {
    const selected = WheelRoundState.pickAvailableIndex(tasks, completed, value);
    assert(selected !== 1, `completed index was selected for random value ${value}`);
  });
});

test('wheel round reports no target after every task is completed', () => {
  const tasks = [customTask('one'), customTask('two')];
  assert(WheelRoundState.pickAvailableIndex(tasks, ['one', 'two'], 0.5) === -1,
    'all-completed round should not return a target');
});

test('built-in task library keeps expected size and unique ids', () => {
  const tasks = getAllBuiltInTasks();
  const ids = new Set(tasks.map(task => task.id));
  assert(tasks.length === 190, `expected 190 built-in tasks, got ${tasks.length}`);
  assert(ids.size === tasks.length, 'built-in task ids are not unique');
});

test('built-in dares avoid outsiders, dangerous actions, privacy exposure and irreversible operations', () => {
  const forbidden = /陌生服务员|不在场|发朋友圈|发到群|给一个群聊发|打电话|拨一个|翻看你的|私密笔记|删掉一个|倒立|平板支撑|背你走|通知音量调到最大|遗言/;
  const unsafe = getAllBuiltInTasks()
    .filter(task => task.type === TaskType.DARE && forbidden.test(task.text));
  assert(unsafe.length === 0, `unsafe built-in dares remain: ${unsafe.map(task => task.id).join(', ')}`);
});

if (!process.exitCode) {
  console.log(`ALL ${passed} LOGIC TESTS PASSED`);
}
