import { fileIo as fs } from '@kit.CoreFileKit';
import { discoverableBundle } from './LearningStore';
import { Settings } from './LocalStore';

export const CLEAN_STABLE_MS: number = 6000;
export const CLEAN_GAP_MS: number = 30 * 60 * 1000;
const DAY_MS: number = 24 * 60 * 60 * 1000;
export class AdFreeEntry {
  bundle: string = '';
  cleanLaunches: number = 0;
  firstCleanAt: number = 0;
  lastCleanAt: number = 0;
  pausedUntil: number = 0;
  updatedAt: number = 0;
}

// Worker owns observations; UI owns overrides. A manual release cannot be
// overwritten by a worker that was still saving an earlier launch's result.
export class AdFreeStore {
  private directory: string;
  constructor(directory: string) { this.directory = directory; }
  private overrides(): Record<string, number> {
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/ad-free-overrides.json')) as Record<string, number>;
      if (!raw || Array.isArray(raw) || typeof raw !== 'object') { return {}; }
      return raw;
    } catch (_) { return {}; }
  }
  read(settings?: Settings): AdFreeEntry[] {
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/ad-free-observations.json')) as AdFreeEntry[];
      const overrides = this.overrides();
      return Array.isArray(raw) ? raw.filter((x: AdFreeEntry) => x && discoverableBundle(x.bundle) &&
        [x.cleanLaunches, x.firstCleanAt, x.lastCleanAt, x.pausedUntil, x.updatedAt].every((n: number) => Number.isFinite(n) && n >= 0) &&
        x.updatedAt > (overrides[x.bundle] ?? 0)).slice(0, 1000).map((x: AdFreeEntry) => {
          // Only previously admitted entries can remain paused. Lowering the
          // threshold never admits an observed app without another full check.
          if (settings && x.pausedUntil > 0) {
            x.pausedUntil = x.cleanLaunches >= settings.adFreeCleanChecks &&
              x.lastCleanAt - x.firstCleanAt >= settings.adFreeMinDays * DAY_MS ?
              x.lastCleanAt + settings.adFreeRecheckDays * DAY_MS : 0;
          }
          return x;
        }) : [];
    } catch (_) { return []; }
  }
  paused(bundle: string, now: number = Date.now(), settings: Settings = new Settings()): boolean {
    return this.read(settings).some((x: AdFreeEntry) => x.bundle === bundle && x.pausedUntil > now && x.updatedAt <= now);
  }
  release(bundle: string): void {
    if (!discoverableBundle(bundle)) { return; }
    const overrides = this.overrides();
    overrides[bundle] = Math.max(Date.now(), (overrides[bundle] ?? 0) + 1);
    this.write('ad-free-overrides.json', JSON.stringify(overrides));
  }
  evidence(bundle: string): void {
    const rows = this.read();
    if (!rows.some((x: AdFreeEntry) => x.bundle === bundle)) { return; }
    this.write('ad-free-observations.json', JSON.stringify(rows.filter((x: AdFreeEntry) => x.bundle !== bundle)));
  }
  completeCleanLaunch(bundle: string, startedAt: number, settings: Settings = new Settings()): boolean {
    const now = Date.now();
    if (!discoverableBundle(bundle) || now - startedAt < CLEAN_STABLE_MS || startedAt <= (this.overrides()[bundle] ?? 0)) { return false; }
    const rows = this.read(settings);
    let row = rows.find((x: AdFreeEntry) => x.bundle === bundle);
    if (row && now < row.lastCleanAt) { return false; }
    if (row && now - row.lastCleanAt < CLEAN_GAP_MS) { return false; }
    if (!row) { row = new AdFreeEntry(); row.bundle = bundle; row.firstCleanAt = now; rows.unshift(row); }
    // Expired entries undergo a complete current check before being paused again.
    row.cleanLaunches = Math.min(20, row.cleanLaunches + 1); row.lastCleanAt = now; row.updatedAt = now;
    if (row.cleanLaunches >= settings.adFreeCleanChecks && now - row.firstCleanAt >= settings.adFreeMinDays * DAY_MS) { row.pausedUntil = now + settings.adFreeRecheckDays * DAY_MS; }
    this.write('ad-free-observations.json', JSON.stringify(rows.slice(0, 1000)));
    return row.pausedUntil > now;
  }
  private write(name: string, value: string): void {
    const path = this.directory + '/' + name;
    const file = fs.openSync(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, value); } finally { fs.closeSync(file); }
    fs.renameSync(path + '.tmp', path);
  }
}
