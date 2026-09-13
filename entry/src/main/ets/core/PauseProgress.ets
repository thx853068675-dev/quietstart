import { AdFreeEntry, CLEAN_GAP_MS } from './AdFreeStore';

export class PauseProgress {
  progress: string = '';
  remaining: string = '';
}
function duration(ms: number): string {
  const minutes = Math.max(1, Math.ceil(ms / 60000));
  if (minutes < 60) { return minutes + ' 分钟'; }
  if (minutes < 1440) { return Math.ceil(minutes / 60) + ' 小时'; }
  return Math.ceil(minutes / 1440) + ' 天';
}
// Wall time alone never admits an app: the worker must complete another clean check.
export function pauseProgress(entry: AdFreeEntry | undefined, days: number, checks: number, now: number): PauseProgress {
  const result = new PauseProgress();
  const count = entry?.cleanLaunches ?? 0;
  const missing = Math.max(0, checks - count);
  result.progress = '有效检查 ' + Math.min(count, checks) + '/' + checks + ' 次';
  if (!entry || count === 0) {
    result.remaining = '还需 ' + checks + ' 次；首次有效检查后观察 ' + days + ' 天';
    return result;
  }
  const wait = Math.max(0, entry.firstCleanAt + days * 86400000 - now);
  const cooldown = Math.max(0, entry.lastCleanAt + CLEAN_GAP_MS - now);
  result.progress += wait > 0 ? ' · 时长未满' : ' · 时长已满';
  result.remaining = missing > 0 ? '还需 ' + missing + ' 次完整检查' : '还需 1 次完整检查确认';
  if (wait > 0) { result.remaining += ' · 距观察期满 ' + duration(wait); }
  else if (cooldown > 0) { result.remaining += ' · ' + duration(cooldown) + '后可再次计数'; }
  else { result.remaining += ' · 下次打开继续'; }
  return result;
}
