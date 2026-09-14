import { ExperienceNode as DiscoveryNode, structuralAction, overlayDismissTarget, dismissImageTarget } from './StructuralExperience';
import { captureProfile } from './ProfileCapture';
import { SnapshotNode, snapshotBounds, imageLayoutSignature, normalizeSnapshotTrees, snapshotImage } from './SnapshotLayout';
import { RecognitionPack, packLabel } from '../../../main/ets/core/RulePack';
import { UIElementInfo, Component, Driver, MatchPattern, ON, On, Rect } from '@kit.TestKit';
import { LearnedRule, LearningStore, ruleKey, skipLabel, hasSkipCountdown, isCountdownText, adLabel,
  explicitAdAction, controlIdLabel, adControlId, discoverableBundle } from '../../../main/ets/core/LearningStore';
import { isSplashButton } from './Rules';
export { imageLayoutSignature } from './SnapshotLayout';

// One native regex query per attribute replaces four separate tree traversals.
// Still inspect both text and description so conflicting targets stay ambiguous.
const SKIP_QUERY: string = '[\\s\\S]*(跳[过過]|略[过過]|[关關][闭閉]|skip|close|dismiss|[×✕✖✗✘╳])[\\s\\S]*|\\s*[xX]\\s*';
const ID_QUERY: string = '[\\s\\S]*(skip|close|dismiss)[\\s\\S]*';
export class ScanReport {
  coordinateReadAt: number = 0;
  coordinateReadyAt: number = 0;
  imageRegions: Rect[] = [];
  imageMarker?: AdMarkerEvidence;
  collectTrace: boolean = false;
  candidateTrace: string = "";
  reason: string = '未找到跳过/关闭文字、图标描述或可识别的广告控件标识';
  readable: boolean = false;
  androidBridge: boolean = false;
  adEvidence: boolean = false;
  cleanPage: boolean = false;
  cleanReason: string = '界面尚未完整读取';
}
export class AdMarkerEvidence {
  label: string;
  source: string;
  bounds: Rect;
  constructor(label: string, source: string, bounds: Rect) {
    this.label = label; this.source = source; this.bounds = bounds;
  }
}
export class LearnedCandidate {
  target: Component;
  textNode: Component;
  rule: LearnedRule;
  adMarker?: AdMarkerEvidence;
  constructor(target: Component, textNode: Component, rule: LearnedRule) {
    this.target = target; this.textNode = textNode; this.rule = rule;
  }
}
class LabelNode {
  node: Component;
  raw: string;
  source: string;
  constructor(node: Component, raw: string, source: string) { this.node = node; this.raw = raw; this.source = source; }
}
function selector(value: string, source: string, pattern: MatchPattern = MatchPattern.EQUALS): On {
  if (source === 'id') { return ON.id(value, pattern); }
  return source === 'description' ? ON.description(value, pattern) : ON.text(value, pattern);
}
export async function readCandidateLabel(candidate: LearnedCandidate): Promise<string> {
  if (candidate.rule.labelSource === 'id') { return controlIdLabel(await candidate.textNode.getId()); }
  return skipLabel(candidate.rule.labelSource === 'description' ? await candidate.textNode.getDescription() :
    await candidate.textNode.getText());
}
function covers(box: Rect, text: Rect): boolean {
  return box.left <= text.left && box.top <= text.top && box.right >= text.right && box.bottom >= text.bottom &&
    box.right - box.left <= Math.max(1, text.right - text.left) * 8 &&
    box.bottom - box.top <= Math.max(1, text.bottom - text.top) * 8;
}
async function findAdMarker(driver: Driver, bundle: string): Promise<AdMarkerEvidence | undefined> {
  for (const source of ['text', 'description']) {
    const markers = await driver.findComponents(selector('[\\s\\S]*(广告|ad)[\\s\\S]*', source, MatchPattern.REG_EXP_ICASE).inWindow(bundle));
    if (!markers || markers.length > 16) { continue; }
    for (const marker of markers) {
      const label = adLabel(source === 'text' ? await marker.getText() : await marker.getDescription());
      if (label) { return new AdMarkerEvidence(label, source, await marker.getBounds()); }
    }
  }
  return undefined;
}
async function hasNearbyCountdown(driver: Driver, bundle: string, text: Rect, window: Rect): Promise<boolean> {
  for (const source of ['text', 'description']) {
    const matches = await driver.findComponents(selector('[\\s\\S]*(秒|s)[\\s\\S]*', source, MatchPattern.REG_EXP_ICASE).inWindow(bundle));
    if (!matches || matches.length > 20) { continue; }
    for (const node of matches) {
      const raw = source === 'text' ? await node.getText() : await node.getDescription();
      if (!isCountdownText(raw)) { continue; }
      const box = await node.getBounds();
      const gapX = Math.max(0, box.left - text.right, text.left - box.right);
      const gapY = Math.max(0, box.top - text.bottom, text.top - box.bottom);
      if (isSplashButton(box, window) && gapX <= (window.right - window.left) * 0.06 &&
        gapY <= (window.bottom - window.top) * 0.02) { return true; }
    }
  }
  return false;
}
export async function findLearnedCandidate(driver: Driver, bundle: string, window: Rect,
  report: ScanReport = new ScanReport()): Promise<LearnedCandidate | undefined> {
  const labels: LabelNode[] = [];
  for (const source of ['text', 'description']) {
    const matches = await driver.findComponents(selector(SKIP_QUERY, source, MatchPattern.REG_EXP_ICASE).inWindow(bundle));
    if (matches && matches.length > 24) { report.reason = '类似跳过的控件过多，等待页面稳定'; return undefined; }
    if (!matches) { continue; }
    for (const node of matches) {
      const raw = source === 'text' ? await node.getText() : await node.getDescription();
      if (!skipLabel(raw)) { report.reason = '找到类似文字，但不是明确的跳过按钮'; continue; }
      if (source === 'description') {
        const text = await node.getText();
        if (skipLabel(text)) { continue; }
      }
      labels.push(new LabelNode(node, raw, source));
    }
  }
  // Query IDs only when text/description discovery found nothing, keeping the
  // common text-button path fast. Never fall back to stored screen coordinates.
  if (labels.length === 0) {
    const icons = await driver.findComponents(ON.id(ID_QUERY, MatchPattern.REG_EXP_ICASE).inWindow(bundle));
    if (icons && icons.length <= 24) {
      for (const icon of icons) {
        const id = await icon.getId();
        if (!controlIdLabel(id)) { continue; }
        const text = await icon.getText();
        const description = await icon.getDescription();
        if ((text && !skipLabel(text)) || (description && !skipLabel(description))) { continue; }
        labels.push(new LabelNode(icon, id, 'id'));
      }
    }
  }
  let candidate: LearnedCandidate | undefined = undefined;
  let pageMarker: AdMarkerEvidence | undefined = undefined;
  let markerChecked: boolean = false;
  for (const found of labels) {
    const node = found.node;
    if (!await node.isEnabled()) { report.reason = '跳过控件暂不可用'; continue; }
    const textBox = await node.getBounds();
    if (!isSplashButton(textBox, window)) { report.reason = '候选控件不可见、超出窗口或面积过大'; continue; }
    let target: Component = node;
    let bounds: Rect = textBox;
    if (!await node.isClickable()) {
      const parents = await driver.findComponents(ON.clickable(true).inWindow(bundle));
      let parent: Component | undefined = undefined;
      let smallestArea: number = Number.POSITIVE_INFINITY;
      let ambiguous: boolean = false;
      if (!parents || parents.length > 100) { report.reason = '未找到可用的点击容器'; continue; }
      for (const possible of parents) {
        const box = await possible.getBounds();
        if (!isSplashButton(box, window) || !covers(box, textBox)) { continue; }
        const children = await driver.findComponents(selector(found.raw, found.source).withinComponent(possible).inWindow(bundle));
        if (!children || children.length !== 1) { continue; }
        const area = (box.right - box.left) * (box.bottom - box.top);
        if (area < smallestArea) { parent = possible; smallestArea = area; ambiguous = false; }
        else if (area === smallestArea) { ambiguous = true; }
      }
      if (!parent || ambiguous || !await parent.isEnabled()) { report.reason = '未找到唯一可用的点击容器'; continue; }
      target = parent;
      bounds = await target.getBounds();
    }
    if (!isSplashButton(bounds, window) || !covers(bounds, textBox)) { report.reason = '点击范围过大或位置不符'; continue; }
    const targetId = await target.getId();
    const label = found.source === 'id' ? controlIdLabel(found.raw) : skipLabel(found.raw);
    let marker: string = explicitAdAction(label) ? 'label' : '';
    // Keep existing text+ad-marker rule keys stable when a countdown is also present.
    if (!marker) {
      if (!markerChecked) { pageMarker = await findAdMarker(driver, bundle); markerChecked = true; }
      marker = pageMarker?.label ?? '';
    }
    const plainSkip = ['跳过', 'skip'].includes(label);
    if (!marker && plainSkip && hasSkipCountdown(found.raw)) { marker = 'countdown'; }
    if (!marker && plainSkip && await hasNearbyCountdown(driver, bundle, textBox, window)) { marker = 'countdown'; }
    if (!marker && adControlId(targetId)) { marker = 'control-id'; }
    if (!marker) { report.reason = plainSkip ? '找到跳过按钮，但缺少广告或倒计时依据' : '找到关闭/图标按钮，但缺少广告标记或广告控件依据'; continue; }
    if (targetId) {
      const sameId = await driver.findComponents(ON.id(targetId).clickable(true).inWindow(bundle));
      if (!sameId || sameId.length !== 1) { report.reason = '跳过控件标识重复，未收集'; return undefined; }
    }
    // Duplicate text/description representations may resolve to the same unique target.
    if (candidate) {
      if (targetId && candidate.rule.targetId === targetId) { continue; }
      report.reason = '存在多个不同的跳过目标，等待页面稳定'; return undefined;
    }
    const rule = new LearnedRule();
    rule.bundle = bundle; rule.targetId = targetId; rule.label = label; rule.marker = marker; rule.labelSource = found.source;
    rule.example = found.source === 'id' ? '' : found.raw.slice(0, 64);
    const width = window.right - window.left;
    const height = window.bottom - window.top;
    rule.left = (bounds.left - window.left) / width; rule.right = (bounds.right - window.left) / width;
    rule.top = (bounds.top - window.top) / height; rule.bottom = (bounds.bottom - window.top) / height;
    rule.aspect = width / height;
    rule.key = ruleKey(rule);
    candidate = new LearnedCandidate(target, node, rule);
    candidate.adMarker = pageMarker;
  }
  if (candidate) { report.reason = '已识别广告关闭目标及其依据'; }
  return candidate;
}

// Verification only tracks the clicked splash region and the marker captured
// during discovery. Unrelated feed ads elsewhere are not evidence it remained.
function sameRegion(box: Rect, reference: Rect, window: Rect): boolean {
  const width = window.right - window.left;
  const height = window.bottom - window.top;
  return box.right > box.left && box.bottom > box.top &&
    box.right > window.left && box.left < window.right && box.bottom > window.top && box.top < window.bottom &&
    Math.abs((box.left + box.right - reference.left - reference.right) / 2) <= width * 0.06 &&
    Math.abs((box.top + box.bottom - reference.top - reference.bottom) / 2) <= height * 0.04;
}

export async function learnedTargetState(driver: Driver, rule: LearnedRule, window: Rect,
  marker?: AdMarkerEvidence): Promise<string> {
  const width = window.right - window.left;
  const height = window.bottom - window.top;
  if (width <= 0 || height <= 0 || Math.abs(width / height - rule.aspect) >= 0.08) { return 'unknown'; }
  const reference: Rect = { left: window.left + rule.left * width, top: window.top + rule.top * height,
    right: window.left + rule.right * width, bottom: window.top + rule.bottom * height };
  if (rule.targetId) {
    const targets = await driver.findComponents(ON.id(rule.targetId).inWindow(rule.bundle));
    for (const target of targets ?? []) {
      const box = await target.getBounds();
      if (box.right > box.left && box.bottom > box.top && box.right > window.left &&
        box.left < window.right && box.bottom > window.top && box.top < window.bottom) { return 'present'; }
    }
  }
  for (const source of ['text', 'description']) {
    const nodes = await driver.findComponents(selector(SKIP_QUERY, source, MatchPattern.REG_EXP_ICASE).inWindow(rule.bundle));
    if (nodes && nodes.length > 24) { return 'unknown'; }
    for (const node of nodes ?? []) {
      const label = skipLabel(source === 'text' ? await node.getText() : await node.getDescription());
      if (label === rule.label || explicitAdAction(label)) {
        const box = await node.getBounds();
        if (sameRegion(box, reference, window)) { return 'present'; }
        if (!rule.targetId && isSplashButton(box, window)) { return 'unknown'; }
      }
    }
  }
  if (marker) {
    const markers = await driver.findComponents(selector('[\\s\\S]*(广告|ad)[\\s\\S]*', marker.source, MatchPattern.REG_EXP_ICASE).inWindow(rule.bundle));
    if (markers && markers.length > 24) { return 'unknown'; }
    for (const node of markers ?? []) {
      const label = adLabel(marker.source === 'text' ? await node.getText() : await node.getDescription());
      if (label && sameRegion(await node.getBounds(), marker.bounds, window)) { return 'blocked'; }
    }
  } else if (!['manual', 'label', 'countdown', 'close-countdown', 'control-id', 'structure'].includes(rule.marker)) {
    // Missing evidence must not silently weaken verification for an old rule.
    return 'unknown';
  }
  return 'absent';
}


function snapshotVisible(a: Record<string, string>): boolean {
  return a.visible === 'true' && (a.opacity === undefined || a.opacity === '' || Number(a.opacity) > 0);
}

// Normalize only local, visible text. Never join arbitrary page text or separate
// clickable actions. This lets one compact button expose "跳" + "过" as a label.
function snapshotLabel(node: SnapshotNode): string {
  const a = node.attributes;
  if (!a) { return ''; }
  if (a.text) { return a.text; }
  if (a.originalText) { return a.originalText; }
  const children = node.children ?? [];
  const box = snapshotBounds(a.bounds);
  if (a.clickable !== 'true' || !box || children.length < 2 || children.length > 4) { return ''; }
  const parts: string[] = [];
  let previous: Rect | undefined = undefined;
  for (const child of children) {
    const c = child.attributes;
    if (!c || !snapshotVisible(c) || c.enabled === 'false' || c.clickable === 'true' ||
      (c.bundleName && c.bundleName !== a.bundleName) ||
      (c.hostWindowId && c.hostWindowId !== a.hostWindowId) || (child.children ?? []).length) { return ''; }
    const bounds = snapshotBounds(c.bounds);
    const value = c.text || c.originalText || '';
    if (!bounds || !value || value.length > 12 || !covers(box, bounds) ||
      (previous && (bounds.left < previous.left || bounds.top >= previous.bottom || bounds.bottom <= previous.top))) { return ''; }
    parts.push(value); previous = bounds;
  }
  const joined = parts.join('');
  return skipLabel(joined) ? joined : '';
}

// The caller independently checks the focused/active UiWindow bundle. Some SDKs put
// the visible splash in a non-focusable window while the app's main window
// retains input focus and is omitted from dumpLayout. Accept that sole visible
// window only for the already verified foreground app; never choose between
// multiple non-focused windows or borrow another app's foreground identity.
function selectSnapshotRoot(roots: SnapshotNode[], bundle: string): SnapshotNode | undefined {
  const focused = roots.filter((root: SnapshotNode) => root.attributes?.focused === 'true');
  if (focused.length === 1 && focused[0].attributes?.bundleName === bundle) { return focused[0]; }
  if (focused.length !== 0 || roots.length !== 1) { return undefined; }
  const a = roots[0].attributes!;
  if (a.bundleName !== bundle || a.focused !== 'false' || !a.hostWindowId ||
    (a.displayId && a.displayId !== '0')) { return undefined; }
  return roots[0];
}

// This is a fresh, unfiltered display snapshot, not a saved rule or per-app
// query. A lone visible application window is usable when UiTest exposes no
// focused/active window at all (non-focusable full-screen splash windows).
// Any second visible root, missing ownership, or secondary display is rejected.
export function soleVisibleAppBundle(text: string): string {
  if (!text || text.length > 8 * 1024 * 1024) { return ''; }
  let count = 0;
  let invalid = false;
  const roots: SnapshotNode[] = [];
  const collect = (node: SnapshotNode, depth: number): void => {
    if (!node || typeof node !== 'object' || depth > 128 || ++count > 20000) { invalid = true; return; }
    if (node.attributes?.type === 'root') {
      if (snapshotVisible(node.attributes)) { roots.push(node); }
      return;
    }
    for (const child of node.children ?? []) { collect(child, depth + 1); }
  };
  try {
    const parsed = JSON.parse(text) as SnapshotNode | SnapshotNode[];
    const trees = Array.isArray(parsed) ? parsed : [parsed];
    normalizeSnapshotTrees(trees);
    for (const tree of trees) { collect(tree, 0); }
  } catch (_) { return ''; }
  if (invalid || roots.length !== 1) { return ''; }
  const a = roots[0].attributes!;
  const window = snapshotBounds(a.origBounds) ?? snapshotBounds(a.bounds);
  const visible = snapshotBounds(a.bounds);
  if (!discoverableBundle(a.bundleName) || !a.hostWindowId ||
    !['true', 'false'].includes(a.focused) || (a.displayId && a.displayId !== '0') ||
    !window || !visible || window.left !== 0 || window.top !== 0 ||
    visible.right - visible.left < (window.right - window.left) * 0.8 ||
    visible.bottom - visible.top < (window.bottom - window.top) * 0.8) { return ''; }
  return a.bundleName;
}

// Some splash SDKs paint the ad badge into an image, but expose a semantic
// SplashAd... identifier on their guide. Ignore instance numbers in that ID.
function splashAdId(value: string): boolean {
  if (typeof value !== 'string' || value.length > 200) { return false; }
  const words = value.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase().split(/[^a-z0-9]+/);
  return (words.includes('splash') && words.some((word: string) => ['ad', 'ads', 'advert', 'advertisement'].includes(word))) ||
    (words.includes('ad') && words.includes('content'));
}

// One dump is one coherent tree. No Component handles are retained or reread
// while the destination page is animating. Only the selected app root is used.
export function snapshotTargetState(text: string, rule: LearnedRule, marker?: AdMarkerEvidence, pack?: RecognitionPack): string {
  if (!text || text.length > 8 * 1024 * 1024) { return 'unknown'; }
  let trees: SnapshotNode[];
  try {
    const parsed = JSON.parse(text) as SnapshotNode | SnapshotNode[];
    trees = Array.isArray(parsed) ? parsed : [parsed];
    normalizeSnapshotTrees(trees);
  } catch (_) { return 'unknown'; }
  const roots: SnapshotNode[] = [];
  let count = 0;
  let invalid = false;
  const collect = (node: SnapshotNode, depth: number): void => {
    if (!node || typeof node !== 'object' || depth > 128 || ++count > 20000) { invalid = true; return; }
    if (node.attributes?.type === 'root') {
      if (snapshotVisible(node.attributes)) { roots.push(node); }
      return;
    }
    for (const child of node.children ?? []) { collect(child, depth + 1); }
  };
  try { for (const tree of trees) { collect(tree, 0); } } catch (_) { return 'unknown'; }
  const root = selectSnapshotRoot(roots, rule.bundle);
  if (invalid || !root) { return 'unknown'; }
  const rootAttributes = root.attributes!;
  const window = snapshotBounds(rootAttributes.origBounds) ?? snapshotBounds(rootAttributes.bounds);
  if (!window) { return 'unknown'; }
  const width = window.right - window.left;
  const height = window.bottom - window.top;
  if (Math.abs(width / height - rule.aspect) >= 0.08) { return 'unknown'; }
  const reference: Rect = { left: window.left + rule.left * width, top: window.top + rule.top * height,
    right: window.left + rule.right * width, bottom: window.top + rule.bottom * height };
  let liveNodes = 0;
  let targetPresent = false;
  let markerPresent = false;
  const imageMarker = marker && ['image-ocr', 'image-memory'].includes(marker.source);
  const imageScopePresent = imageMarker && !!imageLayoutSignature(text, marker!.bounds);
  let ambiguous = false;
  const visit = (node: SnapshotNode, depth: number, parentVisible: boolean, identified: boolean = false): void => {
    if (!node || typeof node !== 'object' || depth > 128 || ++count > 20000) { invalid = true; return; }
    const a = node.attributes;
    if (!a || !parentVisible || !snapshotVisible(a) ||
      (a.bundleName && a.bundleName !== rule.bundle) ||
      (a.hostWindowId && a.hostWindowId !== rootAttributes.hostWindowId)) { return; }
    const box = snapshotBounds(a.bounds);
    if (box && box.right > window.left && box.left < window.right && box.bottom > window.top && box.top < window.bottom) {
      liveNodes += 1;
      if (rule.labelSource === 'manual' && a.type === rule.buttonType && sameRegion(box, reference, window) &&
        manualText(manualActionText(node)) === manualText(rule.example)) { targetPresent = true; }
      if (rule.labelSource === 'structure' && a.type === rule.buttonType && sameRegion(box, reference, window)) { targetPresent = true; }
      if (rule.targetId && a.id === rule.targetId && sameRegion(box, reference, window)) { targetPresent = true; }
      const labels = [recognizedLabel(snapshotLabel(node), 'text', rule.bundle, pack),
        recognizedLabel(a.description, 'description', rule.bundle, pack), recognizedLabel(a.originalText, 'text', rule.bundle, pack)];
      if (labels.some((label: string) => label === rule.label || explicitAdAction(label))) {
        if (sameRegion(box, reference, window) || identified || (!!rule.targetId && a.id === rule.targetId)) { targetPresent = true; }
        else if (!rule.targetId && isSplashButton(box, window)) { ambiguous = true; }
      }
      if (marker && marker.source !== 'approved-button' && (imageMarker ? (snapshotImage(a.type) || a.clickable === 'true') && imageScopePresent &&
        Math.abs(box.left - marker.bounds.left) <= 2 && Math.abs(box.top - marker.bounds.top) <= 2 &&
        Math.abs(box.right - marker.bounds.right) <= 2 && Math.abs(box.bottom - marker.bounds.bottom) <= 2 : marker.source === 'splash-id' ? splashAdId(a.id) :
        !!(adLabel(a.text) || adLabel(a.description) || adLabel(a.originalText))) &&
        sameRegion(box, marker.bounds, window)) { markerPresent = true; }
    }
    for (const child of node.children ?? []) { visit(child, depth + 1, true, identified || (!!rule.targetId && a.id === rule.targetId)); }
  };
  try { for (const child of root.children ?? []) { visit(child, 0, true); } } catch (_) { return 'unknown'; }
  if (invalid || liveNodes === 0) { return 'unknown'; }
  if (targetPresent) { return 'present'; }
  if (markerPresent) { return 'blocked'; }
  if (ambiguous || (!marker && !['manual', 'label', 'countdown', 'close-countdown', 'control-id', 'structure'].includes(rule.marker))) { return 'unknown'; }
  return 'absent';
}

// Exempt only a non-interactive background beneath a readable native tab page.
// A foreground image, Web/Canvas layer or clickable image remains unknown.
function nativePageBackground(image: DiscoveryNode, nodes: DiscoveryNode[]): boolean {
  if (image.a.type !== 'Image') { return false; }
  let branch: DiscoveryNode | undefined = image;
  while (branch && branch.parent) {
    if (branch.a.clickable !== 'false' || Number(branch.a.zIndex || '0') !== 0) { return false; }
    const parent: DiscoveryNode = branch.parent;
    if (parent.a.type === 'Stack') {
      const later = nodes.filter((node: DiscoveryNode) => node.parent === parent && node.order > branch!.order &&
        Number(node.a.zIndex || '0') >= 0);
      for (const sibling of later) {
        const content = nodes.filter((node: DiscoveryNode) => {
          let ancestor: DiscoveryNode | undefined = node;
          while (ancestor) { if (ancestor === sibling) { return true; } ancestor = ancestor.parent; }
          return false;
        });
        if (content.some((node: DiscoveryNode) => node.a.type === 'TabBar') &&
          content.filter((node: DiscoveryNode) => (node.a.text ?? '').trim().length > 0).length >= 3) { return true; }
      }
    }
    branch = parent;
  }
  return false;
}

// Some Android ad SDKs put the enabled image hit target beside a disabled
// decorative text overlay. Link only an exactly co-located sibling image.
function androidSiblingTarget(label: DiscoveryNode, nodes: DiscoveryNode[], window: Rect): DiscoveryNode | undefined {
  if (label.a.type !== 'android.widget.TextView' || label.a.enabled !== 'true') { return undefined; }
  const overlay = label.parent;
  if (!overlay || !overlay.parent || overlay.a.type !== 'android.view.ViewGroup' ||
    overlay.a.clickable !== 'false' || overlay.a.enabled !== 'false') { return undefined; }
  const matches = nodes.filter((node: DiscoveryNode) => node.parent === overlay.parent &&
    node.a.type === 'android.widget.ImageView' && node.a.enabled === 'true' && receivesTouch(node) &&
    node.box.left === overlay.box.left && node.box.top === overlay.box.top &&
    node.box.right === overlay.box.right && node.box.bottom === overlay.box.bottom &&
    covers(node.box, label.box) && isSplashButton(node.box, window));
  return matches.length === 1 ? matches[0] : undefined;
}

// Local diagnostic only: geometry and allowlisted control properties, never page content.
function candidateTrace(target: DiscoveryNode, nodes: DiscoveryNode[], window: Rect): string {
  const padX = (target.box.right - target.box.left) * 1.5;
  const padY = (target.box.bottom - target.box.top) * 1.5;
  const nearby = nodes.filter((node: DiscoveryNode) => node === target ||
    (node.box.left >= target.box.left - padX && node.box.right <= target.box.right + padX &&
    node.box.top >= target.box.top - padY && node.box.bottom <= target.box.bottom + padY)).slice(0, 24);
  const data: Record<string, string>[] = nearby.map((node: DiscoveryNode) => {
    const a: Record<string, string> = {};
    for (const key of ['type', 'bounds', 'origBounds', 'enabled', 'visible', 'clickable', 'hitTestBehavior', 'zIndex']) {
      if (typeof node.a[key] === 'string') { a[key] = node.a[key].slice(0, 100); }
    }
    a.order = String(node.order); a.parent = String(node.parent?.order ?? -1);
    a.label = skipLabel(node.a.text ?? '') || skipLabel(node.a.description ?? '') || adLabel(node.a.text ?? '') || '';
    if (isCountdownText(node.a.text ?? '')) { a.countdown = node.a.text.slice(0, 24); }
    for (const key of ['value', 'max', 'min', 'total', 'progress', 'current', 'rangeValue']) {
      if (/^\d+(?:\.\d+)?$/.test(node.a[key] ?? '')) { a[key] = node.a[key].slice(0, 16); }
    }
    return a;
  });
  return JSON.stringify({ window: window, target: target.order, nodes: data });
}

// OCR requires an already plausible dismissal control in the same large splash layer.
// Small images anywhere are checked first; one large artwork may be read as fallback.
function imageMarkerRegions(target: DiscoveryNode, nodes: DiscoveryNode[], window: Rect): Rect[] {
  const w = window.right - window.left; const h = window.bottom - window.top;
  if (!isSplashButton(target.box, window)) { return []; }
  let layer = target.parent;
  while (layer && !(layer.a.clickable === 'true' && layer.a.enabled === 'true' &&
    layer.box.right - layer.box.left >= w * 0.8 && layer.box.bottom - layer.box.top >= h * 0.8)) { layer = layer.parent; }
  if (!layer) { return []; }
  const scope = layer;
  const images = nodes.filter((node: DiscoveryNode) => {
    if (!snapshotImage(node.a.type) || node.a.clickable === 'true' || node.a.enabled === 'false' || node.a.text || node.a.description ||
      node.box.left < window.left || node.box.top < window.top || node.box.right > window.right ||
      node.box.bottom > window.bottom || node.box.right - node.box.left < 20 || node.box.bottom - node.box.top < 12) { return false; }
    for (let parent = node.parent; parent; parent = parent.parent) { if (parent === scope) { return true; } }
    return false;
  });
  const area = (node: DiscoveryNode): number => (node.box.right - node.box.left) * (node.box.bottom - node.box.top);
  const small = images.filter((node: DiscoveryNode) => area(node) <= 160000)
    .sort((a: DiscoveryNode, b: DiscoveryNode) => area(a) - area(b)).slice(0, 5);
  // The final bounded crop covers the whole candidate layer, including embedded
  // text and Canvas/Web content that exposes no separate Image node.
  return small.map((node: DiscoveryNode) => node.box).concat([scope.box]);
}

function splashMarkerFor(target: DiscoveryNode, nodes: DiscoveryNode[], window: Rect): AdMarkerEvidence | undefined {
  const width = window.right - window.left;
  const height = window.bottom - window.top;
  // Only a corner dismissal inside a large clickable splash layer qualifies.
  // An unrelated close button elsewhere in the app must not borrow its evidence.
  if (!((target.box.right <= window.left + width * 0.35 || target.box.left >= window.left + width * 0.65) &&
    (target.box.bottom <= window.top + height * 0.2 || target.box.top >= window.top + height * 0.8))) { return undefined; }
  for (let layer: DiscoveryNode | undefined = target.parent; layer; layer = layer?.parent) {
    if (layer.a.enabled !== 'true' ||
      layer.box.right - layer.box.left < width * 0.8 || layer.box.bottom - layer.box.top < height * 0.8) { continue; }
    for (const node of nodes) {
      if (!splashAdId(node.a.id) || (layer.a.clickable !== 'true' &&
        (!snapshotImage(node.a.type) || node.box.right - node.box.left < width * 0.8 || node.box.bottom - node.box.top < height * 0.6)) || node.box.right <= node.box.left || node.box.bottom <= node.box.top ||
        node.box.left < window.left || node.box.right > window.right ||
        node.box.top < window.top || node.box.bottom > window.bottom) { continue; }
      for (let parent = node.parent; parent; parent = parent.parent) {
        if (parent === layer) {
          // The guide can be deliberately non-interactive. Visibility matters
          // for evidence; enabled/clickable checks apply to the close target.
          return new AdMarkerEvidence('广告', 'splash-id', node.box);
        }
      }
    }
    // Continue through layout wrappers; only explicit ad content can establish evidence.
  }
  return undefined;
}
// A progress control becomes countdown evidence through its relationship to
// an already recognized dismissal action; no app IDs, digits or OCR required.
function graphicalCountdown(node: DiscoveryNode): boolean {
  const a = node.a;
  if (['Progress', 'ArcProgress', 'android.widget.ProgressBar'].includes(a.type ?? '')) { return true; }
  const semantic = [a.id ?? '', a.type ?? '', a.description ?? ''].join(' ')
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
  return /倒计时/.test(semantic) || /(?:^|[^a-z])count_?down(?:[^a-z]|$)/.test(semantic);
}

function relatedGraphicalCountdown(target: DiscoveryNode, nodes: DiscoveryNode[], window: Rect): DiscoveryNode | undefined {
  const w = window.right - window.left; const h = window.bottom - window.top;
  let scope = target;
  // Transparent layout wrappers are common in both ArkUI and Android guests.
  for (let depth = 0; depth < 3 && scope.parent; depth++) {
    const parent = scope.parent;
    if (parent.box.right - parent.box.left > w * 0.35 ||
      parent.box.bottom - parent.box.top > h * 0.10 || !covers(parent.box, target.box)) { break; }
    scope = parent;
  }
  return nodes.find((other: DiscoveryNode) => {
    if (!graphicalCountdown(other)) { return false; }
    if (other === target) { return true; }
    if (other.a.clickable === 'true' || !covers(scope.box, other.box)) { return false; }
    let related = false;
    for (let parent = other.parent; parent; parent = parent.parent) {
      if (parent === scope) { related = true; break; }
    }
    if (!related) { return false; }
    const gapX = Math.max(0, other.box.left - target.box.right, target.box.left - other.box.right);
    const gapY = Math.max(0, other.box.top - target.box.bottom, target.box.top - other.box.bottom);
    const overlapX = other.box.left < target.box.right && other.box.right > target.box.left;
    const overlapY = other.box.top < target.box.bottom && other.box.bottom > target.box.top;
    return (overlapY && gapX <= w * 0.06) || (overlapX && gapY <= h * 0.02);
  });
}

// A countdown may corroborate a close action only inside the same small
// button group at a screen corner. Mere geometric proximity is insufficient.
function closeCountdown(node: DiscoveryNode, target: DiscoveryNode, nodes: DiscoveryNode[], window: Rect): boolean {
  const w = window.right - window.left; const h = window.bottom - window.top;
  if (!((target.box.right <= window.left + w * 0.35 || target.box.left >= window.left + w * 0.65) &&
    (target.box.bottom <= window.top + h * 0.2 || target.box.top >= window.top + h * 0.8))) { return false; }
  if (hasSkipCountdown(node.a.text) || hasSkipCountdown(node.a.description) ||
    relatedGraphicalCountdown(target, nodes, window)) { return true; }
  const group = target.parent;
  if (!group || group.box.right - group.box.left > w * 0.35 ||
    group.box.bottom - group.box.top > h * 0.10 || !covers(group.box, target.box)) { return false; }
  return nodes.some((other: DiscoveryNode) => other !== node && other.parent === group &&
    other.a.enabled !== 'false' && other.a.clickable !== 'true' &&
    (isCountdownText(other.a.text) || isCountdownText(other.a.description)) &&
    covers(group.box, other.box) && other.box.top < target.box.bottom && other.box.bottom > target.box.top);
}

function excludedContext(target: DiscoveryNode, nodes: DiscoveryNode[], window: Rect): boolean {
  const denied = /片头|片尾|播放视频|正在播放|正在下载|下载中|正在加载|加载中|登录|授权|隐私|用户协议|青少年|新手教程|允许通知|开启通知/;
  let scope = target;
  for (let depth = 0; depth < 2 && scope.parent; depth++) {
    const parent = scope.parent;
    if (parent.box.right - parent.box.left > (window.right - window.left) * 0.95 ||
      parent.box.bottom - parent.box.top > (window.bottom - window.top) * 0.4) { break; }
    scope = parent;
  }
  return nodes.some((other: DiscoveryNode) => {
    if (!denied.test((other.a.text ?? '') + ' ' + (other.a.description ?? ''))) { return false; }
    for (let item: DiscoveryNode | undefined = other; item; item = item.parent) {
      if (item === scope) { return true; }
    }
    return false;
  });
}

// Some SDK gesture handlers omit clickable. Admit only a compact semantic
// label island; discovery still requires separate ad/countdown evidence below.
function semanticTouchTarget(node: DiscoveryNode, nodes: DiscoveryNode[], window: Rect,
  source: string, label: string): DiscoveryNode | undefined {
  if (!['text', 'description'].includes(source) ||
    !['跳过', '跳过广告', 'skip', 'skipad', '关闭', '关闭广告'].includes(label) ||
    node.a.clickable !== 'false' || node.a.enabled !== 'true') { return undefined; }
  for (let item: DiscoveryNode | undefined = node; item; item = item.parent) {
    if (item.a.enabled === 'false' || item.a.hitTestBehavior === 'HitTestMode.Block') { return undefined; }
  }
  const parent = node.parent;
  if (!parent || parent.a.clickable !== 'false' || parent.a.enabled !== 'true' ||
    !['Row', 'Column', 'Stack', 'Flex', 'RelativeContainer', 'Button', 'android.widget.FrameLayout', 'android.widget.LinearLayout', 'android.view.ViewGroup'].includes(parent.a.type ?? '') ||
    !isSplashButton(parent.box, window) || !covers(parent.box, node.box)) { return undefined; }
  const descendants = nodes.filter((other: DiscoveryNode) => {
    for (let p = other.parent; p; p = p.parent) { if (p === parent) { return true; } }
    return false;
  });
  // Decorative circle stacks and split bare seconds are confined to the same
  // compact button. Neither becomes advertising evidence on its own.
  if (descendants.length > 16 || !descendants.every((other: DiscoveryNode) => other === node ||
    (other.a.clickable === 'false' && other.a.enabled !== 'false' && other.box.left >= parent.box.left && other.box.right <= parent.box.right &&
      other.box.top >= parent.box.top && other.box.bottom <= parent.box.bottom &&
      (!other.a.text || isCountdownText(other.a.text) || /^\d{1,2}$/.test(other.a.text.trim())) &&
      (!other.a.description || isCountdownText(other.a.description)) &&
      ['Text', 'Progress', 'LoadingProgress', 'Circle', 'Path', 'Stack', 'Row', 'Column', 'Blank'].includes(other.a.type ?? '')))) { return undefined; }
  if (node.a.hitTestBehavior !== 'HitTestMode.None') { return node; }
  // None applies to the text itself. A gesture on its compact parent can still
  // handle the tap; never enlarge the target to the full-screen ad surface.
  return parent.a.hitTestBehavior !== 'HitTestMode.None' ? parent : undefined;
}
function snapshotTargetId(node: DiscoveryNode, semantic: boolean): string {
  const id = node.a.id ?? '';
  // Generated numeric IDs change at every launch. Semantics, type and live
  // geometry remain mandatory; named developer IDs are still matched exactly.
  return semantic && /^\d+$/.test(id) ? '' : id;
}

// None excludes this node's own hit test, not its descendants. Transparent
// still receives touches, so it must not be treated as an inert background.
function receivesTouch(node: DiscoveryNode): boolean {
  return node.a.clickable === 'true' && node.a.hitTestBehavior !== 'HitTestMode.None';
}

// Compare the two branches at their nearest shared ancestor. A large clickable
// ad image behind a skip label is not an occluder. Only trust reported z-order;
// missing metadata remains ambiguous. Equal z-order follows sibling paint order.
function definitelyBehind(other: DiscoveryNode, target: DiscoveryNode): boolean {
  const left: DiscoveryNode[] = [];
  const right: DiscoveryNode[] = [];
  for (let node: DiscoveryNode | undefined = other; node; node = node.parent) { left.unshift(node); }
  for (let node: DiscoveryNode | undefined = target; node; node = node.parent) { right.unshift(node); }
  let index = 0;
  while (index < left.length && index < right.length && left[index] === right[index]) { index++; }
  if (index >= left.length || index >= right.length) { return false; }
  const a = left[index]; const b = right[index];
  if (a.parent !== b.parent || typeof a.a.zIndex !== 'string' || typeof b.a.zIndex !== 'string' ||
    a.a.zIndex.trim() === '' || b.a.zIndex.trim() === '') { return false; }
  const zA = Number(a.a.zIndex); const zB = Number(b.a.zIndex);
  if (!Number.isFinite(zA) || !Number.isFinite(zB)) { return false; }
  return zA < zB || (zA === zB && a.order < b.order);
}

export class SnapshotCandidate {
  approvedButton: boolean = false;
  rule: LearnedRule;
  adMarker?: AdMarkerEvidence;
  bounds: Rect;
  window: Rect;
  windowId: string;
  constructor(rule: LearnedRule, bounds: Rect, window: Rect, windowId: string) {
    this.rule = rule; this.bounds = bounds; this.window = window; this.windowId = windowId;
  }
}

// Discovery uses one coherent native tree instead of a native round trip for
// every attribute and possible parent. The caller must acquire a second fresh
// matching snapshot before using its live bounds; stored template coordinates never drive input.
export function recognizedLabel(value: string, field: string, bundle: string, pack?: RecognitionPack): string {
  return skipLabel(value) || packLabel(value, field, bundle, pack);
}

export function discoverSnapshot(text: string, bundle: string, report: ScanReport, pack?: RecognitionPack, approvedRules: LearnedRule[] = [], selectedButtonOnly: boolean = false): SnapshotCandidate | undefined {
  const manual = approvedRules.filter((r: LearnedRule) => r.origin === 'manual' && r.bundle === bundle)
    .map((r: LearnedRule) => manualSnapshot(text, bundle, undefined, r)).filter((r: SnapshotCandidate | undefined) => !!r);
  if (manual.length > 1) { report.reason = '多个手动规则匹配，等待明确目标'; return undefined; }
  if (manual.length === 1) { report.reason = '已匹配手动确认的按钮'; return manual[0]; }
  report.reason = '界面读取：布局为空、格式无效或缺少前台窗口';
  if (!text) { report.reason = '界面读取：系统返回空布局，未进入按钮识别'; return undefined; }
  if (text.length > 8 * 1024 * 1024) { report.reason = '界面读取：布局超过 8 MB，停止解析以避免卡顿'; return undefined; }
  let trees: SnapshotNode[];
  try {
    const parsed = JSON.parse(text) as SnapshotNode | SnapshotNode[];
    trees = Array.isArray(parsed) ? parsed : [parsed];
    normalizeSnapshotTrees(trees);
  } catch (_) { report.reason = '界面读取：布局 JSON 无效，未进入按钮识别'; return undefined; }
  const roots: SnapshotNode[] = [];
  let count = 0;
  let invalid = false;
  const collect = (node: SnapshotNode, depth: number): void => {
    if (!node || typeof node !== 'object' || depth > 128 || ++count > 20000) { invalid = true; return; }
    if (node.attributes?.type === 'root') {
      if (snapshotVisible(node.attributes)) { roots.push(node); }
      return;
    }
    for (const child of node.children ?? []) { collect(child, depth + 1); }
  };
  try { for (const tree of trees) { collect(tree, 0); } } catch (_) { return undefined; }
  const root = selectSnapshotRoot(roots, bundle);
  if (invalid) { report.reason = '界面读取：布局结构过深或节点过多，未进入按钮识别'; return undefined; }
  if (!root) {
    report.reason = '窗口核对：读取到 ' + roots.length + ' 个可见窗口，' +
      (roots.length === 0 ? '没有可用的应用窗口' : '无法确认唯一属于当前应用的目标窗口'); return undefined;
  }
  const rootA = root.attributes!;
  report.androidBridge = rootA.quietstartRuntime === 'android';
  const window = snapshotBounds(rootA.origBounds) ?? snapshotBounds(rootA.bounds);
  if (!window) { report.reason = '窗口核对：窗口尺寸无效，无法计算点击范围'; return undefined; }
  if (rootA.displayId && rootA.displayId !== '0') { report.reason = '窗口核对：目标在显示屏 ' + rootA.displayId + '，当前仅检查主屏'; return undefined; }
  const nodes: DiscoveryNode[] = [];
  const visit = (node: SnapshotNode, depth: number, order: number, parent?: DiscoveryNode): void => {
    if (!node || typeof node !== 'object' || depth > 128 || ++count > 20000) { invalid = true; return; }
    const a = node.attributes;
    if (!a || !snapshotVisible(a) || (a.bundleName && a.bundleName !== bundle) ||
      (a.hostWindowId && a.hostWindowId !== rootA.hostWindowId)) { return; }
    const box = snapshotBounds(a.bounds);
    // Retain structural ancestry even for a container without usable bounds.
    const normalized: Record<string, string> = {};
    for (const key of Object.keys(a)) { normalized[key] = a[key]; }
    normalized.text = snapshotLabel(node);
    const item = new DiscoveryNode(normalized, box ?? { left: 0, top: 0, right: 0, bottom: 0 }, order, parent);
    nodes.push(item);
    (node.children ?? []).forEach((child: SnapshotNode, index: number) => { visit(child, depth + 1, index, item); });
  };
  try { (root.children ?? []).forEach((child: SnapshotNode, index: number) => { visit(child, 0, index); }); } catch (_) { return undefined; }
  if (invalid) { return undefined; }
  const width = window.right - window.left;
  const height = window.bottom - window.top;
  let marker: AdMarkerEvidence | undefined = undefined;
  for (const source of ['text', 'description']) {
    for (const node of nodes) {
      const label = adLabel(node.a[source]);
      if (label && node.box.right > node.box.left && node.box.bottom > node.box.top &&
        node.box.left >= window.left && node.box.top >= window.top &&
        node.box.right <= window.right && node.box.bottom <= window.bottom) {
        marker = new AdMarkerEvidence(label, source, node.box); break;
      }
    }
    if (marker) { break; }
  }
  report.readable = true;
  report.adEvidence = /splash|advert/i.test(rootA.pagePath ?? '') || nodes.some((node: DiscoveryNode) => !!recognizedLabel(node.a.text, 'text', bundle, pack) || !!recognizedLabel(node.a.description, 'description', bundle, pack) ||
    !!controlIdLabel(node.a.id) || !!adLabel(node.a.text) || !!adLabel(node.a.description) ||
    splashAdId(node.a.id) || /广告|[sS]plash|[aA]dvert/.test((node.a.text ?? '') + ' ' + (node.a.description ?? '') + ' ' + (node.a.id ?? '')));
  const visibleBox = snapshotBounds(rootA.bounds);
  const unknownLayer = nodes.some((node: DiscoveryNode) => /Image|Canvas|XComponent|Web/.test(node.a.type ?? '') &&
    (node.box.right - node.box.left) * (node.box.bottom - node.box.top) > width * height * 0.45 &&
    !nativePageBackground(node, nodes));
  report.cleanReason = roots.length !== 1 ? '存在多个窗口' : report.adEvidence ? '发现广告或关闭控件线索' :
    unknownLayer ? '大面积图片或绘制内容无法核实' : nodes.length < 6 ||
    nodes.filter((node: DiscoveryNode) => (node.a.text ?? '').trim().length > 0).length < 3 ? '可读取的界面内容不足' :
    !visibleBox || visibleBox.right - visibleBox.left < width * 0.8 ||
    visibleBox.bottom - visibleBox.top < height * 0.8 ? '应用窗口未完整显示' : '';
  report.cleanPage = report.cleanReason.length === 0;
  report.reason = '目标识别：已读取 ' + nodes.length + ' 个可见控件；跳过/关闭文字、无障碍描述及图标标识均未匹配。图片内文字或未开放的控件可能无法读取，不能据此判定没有广告';
  const structuralKinds = new Map<DiscoveryNode, string>();
  const structuralKind = (node: DiscoveryNode): string => {
    if (node.a.text || node.a.description) { return ''; }
    if (structuralKinds.has(node)) { return structuralKinds.get(node)!; }
    const saved = approvedRules.find((rule: LearnedRule) => rule.labelSource === 'structure' && rule.bundle === bundle &&
      rule.targetId === (node.a.id ?? '') && rule.buttonType === node.a.type && !node.a.text && !node.a.description &&
      Math.abs(rule.aspect - width / height) < 0.08 &&
      Math.abs(rule.left - (node.box.left - window.left) / width) <= 0.015 &&
      Math.abs(rule.right - (node.box.right - window.left) / width) <= 0.015 &&
      Math.abs(rule.top - (node.box.top - window.top) / height) <= 0.015 &&
      Math.abs(rule.bottom - (node.box.bottom - window.top) / height) <= 0.015);
    const kind = saved?.structureKind || structuralAction(node, nodes, window);
    structuralKinds.set(node, kind);
    return kind;
  };
  const labels = nodes.filter((node: DiscoveryNode) => !!recognizedLabel(node.a.text, 'text', bundle, pack) || !!recognizedLabel(node.a.description, 'description', bundle, pack));
  const sources = nodes.filter((node: DiscoveryNode) => !!structuralKind(node) || (!overlayDismissTarget(node, nodes, window) && (labels.includes(node) || (!!controlIdLabel(node.a.id) &&
    (!node.a.text || !!recognizedLabel(node.a.text, 'text', bundle, pack)) && (!node.a.description || !!recognizedLabel(node.a.description, 'description', bundle, pack))))));
  if (sources.length > 24) { report.reason = '目标识别：发现 ' + sources.length + ' 个候选，超过 24 个，无法确定唯一目标'; return undefined; }
  let result: SnapshotCandidate | undefined = undefined;
  let selectedTarget: DiscoveryNode | undefined = undefined;
  for (const node of sources) {
    const kind = structuralKind(node);
    const source = kind ? 'structure' : recognizedLabel(node.a.text, 'text', bundle, pack) ? 'text' : (recognizedLabel(node.a.description, 'description', bundle, pack) ? 'description' : 'id');
    const raw = node.a[source] ?? '';
    const label = source === 'structure' ? '跳过图标' : source === 'id' ? controlIdLabel(raw) : recognizedLabel(raw, source, bundle, pack);
    if (node.a.enabled !== 'true') { report.reason = '目标识别：候选「' + label + '」' +
      (node.a.enabled === 'false' ? '已禁用，不可点击' : '缺少 enabled 状态，无法确认可点击'); continue; }
    if (!isSplashButton(node.box, window)) {
      report.reason = '位置核对：候选「' + label + '」范围 [' + node.box.left + ',' + node.box.top + '][' +
        node.box.right + ',' + node.box.bottom + '] 不符合窗口内开屏按钮的尺寸或位置要求'; continue;
    }
    const siblingTarget = androidSiblingTarget(node, nodes, window);
    let disabledAncestor = false;
    for (let parent = siblingTarget ? siblingTarget.parent : node.parent; parent; parent = parent.parent) {
      if (parent.a.enabled === 'false') { disabledAncestor = true; break; }
    }
    if (disabledAncestor) { report.reason = '目标识别：控件所在容器已禁用'; continue; }
    let target: DiscoveryNode | undefined = siblingTarget ?? (receivesTouch(node) ? node : undefined);
    if (!target) {
      let area = Number.POSITIVE_INFINITY;
      for (let parent = node.parent; parent; parent = parent.parent) {
        const size = (parent.box.right - parent.box.left) * (parent.box.bottom - parent.box.top);
        if (receivesTouch(parent) && parent.a.enabled === 'true' &&
          isSplashButton(parent.box, window) && covers(parent.box, node.box) && size < area) {
          target = parent; area = size;
        }
      }
    }
    const semanticTarget = !target ? semanticTouchTarget(node, nodes, window, source, label) : undefined;
    const semantic = !!semanticTarget;
    if (semanticTarget) { target = semanticTarget; }
    if (!target || !covers(target.box, node.box)) {
      if (report.collectTrace && !report.candidateTrace) { report.candidateTrace = candidateTrace(node, nodes, window); }
      report.reason = '点击核对：候选「' + label + '」本身不可点击，也没有尺寸合适的可点击父容器'; continue; }
    if (excludedContext(target, nodes, window)) {
      report.reason = '场景排除：目标所在容器包含登录、授权、教程或视频操作，未学习'; continue;
    }
    // An enabled learned button is sufficient. Ad copy, artwork and surrounding
    // layout are deliberately excluded from this match; all input guards remain below.
    const button = target;
    const learnedButton = approvedRules.find((saved: LearnedRule) => saved.bundle === bundle &&
      saved.label === label && (saved.labelSource || 'text') === source && saved.targetId === snapshotTargetId(button, semantic) &&
      (!saved.recognition || saved.recognition === 'close-countdown' || saved.recognition === (semantic ? 'semantic' : (button === node ? 'direct' : 'parent'))) &&
      (!saved.buttonType || saved.buttonType === button.a.type) && (!saved.labelType || saved.labelType === node.a.type) &&
      Math.abs(saved.aspect - width / height) < 0.08 &&
      Math.abs(saved.left - (button.box.left - window.left) / width) <= 0.015 &&
      Math.abs(saved.right - (button.box.right - window.left) / width) <= 0.015 &&
      Math.abs(saved.top - (button.box.top - window.top) / height) <= 0.015 &&
      Math.abs(saved.bottom - (button.box.bottom - window.top) / height) <= 0.015);
    if (selectedButtonOnly && !learnedButton) { report.reason = '已选按钮的位置、样式或状态已变化，等待重新匹配'; continue; }
    const regions = learnedButton ? [] : imageMarkerRegions(target, nodes, window);
    const visualMarker = report.imageMarker && regions.some((box: Rect) => box.left === report.imageMarker!.bounds.left &&
      box.top === report.imageMarker!.bounds.top && box.right === report.imageMarker!.bounds.right &&
      box.bottom === report.imageMarker!.bounds.bottom) ? report.imageMarker : undefined;
    const targetMarker = learnedButton ? (marker ?? new AdMarkerEvidence('', 'approved-button', target.box)) :
      (splashMarkerFor(target, nodes, window) ?? marker ?? visualMarker);
    let evidence = learnedButton ? learnedButton.marker : kind ? 'structure' : (explicitAdAction(label) ? 'label' : (targetMarker?.label ?? ''));
    if (!evidence && ['跳过', 'skip'].includes(label)) {
      if (hasSkipCountdown(raw) || relatedGraphicalCountdown(target, nodes, window) || nodes.some((other: DiscoveryNode) => {
        const gapX = Math.max(0, other.box.left - node.box.right, node.box.left - other.box.right);
        const gapY = Math.max(0, other.box.top - node.box.bottom, node.box.top - other.box.bottom);
        return (isCountdownText(other.a.text) || isCountdownText(other.a.description) ||
          (other.parent === node.parent && !!node.parent && isSplashButton(node.parent.box, window) && /^\d{1,2}$/.test((other.a.text ?? '').trim()) && Number(other.a.text) <= 60)) &&
          isSplashButton(other.box, window) && gapX <= width * 0.06 && gapY <= height * 0.02;
      })) { evidence = 'countdown'; }
    }
    if (!evidence && ['关闭', '×', '关闭图标'].includes(label) && closeCountdown(node, target, nodes, window)) {
      evidence = 'close-countdown';
    }
    if (!evidence && adControlId(target.a.id)) { evidence = 'control-id'; }
    if (semantic && !learnedButton && !targetMarker && !['countdown', 'close-countdown'].includes(evidence)) {
      report.reason = '语义按钮未报告点击能力：还需要独立的广告标记或倒计时依据'; continue;
    }
    if (!evidence) {
      if (regions.length && !report.imageRegions.length) { report.imageRegions = regions; }
      report.reason = '找到候选「' + label + '」，但缺少广告或倒计时依据（未读取到有效信息）；未生成新规则。文字或图形倒计时任一可确认即可；当前未读取到可确认的倒计时信息';
      if (report.collectTrace && !report.candidateTrace) { report.candidateTrace = candidateTrace(target, nodes, window); }
      continue;
    }
    const imageTarget = dismissImageTarget(target, nodes, window);
    if (imageTarget === null) { report.reason = '图片关闭目标不可点击或存在多个图片，取消点击'; continue; }
    const currentTarget = imageTarget ?? target;
    const centerX = (currentTarget.box.left + currentTarget.box.right) / 2;
    const centerY = (currentTarget.box.top + currentTarget.box.bottom) / 2;
    const related = (other: DiscoveryNode): boolean => {
      for (let item: DiscoveryNode | undefined = other; item; item = item.parent) {
        if (item === currentTarget) { return true; }
      }
      for (let item: DiscoveryNode | undefined = currentTarget; item; item = item.parent) {
        if (item === other) { return true; }
      }
      return false;
    };
    if (nodes.some((other: DiscoveryNode) => (receivesTouch(other) || other.a.hitTestBehavior === 'HitTestMode.Block') && !related(other) && overlayDismissTarget(other, nodes, window) !== currentTarget && !definitelyBehind(other, currentTarget) &&
      centerX >= other.box.left && centerX <= other.box.right && centerY >= other.box.top && centerY <= other.box.bottom)) {
      report.reason = '点击位置与其他控件重叠：目标「' + label + '」中心 (' + Math.round(centerX) + ', ' + Math.round(centerY) + ') 可能被覆盖，取消点击'; return undefined;
    }
    const targetId = snapshotTargetId(target, semantic);
    // IDs are often shared by an SDK's unrelated controls. Uniqueness is
    // established by live semantics + ancestry + ad evidence + hit geometry,
    // not by counting an ID across the whole page. The selectedTarget check
    // below still rejects two independently valid candidates, even with one ID.
    if (selectedTarget) {
      if (selectedTarget === target) { continue; }
      report.reason = '存在多个不同的跳过目标，等待页面稳定'; return undefined;
    }
    const rule = new LearnedRule();
    rule.bundle = bundle; rule.targetId = targetId; rule.label = label; rule.marker = evidence; rule.labelSource = source;
    rule.recognition = semantic ? 'semantic' : evidence === 'close-countdown' ? 'close-countdown' : (target !== node ? 'parent' : 'direct');
    rule.structureKind = kind;
    rule.strategy = learnedButton?.strategy || (targetMarker?.source === 'image-ocr' ? '图片文字兜底' :
      evidence === 'label' ? '明确广告文字' : ['countdown', 'close-countdown'].includes(evidence) ? '按钮与倒计时' :
      ['structure', 'control-id'].includes(evidence) || targetMarker?.source === 'splash-id' ? '广告控件结构' : '按钮与广告标记');
    rule.buttonType = target.a.type ?? ''; rule.labelType = node.a.type ?? '';
    const progress = relatedGraphicalCountdown(target, nodes, window);
    if (progress) {
      const pw = progress.box.right - progress.box.left; const ph = progress.box.bottom - progress.box.top;
      rule.progressStyle = pw > 0 && ph > 0 && pw / ph >= 0.75 && pw / ph <= 1.33 ? 'ring' : 'linear';
    } else { rule.progressStyle = learnedButton?.progressStyle ?? ''; }
    rule.example = source === 'id' ? '' : raw.slice(0, 64);
    rule.left = (target.box.left - window.left) / width; rule.right = (target.box.right - window.left) / width;
    rule.top = (target.box.top - window.top) / height; rule.bottom = (target.box.bottom - window.top) / height;
    rule.aspect = width / height;
    rule.profile = selectedButtonOnly ? learnedButton?.profile :
      captureProfile(rule, target, node, nodes, window, progress, targetMarker?.source ?? '', targetMarker?.bounds, learnedButton, !!siblingTarget);
    if (learnedButton) { rule.variant = learnedButton.variant ?? ''; }
    rule.key = ruleKey(rule);
    result = new SnapshotCandidate(rule, currentTarget.box, window, rootA.hostWindowId ?? '');
    result.approvedButton = !!learnedButton;
    result.adMarker = learnedButton ? targetMarker : (explicitAdAction(label) ? undefined : targetMarker);
    selectedTarget = target;
  }
  if (result) { report.reason = '已识别广告关闭目标及其依据'; }
  return result;
}

// Manual training never uses a saved coordinate as input. The user click is
// correlated to one live compact component; subsequent matches require the
// same window-relative geometry, type, developer ID and action text.
function manualText(value: string): string {
  return skipLabel(value) || (value ?? '').trim().slice(0, 64);
}
function manualTree(text: string, bundle: string): SnapshotNode | undefined {
  if (!text || text.length > 8 * 1024 * 1024) { return undefined; }
  try {
    const parsed = JSON.parse(text) as SnapshotNode | SnapshotNode[];
    const trees = Array.isArray(parsed) ? parsed : [parsed]; normalizeSnapshotTrees(trees);
    const roots: SnapshotNode[] = []; let count = 0;
    const walk = (n: SnapshotNode, depth: number): void => {
      if (!n || depth > 128 || ++count > 20000) { throw new Error('Invalid tree'); }
      if (n.attributes?.type === 'root') { if (snapshotVisible(n.attributes)) { roots.push(n); } return; }
      for (const c of n.children ?? []) { walk(c, depth + 1); }
    };
    for (const t of trees) { walk(t, 0); }
    return selectSnapshotRoot(roots, bundle);
  } catch (_) { return undefined; }
}
function manualActionText(node: SnapshotNode, depth: number = 0): string {
  if (depth > 4) { return ''; }
  const value = snapshotLabel(node) || node.attributes?.description || '';
  if (value) { return value; }
  const labels = (node.children ?? []).map((c: SnapshotNode) => skipLabel(manualActionText(c, depth + 1)))
    .filter((label: string) => !!label);
  return labels.length === 1 ? labels[0] : '';
}
export function manualSnapshot(text: string, bundle: string, event?: UIElementInfo,
  saved?: LearnedRule): SnapshotCandidate | undefined {
  if ((!event && !saved) || (event && (event.bundleName !== bundle || !event.componentRect))) { return undefined; }
  const root = manualTree(text, bundle); const a = root?.attributes;
  const window = a ? snapshotBounds(a.origBounds) ?? snapshotBounds(a.bounds) : undefined;
  if (!root || !a || !window || (a.displayId && a.displayId !== '0') ||
    (event?.windowId !== undefined && String(event.windowId) !== a.hostWindowId)) { return undefined; }
  const width = window.right - window.left; const height = window.bottom - window.top;
  if (saved && Math.abs(saved.aspect - width / height) >= 0.08) { return undefined; }
  const reference = event?.componentRect ?? { left: window.left + saved!.left * width,
    right: window.left + saved!.right * width, top: window.top + saved!.top * height, bottom: window.top + saved!.bottom * height };
  let count = 0; const found: SnapshotCandidate[] = [];
  const pool: DiscoveryNode[] = []; let selected: DiscoveryNode | undefined;
  const visit = (n: SnapshotNode, depth: number, order: number, parent?: DiscoveryNode): void => {
    if (depth > 128 || ++count > 20000) { throw new Error('Invalid tree'); }
    const v = n.attributes; if (!v || !snapshotVisible(v) || v.enabled === 'false' ||
      (v.bundleName && v.bundleName !== bundle) || (v.hostWindowId && v.hostWindowId !== a.hostWindowId)) { return; }
    const box = snapshotBounds(v.bounds);
    const item = new DiscoveryNode(v, box ?? { left: 0, top: 0, right: 0, bottom: 0 }, order, parent); pool.push(item);
    if (v.hitTestBehavior === 'HitTestMode.Block') { return; }
    const label = manualActionText(n);
    const id = /^\d+$/.test(v.id ?? '') ? '' : (v.id ?? '');
    const safeType = /^(Text|Button|Image|Row|Column|Stack|Flex|RelativeContainer|SymbolGlyph|View|android\.widget\.(TextView|Button|ImageView)|android\.view\.View)$/.test(v.type ?? '');
    const identity = event ? v.type === event.type &&
      (!event.componentId || event.componentId === v.id || event.componentId === v.accessibilityId) &&
      (!event.text || manualText(event.text) === manualText(label)) :
      v.type === saved!.buttonType && id === saved!.targetId && manualText(label) === manualText(saved!.example);
    const tolerance = event ? 2 : Math.min(width, height) * 0.015;
    if (box && v.enabled === 'true' && v.hitTestBehavior !== 'HitTestMode.None' && safeType && identity &&
      Math.abs(box.left - reference.left) <= tolerance && Math.abs(box.top - reference.top) <= tolerance &&
      Math.abs(box.right - reference.right) <= tolerance && Math.abs(box.bottom - reference.bottom) <= tolerance &&
      isSplashButton(box, window) && !/登录|授权|同意|支付|购买|允许|下一步|隐私|协议|首页|我的|设置|返回|取消/.test(label)) {
      const r = new LearnedRule(); r.bundle = bundle; r.origin = 'manual'; r.strategy = '手动点击确认';
      r.targetId = id; r.labelSource = 'manual'; r.marker = 'manual'; r.label = skipLabel(label) || '关闭图标';
      r.example = label.slice(0, 64); r.buttonType = v.type; r.labelType = v.type;
      r.left = (box.left - window.left) / width; r.right = (box.right - window.left) / width;
      r.top = (box.top - window.top) / height; r.bottom = (box.bottom - window.top) / height; r.aspect = width / height;
      r.variant = saved?.variant ?? ''; r.key = ruleKey(r);
      found.push(new SnapshotCandidate(r, box, window, a.hostWindowId ?? '')); selected = item;
    }
    (n.children ?? []).forEach((c: SnapshotNode, i: number) => { visit(c, depth + 1, i, item); });
  };
  try { (root.children ?? []).forEach((c: SnapshotNode, i: number) => { visit(c, 0, i); }); } catch (_) { return undefined; }
  if (found.length !== 1) {
    // Some gesture handlers report the enclosing toolbar rather than its
    // close label. Resolve only a unique, independently evidenced ad target
    // beneath that exact event source; never infer a tap on the ad surface.
    if (!event || found.length > 1) { return undefined; }
    const sources = pool.filter((n: DiscoveryNode) => {
      const box = snapshotBounds(n.a.origBounds) ?? n.box;
      return n.a.type === event.type && n.a.enabled === 'true' &&
        (!event.componentId || event.componentId === n.a.id || event.componentId === n.a.accessibilityId) &&
        Math.abs(box.left - reference.left) <= 2 && Math.abs(box.top - reference.top) <= 2 &&
        Math.abs(box.right - reference.right) <= 2 && Math.abs(box.bottom - reference.bottom) <= 2 &&
        box.bottom - box.top <= height * 0.25;
    });
    if (sources.length !== 1) { return undefined; }
    const candidate = discoverSnapshot(text, bundle, new ScanReport());
    if (!candidate || candidate.rule.labelSource === 'manual') { return undefined; }
    const targets = pool.filter((n: DiscoveryNode) => n.a.type === candidate.rule.buttonType &&
      Math.abs(n.box.left - (window.left + candidate.rule.left * width)) <= 2 && Math.abs(n.box.right - (window.left + candidate.rule.right * width)) <= 2 &&
      Math.abs(n.box.top - (window.top + candidate.rule.top * height)) <= 2 && Math.abs(n.box.bottom - (window.top + candidate.rule.bottom * height)) <= 2);
    if (targets.length !== 1 || targets[0] === sources[0]) { return undefined; }
    let parent = targets[0].parent;
    while (parent && parent !== sources[0]) { parent = parent.parent; }
    if (!parent) { return undefined; }
    const targetEvent: UIElementInfo = { bundleName: bundle, type: targets[0].a.type ?? '', text: '',
      windowId: event.windowId, componentRect: targets[0].box };
    return manualSnapshot(text, bundle, targetEvent);
  }
  const imageTarget = dismissImageTarget(selected!, pool, window);
  if (imageTarget === null) { return undefined; }
  const target = imageTarget ?? selected!;
  const centerX = (target.box.left + target.box.right) / 2; const centerY = (target.box.top + target.box.bottom) / 2;
  const related = (other: DiscoveryNode): boolean => {
    for (let p: DiscoveryNode | undefined = other; p; p = p.parent) { if (p === target) { return true; } }
    for (let p: DiscoveryNode | undefined = target; p; p = p.parent) { if (p === other) { return true; } }
    return false;
  };
  if (pool.some((other: DiscoveryNode) => (receivesTouch(other) || other.a.hitTestBehavior === 'HitTestMode.Block') &&
    !related(other) && !definitelyBehind(other, target) && centerX >= other.box.left && centerX <= other.box.right &&
    centerY >= other.box.top && centerY <= other.box.bottom)) { return undefined; }
  const candidate = found[0]; candidate.approvedButton = !!saved;
  candidate.bounds = target.box;
  candidate.rule.profile = captureProfile(candidate.rule, selected!, selected!, pool, window,
    relatedGraphicalCountdown(target, pool, window), '', undefined, saved);
  candidate.adMarker = new AdMarkerEvidence('', 'approved-button', candidate.bounds);
  return candidate;
}
