import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';

export const OWN_BUNDLE: string = 'com.tonghongxiang.quietstart';
export function runtimeAppLabel(name: string, android: boolean): string {
  return android ? name + '〔卓〕' : name;
}
export class InstalledApp {
  bundleName: string = '';
  label: string = '';
}
export class SeenApp extends InstalledApp {
  firstSeen: number = 0;
  lastSeen: number = 0;
}

export function discoverableBundle(bundle: string): boolean {
  return validBundle(bundle) && bundle !== OWN_BUNDLE &&
    !/^(ohos\.|com\.ohos\.|com\.huawei\.hmos\.(launcher|settings|systemui|sceneboard|permissionmanager|permissioncontroller|screenlock)(\.|$))/.test(bundle);
}

export class AppCatalog {
  source: string = 'device';
  updatedAt: number = 0;
  requestAt: number = 0;
  error: string = '';
  apps: InstalledApp[] = [];
}
export class CatalogPart {
  batch: string = '';
  index: number = 0;
  total: number = 0;
  apps: InstalledApp[] = [];
}
export class LearnedRule {
  key: string = '';
  variant: string = '';
  bundle: string = '';
  targetId: string = '';
  label: string = '';
  labelSource: string = 'text';
  example: string = '';
  recognition: string = '';
  buttonType: string = '';
  labelType: string = '';
  structureKind: string = '';
  progressStyle: string = ''; // Preview metadata only; never part of matching or rule identity.
  marker: string = '';
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
  aspect: number = 0;
  firstSeen: number = 0;
  lastSeen: number = 0;
  observations: number = 0;
  attempts: number = 0;
  successes: number = 0;
  failures: number = 0;
  retained: number = 0;
  unverified: number = 0;
  verificationVersion: number = 2;
  consecutiveFailures: number = 0;
  suspendedAt: number = 0;
}
export class LearnedAppGroup {
  bundle: string;
  rules: LearnedRule[] = [];
  constructor(bundle: string) { this.bundle = bundle; }
}
export function groupLearnedRules(rules: LearnedRule[]): LearnedAppGroup[] {
  const groups: LearnedAppGroup[] = [];
  for (const rule of rules) {
    let group = groups.find((item: LearnedAppGroup) => item.bundle === rule.bundle);
    if (!group) { group = new LearnedAppGroup(rule.bundle); groups.push(group); }
    group.rules.push(rule);
  }
  return groups;
}

export class LearningDiagnostic {
  bundle: string = '';
  at: number = 0;
  reason: string = '';
}
export class RuleDecision {
  key: string = '';
  state: string = 'pending';
  at: number = 0;
  templateAt: number = 0;
}
export interface Box { left: number; top: number; right: number; bottom: number; }

export function validBundle(bundle: string): boolean {
  return typeof bundle === 'string' && /^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/.test(bundle);
}

// Only retain the small, explicit skip label; never persist surrounding page text.
export function skipLabel(text: string): string {
  if (typeof text !== 'string' || text.length > 64) { return ''; }
  const compact = text.replace(/[０-９]/g, (digit: string) => String.fromCharCode(digit.charCodeAt(0) - 65248))
    .replace(/[\s\u200b\u200e\u200f\u2060\ufeff]/g, '').toLowerCase()
    .replace(/過/g, '过').replace(/廣/g, '广').replace(/關/g, '关').replace(/閉/g, '闭')
    .replace(/[（【\[]/g, '(').replace(/[）】\]]/g, ')').replace(/[,，]?(按钮|button)$/, '')
    .replace(/略过/g, '跳过').replace(/(?:跳过|关闭)(?:此|该|本条)广告/g, (value: string) => value.startsWith('跳过') ? '跳过广告' : '关闭广告')
    .replace(/skip(?:this)?(?:advertisement|ads?)/g, 'skipad').replace(/(?:close|dismiss)(?:this)?(?:advertisement|ads?)/g, 'closead');
  if (/^(?:[（(]?\d{1,2}(?:秒|s|sec|seconds?)?[）)]?[|｜·•:：/\-]?)?(跳过广告|跳过|skipad|skip|关闭广告|closead|关闭|close|[x×✕✖✗✘╳])(?:[|｜·•:：/\-]?[（(]?\d{1,2}(?:秒|s|sec|seconds?)?[）)]?)?$/.test(compact)) {
    if (compact.includes('跳过广告')) { return '跳过广告'; }
    if (compact.includes('跳过')) { return '跳过'; }
    if (compact.includes('skip')) { return compact.includes('skipad') ? 'skipad' : 'skip'; }
    if (compact.includes('关闭广告') || compact.includes('closead')) { return '关闭广告'; }
    return /[x×✕✖✗✘╳]/.test(compact) ? '×' : '关闭';
  }
  return '';
}

export function explicitAdAction(label: string): boolean {
  return ['跳过广告', 'skipad', '关闭广告'].includes(label);
}

// Structural fallback for image controls. A close/skip ID alone is not ad evidence.
export function controlIdLabel(id: string): string {
  if (typeof id !== 'string' || id.length > 200) { return ''; }
  const words = id.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase().split(/[^a-z0-9]+/);
  if (words.includes('skip')) { return '跳过图标'; }
  if (words.includes('close') || words.includes('dismiss')) { return '关闭图标'; }
  return '';
}

export function adControlId(id: string): boolean {
  if (!controlIdLabel(id)) { return false; }
  return id.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase().split(/[^a-z0-9]+/)
    .some((word: string) => ['ad', 'ads', 'advert', 'advertisement', 'splash', 'advertising'].includes(word));
}

export function hasSkipCountdown(text: string): boolean {
  if (!skipLabel(text)) { return false; }
  const number = text.replace(/[０-９]/g, (digit: string) => String.fromCharCode(digit.charCodeAt(0) - 65248)).match(/\d{1,2}/);
  return number !== null && Number(number[0]) <= 60;
}

export function isCountdownText(text: string): boolean {
  return typeof text === 'string' && /^\d{1,2}\s*(秒|s|sec|seconds?)$/i.test(text.replace(/[０-９]/g, (digit: string) => String.fromCharCode(digit.charCodeAt(0) - 65248)).trim()) &&
    parseInt(text.replace(/[０-９]/g, (digit: string) => String.fromCharCode(digit.charCodeAt(0) - 65248))) <= 60;
}

export function adLabel(text: string): string {
  if (typeof text !== 'string' || text.length > 32) { return ''; }
  const compact = text.replace(/\s/g, '');
  if (/^广告(?:[·•|｜:：\-].{1,12})?$/.test(compact)) { return '广告'; }
  if (/^(ad|ads|advertisement)(?:[·•|｜:：\-].{1,12})?$/i.test(compact)) {
    return ['Ad', 'AD', 'Advertisement'].includes(compact) ? compact : 'Ad';
  }
  return '';
}

// Location is learned from the actual target, including central/floating controls.
// Bound the size and area so a content card cannot become a dismissal target.
export function isSkipRegion(left: number, top: number, right: number, bottom: number): boolean {
  return [left, top, right, bottom].every((n: number) => Number.isFinite(n)) &&
    left >= 0 && top >= 0 && right <= 1 && bottom <= 1 && right > left && bottom > top &&
    right - left <= 0.60 && bottom - top <= 0.18 && (right - left) * (bottom - top) <= 0.075;
}

export function ruleKey(rule: LearnedRule): string {
  return [rule.bundle, rule.targetId, rule.label, rule.marker,
    Math.round(rule.left * 10).toString(), Math.round(rule.top * 10).toString(),
    Math.round(rule.right * 10).toString(), Math.round(rule.bottom * 10).toString(),
    Math.round(rule.aspect * 5).toString()].join('|') +
    (rule.labelSource === 'description' ? '|description' : (rule.labelSource === 'id' ? '|id' : rule.labelSource === 'structure' ? '|structure' : '')) +
    (rule.variant ? '|geometry:' + rule.variant : '');
}

export function validRule(rule: LearnedRule): boolean {
  if (!rule || !validBundle(rule.bundle) || rule.bundle === OWN_BUNDLE ||
    (rule.variant !== undefined && rule.variant !== '' && !/^\d+(,\d+){4}$/.test(rule.variant)) ||
    typeof rule.targetId !== 'string' || rule.targetId.length > 200 ||
    !['跳过', '跳过广告', 'skip', 'skipad', '关闭广告', '关闭', '×', '跳过图标', '关闭图标'].includes(rule.label) ||
    (rule.labelSource !== undefined && !['text', 'description', 'id', 'structure'].includes(rule.labelSource)) ||
    (rule.example !== undefined && (typeof rule.example !== 'string' || rule.example.length > 64)) ||
    !['label', 'countdown', 'close-countdown', 'control-id', 'structure', '广告', 'Ad', 'AD', 'Advertisement'].includes(rule.marker)) { return false; }
  if ([rule.buttonType, rule.labelType].some((value: string) => value !== undefined &&
    (typeof value !== 'string' || value.length > 80))) { return false; }
  if (rule.progressStyle !== undefined && !['', 'ring', 'linear'].includes(rule.progressStyle)) { return false; }
  if (rule.recognition !== undefined && !['', 'direct', 'parent', 'close-countdown'].includes(rule.recognition)) { return false; }
  if (rule.marker === 'close-countdown' && !['关闭', '×', '关闭图标'].includes(rule.label)) { return false; }
  if (rule.marker === 'label' && !explicitAdAction(rule.label)) { return false; }
  if (rule.labelSource === 'id' && (controlIdLabel(rule.targetId) !== rule.label || !rule.targetId)) { return false; }
  if (['跳过图标', '关闭图标'].includes(rule.label) && !['id', 'structure'].includes(rule.labelSource)) { return false; }
  if ((rule.labelSource === 'structure' || rule.marker === 'structure') &&
    (rule.labelSource !== 'structure' || rule.marker !== 'structure' || rule.label !== '跳过图标' ||
      !['countdown-image', 'splash-corner'].includes(rule.structureKind) || !rule.buttonType)) { return false; }
  if (rule.marker === 'control-id' && !adControlId(rule.targetId)) { return false; }
  if (rule.marker === 'countdown' && ['关闭', '×', '关闭图标', '跳过图标'].includes(rule.label)) { return false; }
  const numbers: number[] = [rule.left, rule.top, rule.right, rule.bottom, rule.aspect,
    rule.observations, rule.attempts, rule.successes, rule.failures, rule.consecutiveFailures,
    rule.suspendedAt, rule.firstSeen, rule.lastSeen];
  return numbers.every((n: number) => Number.isFinite(n) && n >= 0) &&
    isSkipRegion(rule.left, rule.top, rule.right, rule.bottom) &&
    rule.aspect > 0 && rule.aspect < 5 && rule.key === ruleKey(rule);
}

export function sameRuleGeometry(stored: LearnedRule, current: LearnedRule): boolean {
  return stored.key === current.key && Math.abs(stored.aspect - current.aspect) < 0.08 &&
    Math.abs(stored.left - current.left) <= 0.035 && Math.abs(stored.top - current.top) <= 0.035 &&
    Math.abs(stored.right - current.right) <= 0.035 && Math.abs(stored.bottom - current.bottom) <= 0.035;
}

export function ruleState(rule: LearnedRule, decisions: RuleDecision[]): string {
  const decision = decisions.find((item: RuleDecision) => item.key === rule.key);
  if (!decision || decision.templateAt !== rule.firstSeen || decision.at < rule.firstSeen) { return 'pending'; }
  if (decision.state === 'approved' && rule.suspendedAt > 0 && decision.at <= rule.suspendedAt) { return 'suspended'; }
  return decision.state;
}

// Worker owns catalog/rules; UI owns decisions. Separate atomic files avoid
// overwriting user approvals while the worker updates observations and outcomes.
export class LearningStore {
  private directory: string;
  constructor(directory: string) { this.directory = directory; }
  private nameMap(file: string): Record<string, string> {
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/' + file)) as Record<string, string>;
      if (!raw || typeof raw !== 'object' || Array.isArray(raw)) { return {}; }
      const result: Record<string, string> = {};
      for (const bundle of Object.keys(raw).slice(0, 1000)) {
        if (validBundle(bundle) && typeof raw[bundle] === 'string' && raw[bundle].trim().length > 0 && raw[bundle].length <= 80) { result[bundle] = raw[bundle]; }
      }
      return result;
    } catch (_) { return {}; }
  }
  displayName(bundle: string, fallback: string = ''): string {
    return this.nameMap('app-aliases.json')[bundle] || this.nameMap('app-names.json')[bundle] || fallback || bundle;
  }
  androidApps(): string[] {
    const runtimes = this.nameMap('app-runtimes.json');
    const apps = Object.keys(runtimes).filter((bundle: string) => runtimes[bundle] === 'android');
    let changed = false;
    for (const rule of this.readRules()) {
      if (/^android\./.test(rule.buttonType || '') || /^android\./.test(rule.labelType || '')) {
        if (!apps.includes(rule.bundle)) { apps.push(rule.bundle); runtimes[rule.bundle] = 'android'; changed = true; }
      }
    }
    if (changed) { this.write('app-runtimes.json', JSON.stringify(runtimes)); }
    return apps;
  }
  recordAndroidApp(bundle: string): void {
    if (!discoverableBundle(bundle)) { return; }
    const runtimes = this.nameMap('app-runtimes.json');
    if (runtimes[bundle] === 'android') { return; }
    runtimes[bundle] = 'android';
    this.write('app-runtimes.json', JSON.stringify(runtimes));
  }
  clearLegacyAppIcons(): void {
    // Upgrade cleanup: only obsolete icon assets, never rules or app names.
    try {
      for (const name of fs.listFileSync(this.directory)) {
        if (/^app-icon-[A-Za-z0-9_.]+\.png$/.test(name) ||
          ['app-icons.json', 'app-icon-failures.json', 'desktop-icon-tmp.png'].includes(name)) {
          try { fs.unlinkSync(this.directory + '/' + name); } catch (_) {}
        }
      }
    } catch (_) {}
  }
  needsName(bundle: string): boolean {
    return !this.nameMap('app-aliases.json')[bundle] && !this.nameMap('app-names.json')[bundle];
  }
  missingAppNames(): SeenApp[] {
    const names = this.nameMap('app-names.json'); const aliases = this.nameMap('app-aliases.json');
    return this.readSeenApps().filter((app: SeenApp) => !names[app.bundleName] && !aliases[app.bundleName]);
  }
  saveAppName(bundle: string, name: string): void {
    if (!discoverableBundle(bundle) || !name.trim() || name.length > 80 || /[\r\n]/.test(name)) { return; }
    const names = this.nameMap('app-names.json'); names[bundle] = name.trim();
    this.write('app-names.json', JSON.stringify(names));
  }
  readSeenApps(): SeenApp[] {
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/seen-apps.json')) as SeenApp[];
      if (!Array.isArray(raw)) { return []; }
      const names = this.nameMap('app-names.json'); const aliases = this.nameMap('app-aliases.json');
      return raw.filter((app: SeenApp) => app && discoverableBundle(app.bundleName) && typeof app.label === 'string' &&
        Number.isFinite(app.firstSeen) && Number.isFinite(app.lastSeen)).slice(0, 1000)
        .map((app: SeenApp) => { app.label = aliases[app.bundleName] || names[app.bundleName] || app.label; return app; });
    } catch (_) { return []; }
  }
  recordSeenApp(bundle: string): void {
    if (!discoverableBundle(bundle)) { return; }
    const apps = this.readSeenApps();
    let app = apps.find((item: SeenApp) => item.bundleName === bundle);
    if (!app) {
      app = new SeenApp(); app.bundleName = bundle;
      app.label = this.readCatalog().apps.find((item: InstalledApp) => item.bundleName === bundle)?.label || bundle;
      app.firstSeen = Date.now(); apps.push(app);
    }
    app.lastSeen = Date.now();
    this.write('seen-apps.json', JSON.stringify(apps.sort((a: SeenApp, b: SeenApp) => b.lastSeen - a.lastSeen).slice(0, 1000)));
  }
  renameSeenApp(bundle: string, label: string): void {
    if (!discoverableBundle(bundle) || !label.trim() || label.trim().length > 40) { throw new Error('请输入 1～40 字的应用名称'); }
    const aliases = this.nameMap('app-aliases.json'); aliases[bundle] = label.trim();
    this.write('app-aliases.json', JSON.stringify(aliases));
  }

  managedApps(packages: string[], pausedPackages: string[] = []): InstalledApp[] {
    const seen = this.readSeenApps();
    const names = this.readCatalog().apps;
    const result: InstalledApp[] = seen.map((app: SeenApp) => app as InstalledApp);
    for (const bundle of packages.concat(pausedPackages, this.readRules().map((rule: LearnedRule) => rule.bundle))) {
      if (!discoverableBundle(bundle) || result.some((app: InstalledApp) => app.bundleName === bundle)) { continue; }
      const item = new InstalledApp(); item.bundleName = bundle;
      item.label = this.displayName(bundle, names.find((app: InstalledApp) => app.bundleName === bundle)?.label); result.push(item);
    }
    return result;
  }
  readCatalog(): AppCatalog {
    try {
      const value = JSON.parse(fs.readTextSync(this.directory + '/app-catalog.json')) as AppCatalog;
      value.apps = this.parseApps(JSON.stringify(value.apps));
      if (!Number.isFinite(value.updatedAt) || !Number.isFinite(value.requestAt)) { return new AppCatalog(); }
      return value;
    } catch (_) { return new AppCatalog(); }
  }
  parseApps(text: string): InstalledApp[] {
    const raw = JSON.parse(text) as InstalledApp[];
    if (!Array.isArray(raw)) { throw new Error('安装列表格式无效'); }
    const result: InstalledApp[] = [];
    raw.slice(0, 2000).forEach((app: InstalledApp) => {
      if (app && validBundle(app.bundleName) && app.bundleName !== OWN_BUNDLE &&
        typeof app.label === 'string' && !result.some((item: InstalledApp) => item.bundleName === app.bundleName)) {
        const item = new InstalledApp();
        item.bundleName = app.bundleName;
        item.label = app.label.trim().slice(0, 100) || app.bundleName;
        result.push(item);
      }
    });
    return result.sort((a: InstalledApp, b: InstalledApp) => a.label.localeCompare(b.label, 'zh-CN'));
  }
  saveCatalog(value: AppCatalog): void { this.write('app-catalog.json', JSON.stringify(value)); }
  importCatalog(part: CatalogPart): number {
    if (!part || typeof part.batch !== 'string' || !/^[a-zA-Z0-9-]{1,80}$/.test(part.batch) ||
      !Number.isInteger(part.index) || !Number.isInteger(part.total) || part.total < 1 || part.total > 100 ||
      part.index < 0 || part.index >= part.total) { throw new Error('Invalid catalog batch'); }
    part.apps = this.parseApps(JSON.stringify(part.apps));
    let staging: CatalogPart = new CatalogPart();
    if (part.index > 0) {
      staging = JSON.parse(fs.readTextSync(this.directory + '/catalog-import.json')) as CatalogPart;
      if (staging.batch !== part.batch || staging.total !== part.total || staging.index !== part.index - 1) {
        throw new Error('Incomplete catalog batch');
      }
    }
    staging.batch = part.batch; staging.index = part.index; staging.total = part.total;
    staging.apps = this.parseApps(JSON.stringify(staging.apps.concat(part.apps)));
    this.write('catalog-import.json', JSON.stringify(staging));
    if (part.index === part.total - 1) {
      if (staging.apps.length === 0) { throw new Error('Empty catalog'); }
      const catalog = new AppCatalog();
      catalog.source = 'computer'; catalog.updatedAt = Date.now(); catalog.apps = staging.apps;
      this.saveCatalog(catalog);
    }
    return staging.apps.length;
  }
  private readResets(): Record<string, number> {
    let text: string;
    try { text = fs.readTextSync(this.directory + '/rule-resets.json'); }
    catch (error) {
      if ((error as BusinessError).code === 13900002) { return {}; }
      throw new Error('Cannot read rule reset state');
    }
    const raw = JSON.parse(text) as Record<string, number>;
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) { throw new Error('Invalid rule resets'); }
    const result: Record<string, number> = {};
    for (const bundle of Object.keys(raw)) {
      if (!validBundle(bundle) || !Number.isFinite(raw[bundle]) || raw[bundle] <= 0) { throw new Error('Invalid rule reset'); }
      result[bundle] = raw[bundle];
    }
    return result;
  }
  // UI owns reset generations; the worker owns learned-rules.json. Keeping
  // invalidation in a separate atomic file prevents an in-flight worker save
  // from resurrecting deleted rules or their approvals.
  resetAppRules(bundle: string): void {
    if (!discoverableBundle(bundle)) { throw new Error('Invalid application'); }
    const resets = this.readResets();
    resets[bundle] = Math.max(Date.now(), (resets[bundle] ?? 0) + 1);
    this.write('rule-resets.json', JSON.stringify(resets));
  }
  readRules(): LearnedRule[] {
    try {
      const resets = this.readResets();
      const raw = JSON.parse(fs.readTextSync(this.directory + '/learned-rules.json')) as LearnedRule[];
      return Array.isArray(raw) ? raw.filter((rule: LearnedRule) => validRule(rule) &&
        (!(resets[rule.bundle] > 0) || rule.firstSeen > resets[rule.bundle])).slice(0, 200)
        .map((rule: LearnedRule) => {
          // Preserve historical totals and approvals, but old inconclusive
          // timeouts must not contribute to the new confirmed-failure streak.
          if (rule.verificationVersion !== 2) { rule.consecutiveFailures = 0; }
          rule.verificationVersion = 2;
          rule.retained = Number.isFinite(rule.retained) && rule.retained >= 0 ? rule.retained : 0;
          rule.unverified = Number.isFinite(rule.unverified) && rule.unverified >= 0 ? rule.unverified : 0;
          return rule;
        }) : [];
    } catch (_) { return []; }
  }
  saveRules(value: LearnedRule[]): void { this.write('learned-rules.json', JSON.stringify(value)); }
  readDiagnostics(): LearningDiagnostic[] {
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/learning-diagnostics.json')) as LearningDiagnostic[];
      return Array.isArray(raw) ? raw.filter((item: LearningDiagnostic) => item && validBundle(item.bundle) &&
        Number.isFinite(item.at) && item.at > 0 && typeof item.reason === 'string').slice(0, 12) : [];
    } catch (_) { return []; }
  }
  saveCandidateTrace(bundle: string, trace: string): void {
    if (!validBundle(bundle) || !trace || trace.length > 16384) { return; }
    let records: LearningDiagnostic[] = [];
    try {
      const saved = JSON.parse(fs.readTextSync(this.directory + '/candidate-traces.json')) as LearningDiagnostic[];
      if (Array.isArray(saved)) { records = saved.filter((item: LearningDiagnostic) => item && validBundle(item.bundle) &&
        item.bundle !== bundle && typeof item.reason === 'string' && item.reason.length <= 16384).slice(0, 4); }
    } catch (_) {}
    const item = new LearningDiagnostic(); item.bundle = bundle; item.at = Date.now(); item.reason = trace;
    records.unshift(item); this.write('candidate-traces.json', JSON.stringify(records));
  }
  saveDiagnostic(bundle: string, reason: string): void {
    const records = this.readDiagnostics().filter((item: LearningDiagnostic) => item.bundle !== bundle);
    const item = new LearningDiagnostic();
    item.bundle = bundle; item.reason = reason.slice(0, 200); item.at = Date.now();
    records.unshift(item);
    this.write('learning-diagnostics.json', JSON.stringify(records.slice(0, 12)));
  }
  readDecisions(): RuleDecision[] {
    try {
      const resets = this.readResets();
      const raw = JSON.parse(fs.readTextSync(this.directory + '/rule-decisions.json')) as RuleDecision[];
      return Array.isArray(raw) ? raw.filter((item: RuleDecision) => item && typeof item.key === 'string' &&
        ['pending', 'approved', 'rejected'].includes(item.state) && Number.isFinite(item.at) && item.at > 0 &&
        Number.isFinite(item.templateAt) && item.templateAt > (resets[item.key.split('|')[0]] ?? 0)) : [];
    } catch (_) { return []; }
  }
  decide(key: string, state: string): void {
    const decisions = this.readDecisions().filter((item: RuleDecision) => item.key !== key);
    const decision = new RuleDecision();
    decision.key = key; decision.state = state; decision.at = Date.now();
    decision.templateAt = this.readRules().find((rule: LearnedRule) => rule.key === key)?.firstSeen ?? 0;
    decisions.push(decision);
    this.write('rule-decisions.json', JSON.stringify(decisions));
  }
  // Preserve legacy keys and approvals; distinct geometry in the same coarse
  // key bucket must become a separately approved template, never replace it.
  resolveCandidate(candidate: LearnedRule): void {
    candidate.variant = '';
    candidate.key = ruleKey(candidate);
    const base = candidate.key;
    const related = this.readRules().filter((item: LearnedRule) =>
      item.bundle === candidate.bundle && item.targetId === candidate.targetId && item.label === candidate.label &&
      item.marker === candidate.marker && (item.labelSource || 'text') === (candidate.labelSource || 'text'));
    const match = related.find((item: LearnedRule) => {
      const originalKey = candidate.key;
      candidate.key = item.key;
      const compatible = sameRuleGeometry(item, candidate);
      candidate.key = originalKey;
      return compatible;
    });
    if (match) {
      candidate.variant = match.variant ?? ''; candidate.key = match.key; return;
    }
    if (related.some((item: LearnedRule) => item.key === base || item.key.startsWith(base + '|geometry:'))) {
      candidate.variant = [candidate.left, candidate.top, candidate.right, candidate.bottom, candidate.aspect]
        .map((value: number) => Math.round(value * 10000).toString()).join(',');
      candidate.key = ruleKey(candidate);
    }
  }

  observe(candidate: LearnedRule): LearnedRule | undefined {
    candidate.key = ruleKey(candidate);
    if (!validRule(candidate)) { return undefined; }
    this.resolveCandidate(candidate);
    const rules = this.readRules();
    let stored = rules.find((item: LearnedRule) => item.key === candidate.key);
    if (!stored) {
      if (rules.length >= 200) { return undefined; }
      stored = candidate; stored.firstSeen = Math.max(Date.now(), (this.readResets()[candidate.bundle] ?? 0) + 1); rules.unshift(stored);
    }
    stored.lastSeen = Date.now(); stored.observations += 1;
    if (candidate.example) { stored.example = candidate.example; }
    if (candidate.recognition) { stored.recognition = candidate.recognition; }
    if (candidate.buttonType) { stored.buttonType = candidate.buttonType; }
    if (candidate.structureKind) { stored.structureKind = candidate.structureKind; }
    if (candidate.progressStyle) { stored.progressStyle = candidate.progressStyle; }
    if (candidate.labelType) { stored.labelType = candidate.labelType; }
    this.saveRules(rules);
    return stored;
  }
  outcome(key: string, result: string, templateAt: number = 0): void {
    const rules = this.readRules();
    const rule = rules.find((item: LearnedRule) => item.key === key);
    if (!rule || (templateAt > 0 && rule.firstSeen !== templateAt)) { return; }
    if (result === 'attempt') { rule.attempts += 1; }
    if (result === 'success') { rule.successes += 1; rule.consecutiveFailures = 0; }
    if (result === 'unverified') { rule.unverified += 1; rule.consecutiveFailures = 0; }
    if (result === 'retained') {
      rule.retained += 1;
      rule.failures += 1; rule.consecutiveFailures += 1;
      if (rule.consecutiveFailures >= 3) { rule.suspendedAt = Date.now(); rule.consecutiveFailures = 0; }
    }
    this.saveRules(rules);
  }
  private write(name: string, contents: string): void {
    const path = this.directory + '/' + name;
    const file = fs.openSync(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, contents); } finally { fs.closeSync(file); }
    fs.renameSync(path + '.tmp', path);
  }
}
