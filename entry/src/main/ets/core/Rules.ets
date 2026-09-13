export const OWN_BUNDLE: string = 'com.tonghongxiang.quietstart';
export const WINDOW_MS: number = 8000;
export interface Bounds { left: number; top: number; width: number; height: number; }

export function isSkipLabel(label: string): boolean {
  const text: string = label.trim().replace(/\s+/g, '').toLowerCase();
  return /^(跳过(广告)?|skip(ad)?)([（(]?\d{1,2}(s|秒)?[）)]?)?$/.test(text) ||
    /^\d{1,2}(s|秒)?[|｜·]?跳过(广告)?$/.test(text);
}

export function isSafePosition(button: Bounds, screen: Bounds): boolean {
  if (screen.width <= 0 || screen.height <= 0 || button.width <= 0 || button.height <= 0) { return false; }
  const x: number = button.left + button.width / 2;
  const y: number = button.top + button.height / 2;
  return button.left >= screen.left && button.top >= screen.top &&
    button.left + button.width <= screen.left + screen.width + 1 &&
    button.top + button.height <= screen.top + screen.height + 1 &&
    x >= screen.left + screen.width * 0.55 && y <= screen.top + screen.height * 0.30 &&
    button.width <= screen.width * 0.42 && button.height <= screen.height * 0.15;
}

export function parsePackages(text: string): string[] {
  const result: string[] = [];
  text.split(/[\s,，;；]+/).forEach((value: string) => {
    if (/^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/.test(value) && !result.includes(value)) { result.push(value); }
  });
  return result;
}

export function hasCountdown(label: string): boolean {
  return isSkipLabel(label) && /\d/.test(label);
}
