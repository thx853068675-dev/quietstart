import { Rect } from '@kit.TestKit';
import { skipLabel } from '../../../main/ets/core/LearningStore';

export interface SnapshotNode {
  attributes?: Record<string, string>;
  children?: SnapshotNode[];
}
// UiTest's Android bridge uses an Android view as the window root and reports
// zero opacity even for visible views. Normalize only a verified bridge window.
export function normalizeSnapshotTrees(trees: SnapshotNode[]): void {
  let count = 0;
  const visit = (node: SnapshotNode, depth: number, bridgeWindow: string = ''): void => {
    if (!node || depth > 128 || ++count > 20000) { return; }
    const a = node.attributes;
    if (!a) { return; }
    let window = bridgeWindow;
    if (/^android\./.test(a.type ?? '') && a.bundleName && /^\d+$/.test(a.hostWindowId ?? '') &&
      a.hierarchy === 'ROOT' + a.hostWindowId && snapshotBounds(a.origBounds) && snapshotBounds(a.bounds)) {
      window = a.hostWindowId;
      a.type = 'root';
      a.quietstartRuntime = 'android';
    }
    if (window && a.hostWindowId === window) {
      // Android visible is supplied by the bridge; native ArkUI alpha stays strict.
      a.opacity = '';
    } else if (window) { window = ''; }
    for (const child of node.children ?? []) { visit(child, depth + 1, window); }
  };
  for (const tree of trees) { visit(tree, 0); }
}
export function snapshotImage(type: string): boolean {
  return type === 'Image' || type === 'android.widget.ImageView';
}

// A local structural fingerprint, independent of transient window IDs and ad artwork.
// Hash non-action text so the cache never stores page copy or personal text.
export function imageLayoutSignature(text: string, region?: Rect): string {
  if (!text || text.length > 8 * 1024 * 1024) { return ''; }
  const parts: string[] = [];
  let valid = true; let count = 0;
  const visit = (node: SnapshotNode, depth: number): void => {
    if (!node || depth > 128 || ++count > 20000) { valid = false; return; }
    const a = node.attributes ?? {};
    const raw = (a.text || a.originalText || '') + '|' + (a.description || '');
    let hash = 2166136261;
    for (let i = 0; i < raw.length; i++) { hash = Math.imul(hash ^ raw.charCodeAt(i), 16777619); }
    parts.push(JSON.stringify([depth, a.type, a.bounds, a.origBounds, a.bundleName, a.pagePath,
      a.id, a.visible, a.enabled, a.clickable, Number(a.opacity ?? 1) > 0, skipLabel(raw) || String(hash), (node.children ?? []).length]));
    for (const child of node.children ?? []) { visit(child, depth + 1); }
  };
  try {
    const parsed = JSON.parse(text) as SnapshotNode | SnapshotNode[];
    const trees = Array.isArray(parsed) ? parsed : [parsed];
    normalizeSnapshotTrees(trees);
    if (region) {
      let scope: SnapshotNode | undefined;
      let owner: SnapshotNode | undefined;
      let ambiguous = false;
      const locate = (node: SnapshotNode, ancestors: SnapshotNode[], depth: number): void => {
        if (!node || depth > 128 || ++count > 20000) { valid = false; return; }
        const box = snapshotBounds(node.attributes?.bounds ?? '');
        if ((snapshotImage(node.attributes?.type ?? '') || node.attributes?.clickable === 'true') && box && box.left === region.left && box.top === region.top &&
          box.right === region.right && box.bottom === region.bottom) {
          const root = ancestors.find((item: SnapshotNode) => item.attributes?.type === 'root');
          const window = snapshotBounds(root?.attributes?.bounds ?? '');
          if (root && window) {
            const layers = ancestors.concat([node]);
            for (let i = layers.length - 1; i >= 0; i--) {
              const layer = layers[i]; const a = layer.attributes ?? {}; const bounds = snapshotBounds(a.bounds);
              if (a.clickable === 'true' && a.enabled === 'true' && bounds &&
                bounds.right - bounds.left >= (window.right - window.left) * 0.8 &&
                bounds.bottom - bounds.top >= (window.bottom - window.top) * 0.8) {
                if (scope && scope !== layer) { ambiguous = true; }
                scope = layer; owner = root; break;
              }
            }
          }
        }
        for (const child of node.children ?? []) { locate(child, ancestors.concat([node]), depth + 1); }
      };
      for (const root of trees) { locate(root, [], 0); }
      if (!valid || ambiguous || !scope || !owner) { return ''; }
      const a = owner.attributes ?? {};
      parts.push(JSON.stringify(['splash-v2', a.bundleName, a.pagePath, a.bounds, a.origBounds]));
      count = 0; visit(scope, 0);
    } else {
      for (const root of trees) { visit(root, 0); }
    }
  } catch (_) { return ''; }
  const result = parts.join('\n');
  return valid && result.length <= 64000 ? result : '';
}

export function snapshotBounds(value: string): Rect | undefined {
  if (typeof value !== 'string') { return undefined; }
  const match = /^\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]$/.exec(value);
  if (!match) { return undefined; }
  const box: Rect = { left: Number(match[1]), top: Number(match[2]), right: Number(match[3]), bottom: Number(match[4]) };
  return box.right > box.left && box.bottom > box.top ? box : undefined;
}
