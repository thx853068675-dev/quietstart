import { Rect } from '@kit.TestKit';
import { isSkipRegion } from '../../../main/ets/core/LearningStore';

export const ENTRY_WINDOW_MS: number = 12000;
export const MAX_RUN_SECONDS: number = 43200;

export function isSplashButton(button: Rect, window: Rect): boolean {
  const width: number = window.right - window.left;
  const height: number = window.bottom - window.top;
  return width > 0 && height > 0 && isSkipRegion((button.left - window.left) / width,
    (button.top - window.top) / height, (button.right - window.left) / width, (button.bottom - window.top) / height);
}

// Keep the first seconds responsive, then reduce expensive tree reads.
export function scanInterval(elapsedMs: number): number {
  return elapsedMs < 3000 ? 60 : (elapsedMs < 6000 ? 250 : 750);
}
