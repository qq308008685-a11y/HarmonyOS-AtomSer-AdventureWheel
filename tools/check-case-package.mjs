import fs from 'node:fs';
import path from 'node:path';

// 补充生成器原版检查：卡片、SVG、HTML、路径、富文本和待补仓库地址。
const caseDir = path.resolve(import.meta.dirname, '../cases');
const errors = [];
const blockers = [];
const media = [];
const fail = (condition, rule) => { if (!condition) errors.push(rule); };
const raw = fs.readFileSync(path.join(caseDir, 'case.json'));
fail(!(raw[0] === 0xef && raw[1] === 0xbb && raw[2] === 0xbf), 'case-json-no-bom');
fail(raw.length <= 1024 * 1024, 'case-json-max-1MiB');
const data = JSON.parse(raw.toString('utf8'));
for (const name of ['baseInfo', 'introduction', 'prerequisites', 'knowledgePoints', 'practice',
  'architecture', 'preview', 'faqs', 'scenarios', 'challenges']) {
  fail(data[name] && typeof data[name] === 'object', `missing-module:${name}`);
}
const base = data.baseInfo;
const deliverables = data.introduction.deliverables;
fail(deliverables && typeof deliverables === 'object' && !Array.isArray(deliverables) &&
  Array.isArray(deliverables.items) && deliverables.items.length > 0 &&
  deliverables.items.every(item => typeof item === 'string' && item.trim().length > 0),
  'introduction-deliverables-populated');
fail(!/<[a-zA-Z/][^>]*>/.test(data.architecture.description || ''), 'architecture-description-plain-text');
if (!base.repoUrl) blockers.push('baseInfo.repoUrl is empty; public repository and actual import remain unverified');
else fail(/^https:\/\/[^\s]+$/.test(base.repoUrl), 'repository-must-use-https');
for (const key of ['caseId', 'updateTime', 'practiceCount', 'status', 'createdBy']) {
  fail(!Object.hasOwn(data, key) && !Object.hasOwn(base, key), `system-field:${key}`);
}
for (const [key, max] of [['title', 200], ['description', 500], ['author', 100], ['category', 50]]) {
  fail(typeof base[key] === 'string' && [...base[key]].length >= 1 && [...base[key]].length <= max,
    `base-length:${key}`);
}
fail(['入门', '进阶', '高级'].includes(base.difficulty), 'base-difficulty');
fail(Number.isInteger(base.duration) && base.duration >= 1 && base.duration <= 100000, 'base-duration');
const icons = new Set(('Printer Calendar CreditCard Box Money Refrigerator Cpu Football Brush Suitcase SuitcaseLine Umbrella AlarmClock Medal GoldMedal Present Mouse Watch QuartzWatch Magnet Help Soccer ToiletPaper ReadingLamp Paperclip MagicStick Basketball Baseball Coin Goods Sell SoldOut Key ShoppingCart ShoppingCartFull ShoppingTrolley Phone Scissor Handbag ShoppingBag Trophy TrophyBase Stopwatch Timer CollectionTag TakeawayBox PriceTag Wallet').split(' '));
for (const item of [...data.introduction.highlights, ...data.prerequisites.cloud,
  ...data.prerequisites.local, ...data.scenarios.list]) {
  fail(!item.icon || icons.has(item.icon), `icon:${item.icon}`);
}
for (const group of ['cloud', 'local']) {
  fail(data.prerequisites[group].length === 4, `four-prerequisites:${group}`);
  for (const item of data.prerequisites[group]) {
    fail(['必须', '可选', '建议', '免费'].includes(item.status), `prerequisite-status:${item.title}`);
  }
}
for (const name of ['knowledgePoints', 'faqs', 'scenarios', 'challenges']) {
  fail(Array.isArray(data[name].list) && !Object.hasOwn(data[name], 'items'), `list-alias:${name}`);
}
for (const kp of data.knowledgePoints.list) {
  fail(!Object.hasOwn(kp, 'keywords'), `unknown-keywords-field:${kp.title}`);
  fail(['核心', '重要', '了解'].includes(kp.importance), `importance:${kp.title}`);
  const words = kp.subtitle.split(' / ');
  fail(words.length >= 3 && words.length <= 5 && !/[、,，→]/.test(kp.subtitle), `subtitle-tags:${kp.title}`);
  fail(/^<p>[\s\S]*?：<\/p><ul>[\s\S]*?<li><strong>[\s\S]+?<\/strong>/.test(kp.content), `knowledge-rich-text:${kp.title}`);
}
for (const item of data.challenges.list) {
  fail(['简单', '中等', '困难'].includes(item.difficulty), `challenge-difficulty:${item.title}`);
  fail(item.skills === undefined || Array.isArray(item.skills) &&
    item.skills.every(skill => typeof skill === 'string' && skill.trim().length > 0),
    `challenge-skills:${item.title}`);
}

function localFile(file) {
  if (typeof file !== 'string' || !/^[a-z0-9][a-z0-9._-]*$/.test(file)) {
    errors.push(`unsafe-or-nonlocal-reference:${file}`);
    return null;
  }
  const resolved = path.resolve(caseDir, file);
  if (path.dirname(resolved) !== caseDir || !fs.existsSync(resolved)) {
    errors.push(`missing-file:${file}`);
    return null;
  }
  fail(fs.statSync(resolved).size <= 20 * 1024 * 1024, `media-max-20MiB:${file}`);
  return resolved;
}
function png(file, width, height) {
  const resolved = localFile(file);
  if (!resolved) return;
  const bytes = fs.readFileSync(resolved);
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  fail(bytes.length >= 33 && bytes.subarray(0, 8).equals(signature), `actual-png:${file}`);
  const size = [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
  fail(size[0] === width && size[1] === height, `image-size:${file}`);
  fail(bytes.length <= 500 * 1024, `image-max-500KiB:${file}`);
  media.push({ file, width: size[0], height: size[1], bytes: bytes.length });
}
png(base.coverImage, 2080, 960);
png(base.cardImage, 1920, 974);
png(base.shareImage, 1200, 1200);
const names = { phone: '手机', tablet: '平板', foldable: '双折叠展开态', wearable: '智能穿戴' };
fail(data.preview.devices.length === 1, 'current-case-only-one-phone-preview');
for (const device of data.preview.devices) {
  fail(names[device.deviceType] === device.deviceName && device.deviceType === 'phone', 'device-type-and-name');
  png(device.previewImage, 2080, 1100);
}
const svgFile = localFile(data.architecture.archImage);
if (svgFile) {
  const svg = fs.readFileSync(svgFile, 'utf8');
  fail(/<svg[^>]*width="2080"[^>]*height="820"[^>]*viewBox="0 0 2080 820"/.test(svg), 'svg-root-dimensions');
  fail(!/<script|<foreignObject|(?:href|src)\s*=\s*["']https?:/i.test(svg), 'svg-no-active-or-external-content');
  media.push({ file: data.architecture.archImage, width: 2080, height: 820, bytes: Buffer.byteLength(svg) });
}
const htmlFile = localFile(data.practice.content);
if (htmlFile) {
  const html = fs.readFileSync(htmlFile, 'utf8');
  fail(!/<script|<iframe|\bon\w+\s*=|javascript:|file:\/\//i.test(html), 'practice-no-active-or-local-machine-content');
  const decode = value => value.replace(/&(amp|lt|gt|quot|#39);/g,
    (_, key) => ({ amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'" })[key]);
  const start = html.indexOf('<h2 id="4-完整实践"');
  const end = html.indexOf('<h2 id="5-功能检查与排障"');
  fail(start >= 0 && end > start, 'complete-practice-section-present');
  const segment = html.slice(start, end);
  fail((segment.match(/<h3\b[^>]*>步骤 \d：/g) || []).length === 8, 'eight-practice-steps');
  const plain = decode(segment.replace(/<[^>]*>/g, ''));
  for (const label of ['目标：', '复制给 AI：', '完成标志：']) {
    fail(plain.split(label).length - 1 === 8, `practice-step-label:${label}`);
  }
  fail(html.includes('云端快速体验') && html.includes('本地快速体验') && html.includes('案例仓地址留空'),
    'practice-two-experience-paths-and-empty-project');
  const readme = fs.readFileSync(path.resolve(caseDir, '../README.md'), 'utf8').replace(/\r/g, '');
  const sourceBlocks = [...readme.matchAll(/^```([^\n]*)\n([\s\S]*?)^```\s*$/gm)]
    .filter(match => match[1].trim() !== 'mermaid').map(match => match[2].replace(/\n$/, ''));
  const htmlBlocks = [...html.matchAll(/<pre\b[^>]*><code\b[^>]*>([\s\S]*?)<\/code><\/pre>/g)]
    .map(match => decode(match[1]));
  fail(sourceBlocks.length > 0 && sourceBlocks.every((block, index) => block === htmlBlocks[index]),
    'readme-practice-every-text-block-exact');
}
console.log(JSON.stringify({ status: errors.length ? 'FAIL' : blockers.length ? 'DRAFT' : 'LOCAL_PASS',
  errors, blockers, knowledgePoints: data.knowledgePoints.list.length, media }, null, 2));
if (errors.length || blockers.length) process.exitCode = 1;
