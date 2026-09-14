import { Rect } from '@kit.TestKit';
import { ExperienceNode, dismissImageTarget } from './StructuralExperience';
import { LearnedRule, hasSkipCountdown, isCountdownText } from '../../../main/ets/core/LearningStore';
import { ButtonPart, ProfileBox, ProfileLayer, RecognitionProfile, contentKind, safeButtonText,
  ruleStrategyId, validProfile } from '../../../main/ets/core/RecognitionProfile';

function inside(a: Rect, b: Rect): boolean {
  return a.left >= b.left && a.top >= b.top && a.right <= b.right && a.bottom <= b.bottom && a.right > a.left && a.bottom > a.top;
}
function beneath(node: ExperienceNode, ancestor: ExperienceNode): boolean {
  for (let n: ExperienceNode | undefined = node; n; n = n.parent) { if (n === ancestor) { return true; } }
  return false;
}
function normalized(box: Rect, window: Rect): ProfileBox {
  const w = window.right - window.left; const h = window.bottom - window.top;
  return { left: (box.left - window.left) / w, top: (box.top - window.top) / h,
    right: (box.right - window.left) / w, bottom: (box.bottom - window.top) / h };
}
function partFor(node: ExperienceNode, window: Rect, role: string, text: string): ButtonPart {
  const box = normalized(node.box, window);
  return { left: box.left, top: box.top, right: box.right, bottom: box.bottom, role: role, text: text, type: (node.a.type ?? '').slice(0, 80) };
}
function layerFor(node: ExperienceNode, window: Rect, role: string): ProfileLayer {
  const box = normalized(node.box, window);
  return { left: box.left, top: box.top, right: box.right, bottom: box.bottom, role: role, type: (node.a.type ?? '').slice(0, 80) };
}
export function capturedShape(a: Record<string, string>, box: Rect): string {
  // A square bounding box is not proof of a circle. Only explicit attributes
  // are accepted; unsupported/absent properties retain the rounded fallback.
  const declared = (a.shape ?? a.buttonType ?? a.type ?? '').toLowerCase();
  if (['circle', 'buttontype.circle'].includes(declared)) { return 'circle'; }
  if (declared === 'ellipse') { return 'ellipse'; }
  if (['capsule', 'buttontype.capsule'].includes(declared)) { return 'capsule'; }
  if (['rounded', 'roundedrectangle'].includes(declared)) { return 'rounded'; }
  if (declared === 'rectangle') { return 'rectangle'; }
  if (declared === 'borderless') { return 'borderless'; }
  const radius = a.borderRadius ?? a.radius ?? '';
  if (/^\d+(\.\d+)?(px)?$/.test(radius)) {
    const value = parseFloat(radius);
    if (value === 0) { return 'rectangle'; }
    if (value >= Math.min(box.right - box.left, box.bottom - box.top) / 2) { return 'capsule'; }
    return 'rounded';
  }
  return 'unknown';
}
export function captureProfile(rule: LearnedRule, target: ExperienceNode, label: ExperienceNode,
  nodes: ExperienceNode[], window: Rect, progress?: ExperienceNode, markerSource: string = '',
  markerBox?: Rect, approved?: LearnedRule, sibling: boolean = false): RecognitionProfile {
  const p = new RecognitionProfile();
  p.button = normalized(target.box, window); p.shape = capturedShape(target.a, target.box);
  p.shapeSource = p.shape === 'unknown' ? 'fallback' : 'attribute';
  p.targetMode = rule.origin === 'manual' ? 'manual' : rule.recognition === 'semantic' ? 'semantic' : sibling ? 'sibling' : target !== label ? 'parent' : 'direct';
  let scope = target;
  for (let depth = 0; depth < 3 && scope.parent; depth++) {
    const parent = scope.parent;
    if (!inside(target.box, parent.box) || parent.box.right - parent.box.left > (window.right - window.left) * 0.35 ||
      parent.box.bottom - parent.box.top > (window.bottom - window.top) * 0.12) { break; }
    scope = parent;
  }
  const local = nodes.filter((n: ExperienceNode) => beneath(n, scope) && inside(n.box, window) && inside(n.box, scope.box) && n.a.enabled !== 'false').slice(0, 128);
  // Retain only action/countdown copy, not unrelated page text. Coordinates
  // preserve reading order even when the tree enumerates children backwards.
  const visibleText = (n: ExperienceNode): string => {
    const raw = n.a.text || n.a.originalText || '';
    // Custom button words have already passed the recognizer. Only the actual
    // selected label may retain them; surrounding nodes remain allowlisted.
    return n === label && (rule.labelSource === 'text' || rule.origin === 'manual') && raw.length <= 64 ? raw.trim() : safeButtonText(raw);
  };
  const texts = local.filter((n: ExperienceNode) => !!visibleText(n));
  for (const n of texts) {
    const value = visibleText(n);
    if (/^[0-9０-９]+$/.test(value) && (value.length > 2 || Number(value) > 60)) { continue; }
    const descendants = texts.filter((child: ExperienceNode) => child !== n && beneath(child, n));
    if (descendants.length && descendants.map((child: ExperienceNode) => child.a.text || child.a.originalText || '').join('').replace(/\s/g, '') === value.replace(/\s/g, '')) { continue; }
    const duplicate = p.parts.some((part: ButtonPart) => part.text === value &&
      Math.abs(part.left - normalized(n.box, window).left) < 0.001 && Math.abs(part.top - normalized(n.box, window).top) < 0.001);
    if (!duplicate && p.parts.length < 9) { p.parts.push(partFor(n, window, /^(?:[0-9０-９]{1,2})(?:\s*(?:s|sec|秒))?$/i.test(value) ? 'countdown' : /^[×✕✖xX]$/.test(value) ? 'icon' : 'text', value)); }
  }
  // A description provides semantics, not visible text. Keep image buttons
  // as icons rather than drawing their accessibility description as a label.
  if ((!p.parts.some((part: ButtonPart) => part.role !== 'countdown') && !visibleText(label)) || /Image|Symbol/.test(label.a.type ?? '')) {
    const visual = dismissImageTarget(target, nodes, window) ?? label;
    p.parts.push(partFor(visual, window, 'icon', /关闭|×/.test(rule.label) ? '×' : ''));
    if (visual !== label) { p.button = normalized(visual.box, window); }
  }
  if (progress && inside(progress.box, window)) {
    const w = progress.box.right - progress.box.left; const h = progress.box.bottom - progress.box.top;
    const style = w / h >= 0.75 && w / h <= 1.33 ? 'ring' : 'linear';
    p.parts.unshift(partFor(progress, window, 'progress', style));
  }
  // Circle stacks describe the outline, not proof that an ad timer is running.
  // Keep that distinction from a real Progress control in evidence/strategy.
  const circle = !progress ? local.find((n: ExperienceNode) => n.a.type === 'Circle' &&
    n.a.clickable !== 'true' && inside(label.box, n.box) &&
    (n.box.right - n.box.left) / (n.box.bottom - n.box.top) >= 0.85 &&
    (n.box.right - n.box.left) / (n.box.bottom - n.box.top) <= 1.18) : undefined;
  if (circle) { p.parts.unshift(partFor(circle, window, 'outline', 'ring')); }
  const ring = p.parts.find((part: ButtonPart) => ['progress', 'outline'].includes(part.role) && part.text === 'ring');
  if (ring && p.parts.every((part: ButtonPart) => part === ring || part.role === 'outline' || inside(part, ring))) {
    p.shape = 'circle'; p.shapeSource = 'attribute'; p.button = { left: ring.left, top: ring.top, right: ring.right, bottom: ring.bottom };
  }
  p.parts.sort((a: ButtonPart, b: ButtonPart) => a.role === 'progress' ? -1 : b.role === 'progress' ? 1 :
    Math.abs((a.top + a.bottom - b.top - b.bottom) / 2) < Math.min(a.bottom - a.top, b.bottom - b.top) * 0.5 ? a.left - b.left : a.top - b.top);
  p.content = contentKind(p.parts);
  const textCountdown = hasSkipCountdown(rule.example) || p.parts.some((part: ButtonPart) => part.role === 'countdown' || isCountdownText(part.text));
  if (rule.marker === 'label') { p.evidence.push('explicit-action'); }
  if (markerSource && !['approved-button', 'image-memory'].includes(markerSource)) { p.evidence.push(markerSource === 'image-ocr' ? 'image-ocr' : markerSource === 'splash-id' ? 'structure' : 'ad-marker'); }
  if (textCountdown) { p.evidence.push('text-countdown'); }
  if (progress) { p.evidence.push('graphical-countdown'); }
  if (rule.labelSource === 'description') { p.evidence.push('description'); }
  if (rule.labelSource === 'id' || rule.marker === 'control-id') { p.evidence.push('control-id'); }
  if (rule.labelSource === 'structure') { p.evidence.push('structure'); }
  if (rule.origin === 'manual') { p.evidence.push('manual-click'); }
  p.evidence = p.evidence.filter((s: string, i: number) => p.evidence.indexOf(s) === i);
  p.strategyId = rule.origin === 'manual' ? 'S08' : markerSource === 'image-ocr' && (rule.marker !== 'label' || rule.recognition === 'semantic') ? 'S07' :
    rule.labelSource === 'structure' || markerSource === 'splash-id' ? 'S06' :
    rule.labelSource === 'id' || rule.marker === 'control-id' || rule.labelSource === 'description' && /Image|Symbol/.test(label.a.type ?? '') ? 'S05' :
    rule.marker === 'label' ? 'S01' : ['countdown', 'close-countdown'].includes(rule.marker) ? (progress && !textCountdown ? 'S04' : 'S03') : 'S02';
  if (approved) {
    p.strategyId = ruleStrategyId(approved);
    if (validProfile(approved.profile)) {
      p.evidence = approved.profile!.evidence;
      if (p.shape === 'unknown') { p.shape = approved.profile!.shape; p.shapeSource = approved.profile!.shapeSource; }
    }
  }
  p.layers.push(layerFor(target, window, 'target'));
  if (label !== target) { p.layers.push(layerFor(label, window, 'label')); }
  let parent = target.parent;
  for (let depth = 0; parent && depth < 3; depth++, parent = parent.parent) {
    if (inside(parent.box, window)) { p.layers.push(layerFor(parent, window, 'container')); }
  }
  if (progress && inside(progress.box, window)) { p.layers.push(layerFor(progress, window, 'progress')); }
  if (markerBox && inside(markerBox, window) && markerSource !== 'approved-button') {
    const box = normalized(markerBox, window);
    p.layers.push({ left: box.left, top: box.top, right: box.right, bottom: box.bottom, role: 'ad-layer', type: markerSource === 'image-ocr' ? 'Image' : 'AdEvidence' });
  }
  for (const n of local.filter((n: ExperienceNode) => /Image/.test(n.a.type ?? '') || p.parts.some((part: ButtonPart) => part.role === 'countdown' && part.left === normalized(n.box, window).left && part.top === normalized(n.box, window).top)).slice(0, 3)) {
    if (n !== target && n !== label) { p.layers.push(layerFor(n, window, /Image/.test(n.a.type ?? '') ? 'image' : 'countdown')); }
  }
  return p;
}
