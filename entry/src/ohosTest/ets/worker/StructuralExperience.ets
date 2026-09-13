import { Rect } from '@kit.TestKit';
import { hasSkipCountdown, isCountdownText, controlIdLabel } from '../../../main/ets/core/LearningStore';
import { isSplashButton } from './Rules';

export class ExperienceNode {
  a: Record<string, string>;
  box: Rect;
  parent?: ExperienceNode;
  order: number;
  constructor(a: Record<string, string>, box: Rect, order: number, parent?: ExperienceNode) {
    this.a = a; this.box = box; this.order = order; this.parent = parent;
  }
}
function covers(a: Rect, b: Rect): boolean {
  return a.left <= b.left && a.top <= b.top && a.right >= b.right && a.bottom >= b.bottom;
}
function smallGroup(node: ExperienceNode, window: Rect): boolean {
  return node.box.right - node.box.left <= (window.right - window.left) * 0.35 &&
    node.box.bottom - node.box.top <= (window.bottom - window.top) * 0.12;
}
function image(node: ExperienceNode): boolean {
  return ['Image', 'android.widget.ImageView'].includes(node.a.type ?? '');
}
function actionable(node: ExperienceNode, window: Rect): boolean {
  if (node.a.enabled !== 'true' || node.a.clickable !== 'true' ||
    node.a.hitTestBehavior === 'HitTestMode.None' || !isSplashButton(node.box, window)) { return false; }
  for (let p = node.parent; p; p = p.parent) { if (p.a.enabled === 'false') { return false; } }
  return true;
}
export function splashContainer(node: ExperienceNode, window: Rect): ExperienceNode | undefined {
  for (let p = node.parent; p; p = p.parent) {
    const words = (p.a.id ?? '').replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase().split(/[^a-z0-9]+/);
    if (words.includes('splash') && words.some((word: string) => ['container', 'view', 'ad'].includes(word)) &&
      p.box.right - p.box.left >= (window.right - window.left) * 0.8 &&
      p.box.bottom - p.box.top >= (window.bottom - window.top) * 0.6 && covers(p.box, node.box)) { return p; }
  }
  return undefined;
}

// Select the front image, never the underlying clickable countdown label.
// Without z metadata, sibling paint order must establish the image is on top.
export function overlayDismissTarget(node: ExperienceNode, nodes: ExperienceNode[], window: Rect): ExperienceNode | undefined {
  const group = hasSkipCountdown(node.a.text) || hasSkipCountdown(node.a.description) ? node.parent :
    controlIdLabel(node.a.id) ? node : undefined;
  if (!group || !smallGroup(group, window)) { return undefined; }
  const labels = nodes.filter((n: ExperienceNode) => n.parent === group &&
    (hasSkipCountdown(n.a.text) || hasSkipCountdown(n.a.description)));
  if (labels.length !== 1) { return undefined; }
  const label = labels[0];
  const targets = nodes.filter((n: ExperienceNode) => n.parent === group && image(n) && actionable(n, window) &&
    !n.a.text && !n.a.description && n.order > label.order &&
    Number(n.a.zIndex || '0') >= Number(label.a.zIndex || '0') &&
    n.box.left === label.box.left && n.box.top === label.box.top &&
    n.box.right === label.box.right && n.box.bottom === label.box.bottom);
  return targets.length === 1 ? targets[0] : undefined;
}

export function structuralAction(node: ExperienceNode, nodes: ExperienceNode[], window: Rect): string {
  if (!actionable(node, window) || node.a.text || node.a.description) { return ''; }
  const group = node.parent;
  if (image(node) && group && smallGroup(group, window)) {
    const timers = nodes.filter((n: ExperienceNode) => n.parent === group && n !== node &&
      (hasSkipCountdown(n.a.text) || hasSkipCountdown(n.a.description) || isCountdownText(n.a.text) || isCountdownText(n.a.description)));
    if (timers.length === 1) {
      const timer = timers[0];
      const dx = Math.max(0, timer.box.left - node.box.right, node.box.left - timer.box.right);
      const overlapY = timer.box.top < node.box.bottom && timer.box.bottom > node.box.top;
      const choices = nodes.filter((n: ExperienceNode) => n.parent === group && image(n) && actionable(n, window));
      const semanticGroup = !!controlIdLabel(group.a.id) || !!splashContainer(node, window);
      if (choices.length === 1 && semanticGroup && covers(group.box, node.box) && covers(group.box, timer.box) &&
        overlapY && dx <= (window.right - window.left) * 0.06 &&
        (timer.a.clickable !== 'true' || overlayDismissTarget(timer, nodes, window) === node)) { return 'countdown-image'; }
    }
  }
  // Community SDK experience: a leaf View in a splash container corner.
  // ImageViews are deliberately excluded: the other corner can be an ad logo.
  if (['View', 'android.view.View'].includes(node.a.type ?? '') && !nodes.some((n: ExperienceNode) => n.parent === node) &&
    splashContainer(node, window)) {
    const w = window.right - window.left; const h = window.bottom - window.top;
    const bw = node.box.right - node.box.left; const bh = node.box.bottom - node.box.top;
    if (bw / bh >= 0.7 && bw / bh <= 1.4 && bw <= w * 0.15 && bh <= h * 0.1 &&
      node.box.bottom <= window.top + h * 0.2 &&
      (node.box.right <= window.left + w * 0.25 || node.box.left >= window.left + w * 0.75)) { return 'splash-corner'; }
  }
  return '';
}
