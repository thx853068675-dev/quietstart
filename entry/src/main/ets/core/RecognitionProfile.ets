// Shared by discovery, storage and UI. Presentation never grants click permission.
export class ProfileBox {
  left: number = 0; top: number = 0; right: number = 1; bottom: number = 1;
}
export class ButtonPart extends ProfileBox {
  role: string = 'text'; text: string = ''; type: string = '';
}
export class ProfileLayer extends ProfileBox {
  role: string = ''; type: string = '';
}
export class RecognitionProfile {
  schema: number = 1;
  strategyId: string = 'S02'; strategyVersion: number = 1;
  evidence: string[] = [];
  shape: string = 'unknown'; shapeSource: string = 'fallback';
  content: string = 'none'; targetMode: string = 'direct';
  button: ProfileBox = new ProfileBox();
  parts: ButtonPart[] = [];
  layers: ProfileLayer[] = [];
}
export interface ProfileRule {
  left: number; top: number; right: number; bottom: number;
  label: string; example?: string; labelSource?: string; origin?: string;
  marker: string; strategy?: string; recognition?: string; structureKind?: string;
  progressStyle?: string; aspect: number; profile?: RecognitionProfile;
}
export class RecognitionStrategy {
  id: string; name: string; example: string; proof: string; target: string; reject: string;
  constructor(id: string, name: string, example: string, proof: string, target: string, reject: string) {
    this.id = id; this.name = name; this.example = example; this.proof = proof; this.target = target; this.reject = reject;
  }
}
export const RECOGNITION_STRATEGIES: RecognitionStrategy[] = [
  new RecognitionStrategy('S01', '明确广告操作', '跳过广告 · 关闭广告', '按钮文字明确指向广告关闭。', '文字对应的按钮或接收手势的紧凑容器。', '视频、登录、授权等其他操作；目标不唯一。'),
  new RecognitionStrategy('S02', '按钮与广告标记', '广告 … 关闭', '关闭目标与当前广告图层或广告标记同时存在。', '相关广告层中的关闭按钮。', '只有普通关闭按钮，缺少广告依据。'),
  new RecognitionStrategy('S03', '文字倒计时', '3s｜跳过 · 跳过 3', '操作按钮与文字计时相组合，支持同组分离排列。', '操作按钮；计时文字不自动成为点击目标。', '只有数字、关联不明，或其他操作混入。'),
  new RecognitionStrategy('S04', '图形倒计时', '圆环内「跳过」· 关闭旁的进度条', '操作按钮与同组的进度控件关联。', '进度环内或相邻的操作按钮。', '只有进度控件，无法确定关闭操作。'),
  new RecognitionStrategy('S05', '图标语义', '× · 带关闭说明的图片', '描述或控件标识提供关闭含义，并有广告依据。', '图标按钮或其接收手势的容器。', '图片没有关闭语义，或标识与实际内容冲突。'),
  new RecognitionStrategy('S06', '广告容器结构', '计时文字 + 图片按钮', '广告容器、图片、计时与关闭控件的层级对应已支持的结构。', '结构中唯一的关闭目标。', '结构不完整、容器过大或存在多个目标。'),
  new RecognitionStrategy('S07', '图片文字兜底', '图片里的「广告」+ 关闭按钮', '已有合理关闭候选，控件证据不足时用 OCR 补充广告标记。', '重新读取并核对后的实时控件。', 'OCR 超时、标记未确认或目标已变化。'),
  new RecognitionStrategy('S08', '用户示范确认', '强化学习 → 手动关闭', '用户主动示范，点击事件对应唯一的小控件，直接保存并启用。', '示范对应的实时控件。', '事件缺失、目标不唯一或点击的是整页容器。')
];
export function strategyDefinition(id: string): RecognitionStrategy {
  return RECOGNITION_STRATEGIES.find((s: RecognitionStrategy) => s.id === id) ?? RECOGNITION_STRATEGIES[1];
}
// Historical rules do not contain full evidence. This adapter does not claim a
// shape or layer that was never captured, and never rewrites keys or approvals.
export function ruleStrategyId(rule: ProfileRule): string {
  if (validProfile(rule.profile)) { return rule.profile!.strategyId; }
  if (rule.origin === 'manual' || rule.marker === 'manual') { return 'S08'; }
  if (rule.strategy === '图片文字兜底') { return 'S07'; }
  if (rule.labelSource === 'structure' || rule.marker === 'structure') { return 'S06'; }
  if (rule.labelSource === 'id' || rule.marker === 'control-id') { return 'S05'; }
  if (rule.marker === 'label') { return 'S01'; }
  if (['countdown', 'close-countdown'].includes(rule.marker)) { return rule.progressStyle ? 'S04' : 'S03'; }
  return 'S02';
}
export function safeButtonText(value: string): string {
  if (typeof value !== 'string' || value.length > 64) { return ''; }
  const compact = value.replace(/[\s\u200b\ufeff]/g, '');
  return compact && /^(?:(?:跳[过過]|略[过過]|[关關][闭閉]|此|本|该|[广廣]告|秒|skip|close|ad|sec|seconds|s)|[0-9０-９×✕✖xX|｜·:：()（）\-])+$/i.test(compact) ? value.trim() : '';
}
export function contentKind(parts: ButtonPart[]): string {
  const text = parts.filter((p: ButtonPart) => !['progress', 'outline'].includes(p.role)).map((p: ButtonPart) => p.role === 'icon' ? '' : p.text).join('')
    .replace(/[０-９]/g, (digit: string) => String.fromCharCode(digit.charCodeAt(0) - 65248));
  const digit = /[0-9０-９]/.test(text);
  const chinese = /[\u3400-\u9fff]/.test(text.replace(/秒/g, ''));
  const letters = /[a-z]/i.test(text.replace(/\d\s*(seconds?|sec|s)/ig, ''));
  if (digit && (chinese || letters)) { return 'mixed'; }
  if (digit) { return 'numeric'; }
  if (chinese && letters) { return 'mixed'; }
  if (chinese) { return 'chinese'; }
  if (letters) { return 'english'; }
  return parts.some((p: ButtonPart) => p.role === 'icon' || /[×✕✖xX]/.test(p.text)) ? 'icon' : 'none';
}
export function shapeName(shape: string): string {
  if (shape === 'circle') { return '圆形'; }
  if (shape === 'ellipse') { return '椭圆'; }
  if (shape === 'capsule') { return '胶囊形'; }
  if (shape === 'rectangle') { return '矩形'; }
  if (shape === 'borderless') { return '无边框'; }
  return shape === 'rounded' ? '圆角矩形' : '圆角矩形示意';
}
export function contentName(content: string): string {
  return content === 'chinese' ? '中文' : content === 'numeric' ? '数字计时' : content === 'mixed' ? '混合内容' : content === 'english' ? '英文' : content === 'icon' ? '图标' : '无文字';
}
export function targetName(mode: string): string {
  return mode === 'parent' ? '点击父容器' : mode === 'sibling' ? '点击关联控件' : mode === 'semantic' ? '语义目标' : mode === 'manual' ? '用户示范' : '点击按钮';
}
export function evidenceName(evidence: string): string {
  const keys = ['explicit-action', 'ad-marker', 'text-countdown', 'graphical-countdown', 'description', 'control-id', 'structure', 'image-ocr', 'manual-click'];
  const names = ['明确广告文字', '广告标记', '文字计时', '图形计时', '控件说明', '控件标识', '广告层级', '图片广告文字', '手动点击'];
  return names[keys.indexOf(evidence)] ?? '';
}
export function layerName(role: string): string {
  return role === 'target' ? '点击目标' : role === 'label' ? '操作文字' : role === 'container' ? '父容器' : role === 'ad-layer' ? '广告依据' : role === 'progress' ? '进度控件' : role === 'countdown' ? '计时文字' : '图片';
}
function validBox(box: ProfileBox): boolean {
  return !!box && [box.left, box.top, box.right, box.bottom].every((n: number) => Number.isFinite(n) && n >= 0 && n <= 1) && box.right > box.left && box.bottom > box.top;
}
export function validProfile(p?: RecognitionProfile): boolean {
  return !!p && p.schema === 1 && p.strategyVersion === 1 && /^S0[1-8]$/.test(p.strategyId) &&
    ['unknown', 'rectangle', 'rounded', 'capsule', 'ellipse', 'circle', 'borderless'].includes(p.shape) &&
    ['fallback', 'attribute'].includes(p.shapeSource) && ['none', 'chinese', 'numeric', 'mixed', 'english', 'icon'].includes(p.content) &&
    ['direct', 'parent', 'sibling', 'semantic', 'manual'].includes(p.targetMode) && validBox(p.button) &&
    Array.isArray(p.evidence) && p.evidence.length <= 9 && p.evidence.every((s: string) => typeof s === 'string' && !!evidenceName(s)) &&
    Array.isArray(p.parts) && p.parts.length <= 12 && p.parts.every((part: ButtonPart) => !!part && validBox(part) &&
      ['text', 'countdown', 'icon', 'progress', 'outline'].includes(part.role) && typeof part.text === 'string' && part.text.length <= 64 &&
      (!['progress', 'outline'].includes(part.role) || ['ring', 'linear'].includes(part.text)) && typeof part.type === 'string' && part.type.length <= 80) &&
    Array.isArray(p.layers) && p.layers.length <= 12 && p.layers.every((layer: ProfileLayer) => !!layer && validBox(layer) &&
      ['target', 'label', 'container', 'ad-layer', 'image', 'progress', 'countdown'].includes(layer.role) && typeof layer.type === 'string' && layer.type.length <= 80);
}
export function profileForRule(rule: ProfileRule): RecognitionProfile {
  if (validProfile(rule.profile)) { return presentationProfile(rule.profile!); }
  const p = new RecognitionProfile(); p.strategyId = ruleStrategyId(rule);
  p.button = { left: rule.left, top: rule.top, right: rule.right, bottom: rule.bottom };
  p.targetMode = rule.origin === 'manual' ? 'manual' : ['parent', 'semantic'].includes(rule.recognition ?? '') ? rule.recognition! : 'direct';
  const part = new ButtonPart(); part.left = rule.left; part.top = rule.top; part.right = rule.right; part.bottom = rule.bottom;
  part.text = typeof rule.example === 'string' && rule.example.length <= 64 ? rule.example : '';
  if (!part.text) { part.text = safeButtonText(rule.label) || ''; }
  if (!part.text || rule.labelSource === 'id' || rule.labelSource === 'structure') { part.role = 'icon'; part.text = /关闭|×/.test(rule.label) ? '×' : ''; }
  p.parts.push(part);
  if (rule.progressStyle) {
    const progress = new ButtonPart(); progress.role = 'progress'; progress.text = rule.progressStyle;
    progress.left = rule.left; progress.top = rule.top; progress.right = rule.right; progress.bottom = rule.bottom;
    p.parts.unshift(progress);
  }
  p.content = contentKind(p.parts); return presentationProfile(p);
}

// Upgrade display metadata without changing rule identity, approvals or input.
// The visible group can be much smaller than its receiver, or contain detached
// seconds. A single group outline includes every displayed part.
export function presentationProfile(source: RecognitionProfile): RecognitionProfile {
  const p = JSON.parse(JSON.stringify(source)) as RecognitionProfile;
  if (p.parts.length === 1 && p.parts[0].role === 'icon' && !p.parts[0].text) {
    const images = p.layers.filter((l: ProfileLayer) => l.role === 'image' &&
      l.left >= p.button.left && l.top >= p.button.top && l.right <= p.button.right && l.bottom <= p.button.bottom);
    if (images.length === 1) {
      const box = images[0]; p.parts[0] = { left: box.left, top: box.top, right: box.right, bottom: box.bottom, role: 'icon', text: '', type: box.type };
    }
  }
  const ring = p.parts.find((part: ButtonPart) => ['progress', 'outline'].includes(part.role) && part.text === 'ring');
  if (ring && p.parts.every((part: ButtonPart) => part.left >= ring.left && part.right <= ring.right && part.top >= ring.top && part.bottom <= ring.bottom)) {
    p.shape = 'circle'; p.shapeSource = 'attribute';
  }
  if (p.parts.length) {
    const boxes: ProfileBox[] = p.shape !== 'unknown' ? [p.button, ...p.parts] : p.parts;
    p.button = { left: Math.min(...boxes.map((b: ProfileBox) => b.left)), top: Math.min(...boxes.map((b: ProfileBox) => b.top)),
      right: Math.max(...boxes.map((b: ProfileBox) => b.right)), bottom: Math.max(...boxes.map((b: ProfileBox) => b.bottom)) };
  }
  return p;
}

export function strategySample(id: string): RecognitionProfile {
  const p = new RecognitionProfile(); p.strategyId = id;
  p.button = { left: 0.25, top: 0.4, right: 0.85, bottom: 0.6 };
  const part = new ButtonPart(); part.left = 0.3; part.top = 0.43; part.right = 0.8; part.bottom = 0.57;
  part.text = id === 'S01' ? '跳过广告' : id === 'S02' || id === 'S07' || id === 'S08' ? '关闭' : '跳过';
  if (id === 'S03') { part.text = '3s｜跳过'; }
  if (id === 'S04' || id === 'S05') {
    p.shape = 'circle'; p.shapeSource = 'attribute';
    p.button = { left: 0.3, top: 0.35, right: 0.7, bottom: 0.6 };
    part.left = 0.32; part.right = 0.68; part.top = 0.43; part.bottom = 0.52;
    if (id === 'S05') { part.role = 'icon'; part.text = '×'; }
    else { p.parts.push({ left: 0.3, top: 0.35, right: 0.7, bottom: 0.6, role: 'progress', text: 'ring', type: 'Progress' }); }
  }
  if (id === 'S06') {
    p.button = { left: 0.6, top: 0.4, right: 0.9, bottom: 0.6 };
    p.parts.push({ left: 0.2, top: 0.44, right: 0.5, bottom: 0.56, role: 'countdown', text: '3s', type: 'Text' });
    part.left = 0.64; part.right = 0.86; part.role = 'icon'; part.text = '';
  }
  p.parts.push(part); p.content = contentKind(p.parts); return p;
}
