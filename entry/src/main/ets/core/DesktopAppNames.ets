interface DesktopNode {
  attributes?: Record<string, string>;
  children?: DesktopNode[];
}

// Use the launcher's icon identity and its own caption, never arbitrary page text.
export function desktopAppNames(text: string, bundles: string[]): Record<string, string> {
  const result: Record<string, string> = {};
  if (!text || text.length > 8 * 1024 * 1024) { return result; }
  let count = 0;
  const visible = (a: Record<string, string>): boolean => a.visible === 'true' &&
    (a.opacity === undefined || a.opacity === '' || Number(a.opacity) > 0);
  const visit = (node: DesktopNode, depth: number, desktop: boolean = false): void => {
    if (!node || depth > 64 || ++count > 20000) { throw new Error('Invalid desktop tree'); }
    const a = node.attributes ?? {};
    if (a.bundleName) { desktop = a.bundleName === 'com.ohos.sceneboard' && visible(a); }
    if (desktop && !visible(a)) { return; }
    const prefix = 'Container_AppIcon_Image_';
    if (desktop && (a.id ?? '').startsWith(prefix)) {
      const identity = a.id.substring(prefix.length);
      const matches = bundles.filter((bundle: string) => identity.startsWith(bundle) &&
        (/^[A-Z_]/.test(identity.substring(bundle.length)) || /^(com|org|net|cn)\./.test(identity.substring(bundle.length))));
      if (matches.length === 1) {
        const captions: string[] = [];
        const caption = (child: DesktopNode, level: number): void => {
          if (level > 4 || ++count > 20000) { return; }
          const c = child.attributes ?? {};
          if (!visible(c)) { return; }
          if (c.type === 'Text' && c.text?.trim() && c.text.length <= 80 && !/[\r\n]/.test(c.text)) { captions.push(c.text.trim()); }
          for (const item of child.children ?? []) { caption(item, level + 1); }
        };
        for (const child of node.children ?? []) { caption(child, 0); }
        // Badges and extra captions are ambiguous, so leave them unresolved.
        if (captions.length === 1 && captions[0] !== matches[0]) { result[matches[0]] = captions[0]; }
      }
      return;
    }
    for (const child of node.children ?? []) { visit(child, depth + 1, desktop); }
  };
  try {
    const parsed = JSON.parse(text) as DesktopNode | DesktopNode[];
    for (const tree of Array.isArray(parsed) ? parsed : [parsed]) { visit(tree, 0); }
  } catch (_) { return {}; }
  return result;
}

