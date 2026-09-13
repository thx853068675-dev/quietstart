'use strict';

// These rules are deliberately limited to the two splash layouts inspected on Pura X.
const TARGETS = Object.freeze({
  huya: Object.freeze({ bundle: 'com.duowan.hyhos', rule: 'huya-skipButton-topAdText-v1' }),
  youku: Object.freeze({ bundle: 'com.youku.next', rule: 'youku-oneadbiz-countdown-v1' })
});

function bounds(value) {
  if (typeof value !== 'string') return null;
  const match = /^\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]$/.exec(value);
  if (!match) return null;
  const [left, top, right, bottom] = match.slice(1).map(Number);
  if (![left, top, right, bottom].every(Number.isSafeInteger) || right <= left || bottom <= top) return null;
  return { left, top, right, bottom, width: right - left, height: bottom - top };
}

function integer(value) {
  if (!/^\d+$/.test(String(value))) return null;
  const result = Number(value);
  return Number.isSafeInteger(result) ? result : null;
}

function inside(rect, outer) {
  return rect && outer && rect.left >= outer.left && rect.top >= outer.top &&
    rect.right <= outer.right && rect.bottom <= outer.bottom;
}

function visible(node) {
  const a = node.attributes || {};
  return a.visible === 'true' && a.enabled === 'true' && a.hitTestBehavior !== 'HitTestMode.None' &&
    (a.opacity === undefined || a.opacity === '' || Number(a.opacity) > 0);
}

function nodeViews(root) {
  const views = [];
  function visit(node, parents) {
    if (!node || typeof node !== 'object' || !node.attributes) return;
    views.push({ node, parents });
    for (const child of node.children || []) visit(child, parents.concat(node));
  }
  visit(root, []);
  return views;
}

function isSafeButton(rect, windowRect) {
  if (!inside(rect, windowRect)) return false;
  return rect.left >= windowRect.left + windowRect.width * 0.55 &&
    rect.bottom <= windowRect.top + windowRect.height * 0.3 &&
    rect.width <= windowRect.width * 0.35 && rect.height <= windowRect.height * 0.15 &&
    rect.width >= 8 && rect.height >= 8;
}

function findCandidate(layout, targetName) {
  const target = TARGETS[targetName];
  if (!target) return null;
  const allViews = nodeViews(layout);
  const roots = allViews.filter(({ node }) => node.attributes.type === 'root' &&
    node.attributes.bundleName === target.bundle);
  if (roots.length !== 1 || !visible(roots[0].node)) return null;
  const root = roots[0].node;
  const rootAttributes = root.attributes;
  const windowRect = bounds(rootAttributes.bounds);
  const windowId = integer(rootAttributes.hostWindowId);
  const displayId = integer(rootAttributes.displayId);
  // External displays and other window configurations have not been validated.
  if (!windowRect || !windowId || displayId !== 0) return null;
  const views = nodeViews(root);
  function belongs(view) {
    return [view.node, ...view.parents].every(node => {
      const a = node.attributes;
      return visible(node) && (!a.bundleName || a.bundleName === target.bundle) &&
        integer(a.hostWindowId) === windowId && integer(a.displayId) === displayId;
    });
  }
  const markerFound = views.some(view => {
    const a = view.node.attributes;
    if (!belongs(view) || !inside(bounds(a.bounds), windowRect)) return false;
    return targetName === 'huya'
      ? a.id === 'topAdText' && /^广告(?:[｜|].*)?$/.test(a.text)
      : a.id === 'oneadbiz_splash_logo';
  });
  if (!markerFound) return null;
  const candidates = [];
  for (const view of views) {
    const a = view.node.attributes;
    if (a.text !== (targetName === 'huya' ? '跳过' : '跳过广告') || !belongs(view)) continue;
    let clickNode;
    if (targetName === 'huya') {
      if (!view.parents.slice(-3).some(node => node.attributes.id === 'skipButton')) continue;
      if (a.clickable !== 'true') continue;
      clickNode = view.node;
    } else {
      clickNode = view.parents.slice(-2).find(node => node.attributes.id === 'oneadbiz_ad_countdown' &&
        node.attributes.clickable === 'true');
      if (!clickNode) continue;
    }
    const textRect = bounds(a.bounds);
    const clickRect = bounds(clickNode.attributes.bounds);
    if (!isSafeButton(clickRect, windowRect) || !inside(textRect, clickRect)) continue;
    const nodeId = integer(a.accessibilityId);
    const clickNodeId = integer(clickNode.attributes.accessibilityId);
    if (nodeId === null || clickNodeId === null) continue;
    candidates.push({ bundle: target.bundle, rule: target.rule, windowId, displayId,
      nodeId, clickNodeId, windowRect,
      x: Math.floor((textRect.left + textRect.right) / 2),
      y: Math.floor((textRect.top + textRect.bottom) / 2) });
  }
  // Ambiguous duplicate controls are never resolved by guessing their position.
  return candidates.length === 1 ? candidates[0] : null;
}

// This format is documented by Huawei's hidumper guide and observed on the user's API 26 phone.
// https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hidumper
function parseWindowManager(text) {
  if (typeof text !== 'string' || !/^WindowName\s+DisplayId\s+Pid\s+WinId\s+Type\s+Mode\s+Flag\s+ZOrd\s+Orientation\s+/m.test(text)) return null;
  const focusLines = [...text.matchAll(/^Focus window:\s*(\d+)\s*$/gm)];
  if (focusLines.length !== 1) return null;
  const focusedWindowId = integer(focusLines[0][1]);
  if (!focusedWindowId) return null;
  const displayFocus = [...text.matchAll(/^DisplayId:\s*(\d+)\s+WindowId:\s*(\d+)\s*$/gm)];
  if (displayFocus.length !== 1 || integer(displayFocus[0][1]) !== 0 ||
      integer(displayFocus[0][2]) !== focusedWindowId) return null;
  const singleHand = /^SingleHand:\s*X\[([^\]]+)\]\s*Y\[([^\]]+)\]\s*scale\[([^\]]+)\]\s*$/m.exec(text);
  if (!singleHand || Number(singleHand[1]) !== 0 || Number(singleHand[2]) !== 0 || Number(singleHand[3]) !== 1) return null;
  const windows = [];
  for (const line of text.split('\n')) {
    const m = /^(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(-?\d+)\s+(\d+)\s+\[\s*(-?\d+)\s+(-?\d+)\s+(\d+)\s+(\d+)\s*\]\s+\[\s*(-?[\d.]+)\s+(-?[\d.]+)\s*\]\s+\[\s*([\d.]+)\s+([\d.]+)\s+[\d.]+\s+[\d.]+\s*\]\s*$/.exec(line);
    if (!m) continue;
    const values = m.slice(2).map(Number);
    const [displayId, pid, id, type, mode, flag, zOrder, orientation, left, top, width, height,
      offsetX, offsetY, scaleX, scaleY] = values;
    if (!values.every(Number.isFinite)) return null;
    windows.push({ displayId, pid, id, type, mode, flag, zOrder, orientation, offsetX, offsetY, scaleX, scaleY,
      rect: { left, top, right: left + width, bottom: top + height, width, height } });
  }
  const focused = windows.filter(window => window.id === focusedWindowId);
  if (focused.length !== 1) return null;
  return { focusedWindowId, focused: focused[0] };
}

function isForeground(candidate, windowManager) {
  if (!candidate || !windowManager) return false;
  const w = windowManager.focused;
  return w.id === candidate.windowId && w.displayId === candidate.displayId &&
    w.type === 1 && w.mode === 1 && w.zOrder >= 0 &&
    w.offsetX === 0 && w.offsetY === 0 && w.scaleX === 1 && w.scaleY === 1 &&
    candidate.x >= w.rect.left && candidate.x < w.rect.right &&
    candidate.y >= w.rect.top && candidate.y < w.rect.bottom;
}

function sameCandidate(a, b) {
  return !!a && !!b && a.bundle === b.bundle && a.rule === b.rule && a.windowId === b.windowId &&
    a.displayId === b.displayId && a.nodeId === b.nodeId && a.clickNodeId === b.clickNodeId;
}

function verifyControlGone(layout, candidate) {
  const roots = nodeViews(layout).filter(({ node }) => node.attributes.type === 'root' &&
    node.attributes.bundleName === candidate.bundle && integer(node.attributes.hostWindowId) === candidate.windowId);
  if (roots.length !== 1) return null;
  return !nodeViews(roots[0].node).some(({ node }) => integer(node.attributes.hostWindowId) === candidate.windowId &&
    integer(node.attributes.accessibilityId) === candidate.nodeId && node.attributes.visible === 'true');
}

module.exports = { TARGETS, bounds, findCandidate, parseWindowManager, isForeground, sameCandidate, verifyControlGone };
