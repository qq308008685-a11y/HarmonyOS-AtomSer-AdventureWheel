import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const decodeHtml = value => value.replace(/&(?:#x([0-9a-f]+)|#([0-9]+)|(amp|lt|gt|quot|apos|#39));/gi,
  (entity, hex, decimal, name) => hex || decimal
    ? String.fromCodePoint(parseInt(hex || decimal, hex ? 16 : 10))
    : ({ amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", '#39': "'" })[name.toLowerCase()]);
const headingText = value => value.trim().replace(/^\d+\s*[.、．]\s*/, '')
  .replace(/^(快速体验|完整实践)\s*[（(]\s*(?:约|预计)?\s*\d+(?:\.\d+)?(?:\s*[-–—~～至]\s*\d+(?:\.\d+)?)?\s*(?:分钟|小时|min|h)\s*[）)]$/, '$1');

// 只提取真实标题和 pre/code 块；注释、代码示例中的 h2 不参与结构判断。
function readTutorial(html) {
  const headings = [];
  const blocks = [];
  let preDepth = 0;
  let codeDepth = 0;
  let suppressed = '';
  let heading = null;
  let block = null;
  for (const match of html.matchAll(/<!--[\s\S]*?-->|<![^>]*>|<\/?[a-z][^>]*>|[^<]+|</gi)) {
    const token = match[0];
    if (token.startsWith('<!--') || token.startsWith('<!')) continue;
    const tag = token.match(/^<(\/)?([a-z][a-z0-9:-]*)\b[^>]*>/i);
    if (!tag) {
      if (!suppressed && heading) heading.text += token;
      continue;
    }
    const closing = Boolean(tag[1]);
    const name = tag[2].toLowerCase();
    if (suppressed) { if (closing && name === suppressed) suppressed = ''; continue; }
    if (!closing && ['script', 'style', 'textarea'].includes(name) && !preDepth && !codeDepth) {
      suppressed = name; continue;
    }
    if (name === 'pre') {
      preDepth += closing ? -1 : 1;
      preDepth = Math.max(0, preDepth);
      continue;
    }
    if (name === 'code') {
      if (!closing && preDepth && !codeDepth) block = { index: match.index, start: match.index + token.length };
      if (closing && block && codeDepth === 1) {
        blocks.push({ index: block.index, text: decodeHtml(html.slice(block.start, match.index)) });
        block = null;
      }
      codeDepth = Math.max(0, codeDepth + (closing ? -1 : 1));
      continue;
    }
    if (!preDepth && !codeDepth && ['h2', 'h3'].includes(name)) {
      if (!closing) heading = { level: Number(name[1]), text: '', index: match.index };
      else if (heading && heading.level === Number(name[1])) {
        headings.push({ ...heading, text: headingText(decodeHtml(heading.text)) });
        heading = null;
      }
    }
  }
  return { headings, blocks };
}

// 用实际 Markdown 标题归属定位教学块，不能把目录树或注释里的伪标题算进来。
function readReadmeBlocks(markdown) {
  const blocks = [];
  let h2 = '';
  let h3 = '';
  let fence = null;
  let comment = false;
  const headings = [];
  for (let line of markdown.replace(/\r\n?/g, '\n').split('\n')) {
    if (fence) {
      if (new RegExp(`^\\s{0,3}${fence.char}{${fence.length},}\\s*$`).test(line)) {
        if (fence.language !== 'mermaid') blocks.push({ h2, h3, text: fence.lines.join('\n') });
        fence = null;
      } else fence.lines.push(line);
      continue;
    }
    // HTML 注释允许跨行；围栏内容保持原字节，不把其中的注释当 Markdown 注释。
    let visible = '';
    while (line.length) {
      const index = line.indexOf(comment ? '-->' : '<!--');
      if (index < 0) { if (!comment) visible += line; break; }
      if (!comment) visible += line.slice(0, index);
      line = line.slice(index + (comment ? 3 : 4));
      comment = !comment;
    }
    const opening = visible.match(/^\s{0,3}(`{3,}|~{3,})(.*)$/);
    if (opening) {
      fence = { char: opening[1][0], length: opening[1].length,
        language: opening[2].trim().toLowerCase(), lines: [] };
      continue;
    }
    const title = visible.match(/^\s{0,3}(#{2,3})\s+(.+?)\s*#*\s*$/);
    if (title) {
      if (title[1].length === 2) { h2 = headingText(title[2]); h3 = ''; headings.push(h2); }
      else h3 = headingText(title[2]);
    }
  }
  return { blocks, headings };
}

export function checkPracticeTutorial(html, readme, caseForm = 'case_form_practice') {
  const errors = [];
  const fail = (condition, rule) => { if (!condition) errors.push(rule); };
  const tutorial = readTutorial(html.replace(/\r\n?/g, '\n'));
  const h2 = tutorial.headings.filter(item => item.level === 2);
  const names = h2.map(item => item.text);
  if (caseForm === 'case_form_app_template') {
    fail(names.includes('快速体验'), 'quick-experience-section-present');
    fail(!names.includes('完整实践'), 'template-without-complete-practice');
    return { errors, headings: names, blocksBySection: [] };
  }
  const contract = ['快速体验', '完整实践', '功能检查与排障', '安全与清理', '进阶实践'];
  fail(names.length === contract.length && names.every((name, index) =>
    name === contract[index] || index === 2 && name === '高频问题排查'), 'ordinary-practice-five-sections-in-order');
  fail(!tutorial.blocks.some(block => !h2.length || block.index < h2[0].index), 'practice-no-unmapped-preface-blocks');
  const sources = readReadmeBlocks(readme);
  const mappings = contract.map((name, index) => ({ name,
    source: index === 4 ? '项目导览与进阶' : name, subsection: index === 4 ? '深入阅读与扩展' : null }));
  const blocksBySection = [];
  for (const [index, mapping] of mappings.entries()) {
    const sourceCount = sources.headings.filter(name => name === mapping.source).length;
    fail(sourceCount === 1, `readme-source-section-unique:${mapping.source}`);
    const expected = sources.blocks.filter(block => block.h2 === mapping.source &&
      (!mapping.subsection || block.h3 === mapping.subsection)).map(block => block.text);
    const section = h2[index];
    const end = h2[index + 1]?.index ?? html.length;
    const actual = section ? tutorial.blocks.filter(block => block.index > section.index && block.index < end)
      .map(block => block.text) : [];
    fail(expected.length > 0 && actual.length === expected.length &&
      expected.every((block, blockIndex) => block === actual[blockIndex]), `readme-practice-section-blocks-exact:${mapping.name}`);
    blocksBySection.push({ section: mapping.name, sourceBlocks: expected.length, practiceBlocks: actual.length });
  }
  const full = h2[1];
  const end = h2[2]?.index ?? html.length;
  const steps = full ? tutorial.headings.filter(item => item.level === 3 && item.index > full.index &&
    item.index < end && /^步骤\s+\d+：/.test(item.text)) : [];
  fail(steps.length > 0, 'practice-steps-present');
  for (const [index, step] of steps.entries()) {
    const end = steps[index + 1]?.index ?? h2[2]?.index ?? html.length;
    const segment = decodeHtml(html.slice(step.index, end).replace(/<!--[\s\S]*?-->/g, '').replace(/<[^>]*>/g, ''));
    for (const label of ['目标：', '复制给 AI：', '完成标志：']) {
      fail(segment.split(label).length - 1 === 1, `practice-step-label:${index + 1}:${label}`);
    }
  }
  fail(html.includes('云端快速体验') && html.includes('本地快速体验') && html.includes('案例仓地址留空'),
    'practice-two-experience-paths-and-empty-project');
  return { errors, headings: names, blocksBySection, practiceSteps: steps.length };
}

// 本仓库的补充检查，不替代上游 V-1 至 V-13、语义审阅或真实平台验收。
// 五类图片的尺寸/本地文件是本地发布规范；上游选填字段不因此变为通用必填。
export function checkCasePackage(caseDir = path.resolve(import.meta.dirname, '../cases')) {
  caseDir = path.resolve(caseDir);
  const errors = [];
  const blockers = [];
  const media = [];
  const warnings = [];
  const result = () => ({ status: errors.length ? 'FAIL' : blockers.length ? 'DRAFT' : 'LOCAL_PASS',
    scope: 'local-package-supplement-only', errors, blockers, warnings, media });
  const fail = (condition, rule) => { if (!condition) errors.push(rule); };
  const raw = fs.readFileSync(path.join(caseDir, 'case.json'));
  fail(!(raw[0] === 0xef && raw[1] === 0xbb && raw[2] === 0xbf), 'case-json-no-bom');
  fail(raw.length <= 1024 * 1024, 'case-json-max-1MiB');
  let data;
  try { data = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(raw)); }
  catch { errors.push('case-json-valid-utf8-and-json'); return result(); }
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    errors.push('case-json-object'); return result();
  }
  for (const name of ['baseInfo', 'introduction', 'prerequisites', 'knowledgePoints', 'practice',
    'architecture', 'preview', 'faqs']) {
    fail(data[name] && typeof data[name] === 'object' && !Array.isArray(data[name]), `missing-module:${name}`);
  }
  if (errors.length) return result();
  for (const name of ['scenarios', 'challenges']) {
    fail(data[name] === undefined || data[name] && typeof data[name] === 'object' && !Array.isArray(data[name]),
      `optional-module:${name}`);
  }
  const base = data.baseInfo;
  const deliverables = data.introduction.deliverables;
  if (base.caseForm === 'case_form_practice') {
    fail(deliverables && typeof deliverables === 'object' && !Array.isArray(deliverables) &&
      Array.isArray(deliverables.items) && deliverables.items.length > 0 &&
      deliverables.items.every(item => typeof item === 'string' && item.trim().length > 0),
      'introduction-deliverables-populated');
  } else if (base.caseForm === 'case_form_app_template') {
    fail(deliverables && deliverables.title === '' && deliverables.intro === '' &&
      Array.isArray(deliverables.items) && deliverables.items.length === 0, 'template-deliverables-empty');
  }
  for (const [name, value] of [['introduction.overview', data.introduction.overview],
    ['introduction.targetAudience', data.introduction.targetAudience],
    ['architecture.description', data.architecture.description]]) {
    fail(value === undefined || value === '' || typeof value === 'string' && /<[a-zA-Z][^>]*>/.test(value),
      `html-rich-text:${name}`);
  }
  if (!base.repoUrl) blockers.push('baseInfo.repoUrl is empty; public repository and actual import remain unverified');
  else fail(/^https:\/\/[^\s]+$/.test(base.repoUrl), 'repository-must-use-https');
  for (const key of ['caseId', 'updateTime', 'practiceCount', 'status', 'createdBy']) {
    fail(!Object.hasOwn(data, key) && !Object.hasOwn(base, key), `system-field:${key}`);
  }
  for (const [key, max] of [['title', 200], ['description', 500], ['author', 100], ['category', 50]]) {
    fail(typeof base[key] === 'string' && [...base[key]].length >= 1 && [...base[key]].length <= max,
      `base-length:${key}`);
  }
  fail(typeof base.difficulty === 'string' && base.difficulty.trim().length > 0, 'base-difficulty-name');
  fail(Number.isFinite(base.duration) && base.duration >= 1 && base.duration <= 100000, 'base-duration');
  for (const [key, values] of [['caseForm', ['case_form_practice', 'case_form_app_template']],
    ['appForm', ['app_form_app', 'app_form_atomic']]]) {
    fail(base[key] === undefined || base[key] === '' || values.includes(base[key]), `base-code:${key}`);
  }
  const categories = new Set('life travel social shopping education sports game finance catering medical government estate business tools'
    .split(' ').map(value => `industry_${value}`));
  fail(categories.has(base.category), 'category-industry-code');
  fail(base.tags === undefined || Array.isArray(base.tags) && base.tags.every(tag => typeof tag === 'string'), 'base-tags-array');
  const icons = new Set(('Printer Calendar CreditCard Box Money Refrigerator Cpu Football Brush Suitcase SuitcaseLine Umbrella AlarmClock Medal GoldMedal Present Mouse Watch QuartzWatch Magnet Help Soccer ToiletPaper ReadingLamp Paperclip MagicStick Basketball Baseball Coin Goods Sell SoldOut Key ShoppingCart ShoppingCartFull ShoppingTrolley Phone Scissor Handbag ShoppingBag Trophy TrophyBase Stopwatch Timer CollectionTag TakeawayBox PriceTag Wallet').split(' '));
  for (const item of [...(data.introduction.highlights || []), ...(data.prerequisites.cloud || []),
    ...(data.prerequisites.local || []), ...(data.scenarios?.list || [])]) {
    fail(!item.icon || icons.has(item.icon), `icon:${item.icon}`);
  }
  for (const group of ['cloud', 'local']) {
    fail(data.prerequisites[group] === undefined || Array.isArray(data.prerequisites[group]), `prerequisite-list:${group}`);
    for (const item of data.prerequisites[group] || []) {
      fail(item.status === undefined || ['必须', '可选', '建议', '免费'].includes(item.status), `prerequisite-status:${item.title}`);
    }
  }
  for (const name of ['knowledgePoints', 'faqs', 'scenarios', 'challenges']) {
    if (data[name] !== undefined) {
      fail(data[name].list === undefined || Array.isArray(data[name].list), `list-array:${name}`);
      fail(!Object.hasOwn(data[name], 'items'), `list-alias:${name}`);
    }
  }
  for (const kp of data.knowledgePoints.list || []) {
    fail(!Object.hasOwn(kp, 'keywords'), `unknown-keywords-field:${kp.title}`);
    fail(kp.importance === undefined || ['核心', '重要', '了解'].includes(kp.importance), `importance:${kp.title}`);
    fail(kp.subtitle === undefined || typeof kp.subtitle === 'string' && [...kp.subtitle].length <= 200,
      `knowledge-subtitle:${kp.title}`);
    fail(kp.content === undefined || typeof kp.content === 'string', `knowledge-content:${kp.title}`);
  }
  for (const item of data.challenges?.list || []) {
    fail(item.difficulty === undefined || ['简单', '中等', '困难'].includes(item.difficulty), `challenge-difficulty:${item.title}`);
    fail(item.skills === undefined || Array.isArray(item.skills) &&
      item.skills.every(skill => typeof skill === 'string' && skill.trim().length > 0),
      `challenge-skills:${item.title}`);
  }

  function localFile(file) {
    const filename = typeof file === 'string' && file.startsWith('./') ? file.slice(2) : file;
    if (typeof filename !== 'string' || !filename || filename === '.' || filename === '..' ||
      /[\\/:\u0000-\u001f<>"|?*]/.test(filename)) {
      errors.push(`unsafe-or-nonlocal-reference:${file}`);
      return null;
    }
    const resolved = path.resolve(caseDir, filename);
    if (path.dirname(resolved) !== caseDir || !fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
      errors.push(`missing-file:${file}`);
      return null;
    }
    fail(fs.statSync(resolved).size <= 20 * 1024 * 1024, `media-max-20MiB:${file}`);
    return resolved;
  }
  // 检查实际标签/属性，不把提示词代码中的普通文字当成可执行 HTML。
  function inspectHtml(html, field) {
    const stack = [];
    for (const match of html.matchAll(/<\/?([a-z][a-z0-9:-]*)\b([^>]*?)>/gi)) {
      const [tag, rawName, rawAttrs] = match;
      const name = rawName.toLowerCase();
      if (tag.startsWith('</')) {
        const index = stack.lastIndexOf(name);
        if (index >= 0) stack.length = index;
        continue;
      }
      const attrs = Object.fromEntries([...rawAttrs.matchAll(/([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g)]
        .map(value => [value[1].toLowerCase(), value[2] ?? value[3] ?? value[4] ?? '']));
      fail(!['script', 'style', 'iframe', 'html', 'head', 'body', 'object', 'embed'].includes(name),
        `html-forbidden-tag:${field}:${name}`);
      fail(name !== 'article', `editor-article-wrapper:${field}`);
      fail(!(name === 'input' && attrs.type?.toLowerCase() === 'checkbox'), `editor-checkbox:${field}`);
      fail(!(name === 'table' && stack.includes('div')), `editor-div-around-table:${field}`);
      for (const [key, value] of Object.entries(attrs)) {
        fail(!/^on/i.test(key), `html-event-handler:${field}:${key}`);
        if (['href', 'src', 'xlink:href'].includes(key)) {
          const url = value.replace(/&amp;/g, '&').replace(/&#(?:x([0-9a-f]+)|([0-9]+));?/gi,
            (_, hex, decimal) => String.fromCodePoint(parseInt(hex || decimal, hex ? 16 : 10)));
          fail(!/^(?:javascript|vbscript|file|data):/i.test(url.replace(/[\u0000-\u0020]/g, '')),
            `html-unsafe-url:${field}:${key}`);
          if (name === 'img' && key === 'src') localFile(url);
          if (key === 'href' && /\/blob\/[^/]+\//.test(url)) {
            fail(!/%25[0-9a-f]{2}/i.test(url), `link-double-encoded-path:${field}`);
            const repo = base.repoUrl?.replace(/\.git$/, '').replace(/\/$/, '');
            if (repo && url.startsWith(`${repo}/blob/`)) {
              const relative = decodeURIComponent(url.split(/\/blob\/[^/]+\//)[1].split(/[?#]/)[0]);
              const target = path.resolve(caseDir, '..', relative);
              const repoRoot = path.resolve(caseDir, '..');
              fail(target.startsWith(`${repoRoot}${path.sep}`) && fs.existsSync(target) && fs.statSync(target).isFile(),
                `repository-link-target:${field}:${relative}`);
            }
          }
        }
      }
      if (!['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'].includes(name) && !tag.endsWith('/>')) stack.push(name);
    }
  }
  function png(file, width, height) {
    const resolved = localFile(file);
    if (!resolved) return;
    const bytes = fs.readFileSync(resolved);
    const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
    if (bytes.length < 33 || !bytes.subarray(0, 8).equals(signature)) {
      errors.push(`actual-png:${file}`); return;
    }
    const size = [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
    fail(size[0] === width && size[1] === height, `image-size:${file}`);
    if (bytes.length > 500 * 1024) warnings.push(`image-over-recommended-500KiB:${file}`);
    media.push({ file, width: size[0], height: size[1], bytes: bytes.length });
  }
  png(base.coverImage, 2080, 960);
  // cardImage/shareImage 在上游为选填；本仓库当前仍保留这两类正式图片。
  if (base.cardImage) png(base.cardImage, 1920, 974);
  if (base.shareImage) png(base.shareImage, 1200, 1200);
  const names = { phone: '手机', tablet: '平板', foldable: '双折叠展开态', wearable: '智能穿戴' };
  fail(data.preview.devices === undefined || Array.isArray(data.preview.devices), 'preview-devices-array');
  for (const device of data.preview.devices || []) {
    fail(Object.hasOwn(names, device.deviceType), 'device-type');
    fail(device.deviceName === undefined || device.deviceName === names[device.deviceType], 'device-name');
    if (device.previewImage) png(device.previewImage, 2080, 1100);
  }
  const archFile = data.architecture.archImage;
  if (archFile && path.extname(archFile).toLowerCase() === '.png') {
    png(archFile, 2080, 820);
  } else if (archFile) {
    const svgFile = localFile(archFile);
    if (svgFile) {
      const svg = fs.readFileSync(svgFile, 'utf8');
      const root = svg.match(/<svg\b([^>]*)>/i)?.[1] || '';
      const attr = name => root.match(new RegExp(`\\b${name}\\s*=\\s*["']([^"']+)["']`, 'i'))?.[1];
      fail(path.extname(archFile).toLowerCase() === '.svg' && attr('width') === '2080' && attr('height') === '820' &&
        attr('viewBox')?.trim().split(/\s+/).join(' ') === '0 0 2080 820', 'svg-root-dimensions');
      fail(!/<script|<foreignObject|<!ENTITY|\bon\w+\s*=|(?:href|src)\s*=\s*["'](?!#)/i.test(svg),
        'svg-no-active-or-external-content');
      media.push({ file: archFile, width: 2080, height: 820, bytes: Buffer.byteLength(svg) });
    }
  }
  const htmlFile = localFile(data.practice.content);
  if (htmlFile) {
    const html = fs.readFileSync(htmlFile, 'utf8').replace(/\r\n?/g, '\n');
    inspectHtml(html, 'practice');
    for (const [name, value] of [['overview', data.introduction.overview],
      ['targetAudience', data.introduction.targetAudience], ['architecture', data.architecture.description],
      ...(data.knowledgePoints.list || []).map((kp, index) => [`knowledge-${index + 1}`, kp.content])]) {
      if (typeof value === 'string') inspectHtml(value, name);
    }
    const readme = fs.readFileSync(path.resolve(caseDir, '../README.md'), 'utf8').replace(/\r/g, '');
    const tutorial = checkPracticeTutorial(html, readme, base.caseForm);
    errors.push(...tutorial.errors);
  }
  return { ...result(), knowledgePoints: (data.knowledgePoints.list || []).length };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let report;
  try { report = checkCasePackage(); }
  catch (error) { report = { status: 'FAIL', errors: [`package-read-or-structure:${error.message}`] }; }
  console.log(JSON.stringify(report, null, 2));
  if (report.status !== 'LOCAL_PASS') process.exitCode = 1;
}
