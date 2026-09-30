import path from 'node:path';
import { execFileSync } from 'node:child_process';

// 检查 Git 暂存区中的真实内容，避免只检查工作目录而漏掉旧凭据。
// 诊断只输出文件名、规则和行号，不输出可能含有凭据的原文。
const projectRoot = path.resolve(import.meta.dirname, '..');
const problems = [];
const contents = new Map();
const roots = ['AppScope/', 'entry/', 'hvigor/', 'tools/', 'docs/', 'cases/'];
const rootFiles = new Set([
  '.gitignore', 'README.md', 'LICENSE', 'NOTICE.md', 'build-profile.json5',
  'code-linter.json5', 'hvigorfile.ts', 'oh-package.json5', 'oh-package-lock.json5'
]);
const excludedRoots = [
  '.local/', 'signing/', '.arts/', '.codeartsdoer/', '.codegraph/', '.codex/', '.agents/',
  'build-artifacts/', 'brand-assets/', 'specs/', '测试用户邀请/', '正式版本/'
];
const excludedFiles = new Set([
  'local.properties', 'agconnect-services.json', '.merkle-snapshot.json', 'requirement.md', 'tech-spec.md'
]);
const contentRules = [
  ['private-key', /-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----/],
  ['credential-field', /"(?:storePassword|keyPassword|password|app_?secret|client_secret|private_key|access_token|secretAccessKey|apiKey)"\s*:\s*"[^"\s]+"/i],
  ['credential-assignment', /\b(?:AK|SK|AppSecret|API_KEY|ACCESS_TOKEN)\s*=\s*['"][^'"]+['"]/],
  ['developer-absolute-path', /[A-Z]:[\\/](?:Users|用户|myHarmonyOSproj|HarmonySigning|华为云开发者)[\\/]/i],
  ['private-invitation-link', /hoas\.drcn\.agconnect\.link/i]
];

function git(args, encoding = 'utf8') {
  return execFileSync('git', args, { cwd: projectRoot, encoding, maxBuffer: 32 * 1024 * 1024 });
}

const entries = git(['ls-files', '--stage', '-z']).split('\0').filter(Boolean).map(line => {
  const match = /^(\d+) ([a-f0-9]+) (\d+)\t([\s\S]+)$/.exec(line);
  if (!match) throw new Error('Cannot parse Git index entry');
  return { mode: match[1], objectId: match[2], stage: Number(match[3]), file: match[4] };
});

for (const entry of entries) {
  const { file } = entry;
  if (entry.stage !== 0 || entry.mode === '160000') {
    problems.push({ file, rule: 'unresolved-index-or-submodule' });
    continue;
  }
  if (excludedRoots.some(root => file.startsWith(root)) || excludedFiles.has(file) ||
      /(?:^|\/)(?:node_modules|oh_modules|build|\.hvigor|\.idea|\.appanalyzer)(?:\/|$)/.test(file) ||
      /\.(?:p12|p7b|jks|keystore|cer|pem|key|hap|hsp|app)$/i.test(file) ||
      /(?:^|\/)\.env(?:\.|$)/.test(file) && path.basename(file) !== '.env.example') {
    problems.push({ file, rule: 'excluded-local-or-secret-file' });
  }
  if (!rootFiles.has(file) && !roots.some(root => file.startsWith(root))) {
    problems.push({ file, rule: 'unexpected-public-file' });
  }
  const buffer = git(['cat-file', 'blob', entry.objectId], null);
  if (/\.(?:png|jpe?g|webp)$/i.test(file)) {
    continue; // 图片在发布准备时另行进行视觉检查。
  }
  if (buffer.includes(0)) {
    problems.push({ file, rule: 'unexpected-binary-file' });
    continue;
  }
  const text = buffer.toString('utf8');
  contents.set(file, text);
  text.split(/\r?\n/).forEach((line, index) => {
    for (const [rule, expression] of contentRules) {
      if (expression.test(line)) problems.push({ file, rule, line: index + 1 });
    }
  });
}

for (const file of ['.gitignore', 'README.md', 'LICENSE', 'NOTICE.md', 'build-profile.json5',
  'entry/src/main/module.json5', 'AppScope/app.json5', 'tools/run-logic-tests.mjs']) {
  if (!contents.has(file)) problems.push({ file, rule: 'missing-required-file' });
}

if (contents.has('build-profile.json5')) {
  const profile = JSON.parse(contents.get('build-profile.json5'));
  if ((profile.app.signingConfigs || []).length > 0 ||
      profile.app.products.some(product => Object.hasOwn(product, 'signingConfig'))) {
    problems.push({ file: 'build-profile.json5', rule: 'private-signing-reference' });
  }
  const product = profile.app.products.find(item => item.name === 'default');
  if (!product || product.targetSdkVersion !== '6.1.0(23)' ||
      product.compatibleSdkVersion !== '6.0.0(20)') {
    problems.push({ file: 'build-profile.json5', rule: 'changed-target-or-minimum-api' });
  }
}

const license = contents.get('LICENSE') || '';
if (!license.includes('Apache License') || !license.includes('Version 2.0, January 2004')) {
  problems.push({ file: 'LICENSE', rule: 'missing-apache-2-license-text' });
}

const indexedFiles = new Set(entries.map(entry => entry.file));
let checkedLinks = 0;
for (const [file, text] of contents) {
  if (!/\.(?:md|html)$/.test(file)) continue;
  const targets = file.endsWith('.html') ?
    [...text.matchAll(/(?:src|href)="([^"]+)"/g)].map(match => match[1]) : [
    ...[...text.matchAll(/\[[^\]\n]*\]\(([^)]+)\)/g)].map(match => match[1]),
    ...[...text.matchAll(/<img\s+[^>]*src="([^"]+)"[^>]*>/g)].map(match => match[1])
  ];
  for (const target of targets) {
    if (/^(?:https?:|#)/.test(target)) continue;
    checkedLinks++;
    const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(file),
      decodeURIComponent(target.split('#')[0])));
    if (!indexedFiles.has(resolved)) problems.push({ file, rule: 'unstaged-document-link', target });
  }
}

if (contents.has('cases/case.json')) {
  const data = JSON.parse(contents.get('cases/case.json'));
  const paths = [data.baseInfo.coverImage, data.baseInfo.cardImage, data.baseInfo.shareImage,
    data.architecture.archImage, data.practice.content,
    ...data.preview.devices.map(device => device.previewImage)].filter(Boolean);
  for (const target of paths) {
    checkedLinks++;
    if (!/^[a-z0-9][a-z0-9._-]*$/.test(target) || !indexedFiles.has(`cases/${target}`)) {
      problems.push({ file: 'cases/case.json', rule: 'unsafe-or-unstaged-case-reference', target });
    }
  }
}

console.log(JSON.stringify({ stagedFiles: entries.length, checkedLocalLinks: checkedLinks,
  problems, status: problems.length === 0 ? 'PASS' : 'FAIL' }, null, 2));
if (problems.length > 0) process.exitCode = 1;
