import { LearningStore } from './LearningStore';
import { LocalActivation } from './LocalActivation';

// A separate local HDC connection; never await this in the UiTest scan path.
export class AppNameResolver {
  private nextTick: number = 0;
  private busy: boolean = false;
  private attempts: Record<string, number> = {};
  private counts: Record<string, number> = {};
  private client?: LocalActivation;
  private closed: boolean = false;
  private directory: string;
  constructor(directory: string) { this.directory = directory; }
  requestSoon(): void { this.nextTick = 0; }
  tick(): void {
    if (this.busy || this.closed || Date.now() < this.nextTick) { return; }
    this.nextTick = Date.now() + 1500;
    const store = new LearningStore(this.directory);
    const android = store.androidApps();
    const app = store.missingAppNames().find((item) => !android.includes(item.bundleName) &&
      (this.counts[item.bundleName] || 0) < 3 && Date.now() - (this.attempts[item.bundleName] || 0) > 60000);
    if (!app) { this.nextTick = Date.now() + 30000; return; }
    this.busy = true; this.attempts[app.bundleName] = Date.now();
    this.counts[app.bundleName] = (this.counts[app.bundleName] || 0) + 1;
    this.client = new LocalActivation(this.directory);
    this.client.readAppLabel(app.bundleName).then((name: string) => {
      if (name) { store.saveAppName(app.bundleName, name); }
    }).catch(() => {}).finally(() => { this.busy = false; });
  }
  close(): void { this.closed = true; this.client?.close(); }
}
