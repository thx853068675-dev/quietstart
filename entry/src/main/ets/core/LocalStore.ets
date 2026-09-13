import { fileIo as fs } from '@kit.CoreFileKit';
export class Settings {
  enabled: boolean = false;
  remindersEnabled: boolean = false;
  reminderDismissSeconds: number = 5;
  themeMode: string = 'system';
  discoverApps: boolean = true;
  ignoredPackages: string[] = [];
  packages: string[] = [];
  testUntil: number = 0;
  stopRequested: boolean = false;
  learningEnabled: boolean = true;
  autoAdFree: boolean = true;
  adFreeMinDays: number = 1;
  adFreeCleanChecks: number = 3;
  adFreeRecheckDays: number = 7;
  catalogRequestAt: number = 0;
}
export class ServiceStatus {
  connected: boolean = false;
  updatedAt: number = 0;
  lastBundle: string = '';
  lastExternalBundle: string = '';
  clickCount: number = 0;
  message: string = '尚未收到无障碍服务回调';
  history: string[] = [];
}
export class LocalStore {
  private directory: string;
  constructor(directory: string) { this.directory = directory; }
  readSettings(): Settings {
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/settings.json')) as Settings;
      const value: Settings = raw;
      value.enabled = raw.enabled === true;
      value.remindersEnabled = raw.remindersEnabled === true;
      value.reminderDismissSeconds = Number.isInteger(raw.reminderDismissSeconds) && raw.reminderDismissSeconds >= 0 &&
        raw.reminderDismissSeconds <= 60 ? raw.reminderDismissSeconds : 5;
      value.themeMode = raw.themeMode === 'light' || raw.themeMode === 'dark' ? raw.themeMode : 'system';
      value.discoverApps = raw.discoverApps !== false;
      value.ignoredPackages = Array.isArray(raw.ignoredPackages) ? raw.ignoredPackages.filter((name: string) =>
        typeof name === 'string' && /^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/.test(name)) : [];
      value.packages = Array.isArray(raw.packages) ? raw.packages.filter((name: string) =>
        typeof name === 'string' && /^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/.test(name)) : [];
      value.testUntil = Number.isFinite(raw.testUntil) ? raw.testUntil : 0;
      value.stopRequested = raw.stopRequested === true;
      value.learningEnabled = raw.learningEnabled !== false;
      value.autoAdFree = raw.autoAdFree !== false;
      value.adFreeMinDays = Number.isInteger(raw.adFreeMinDays) && raw.adFreeMinDays >= 1 && raw.adFreeMinDays <= 7 ? raw.adFreeMinDays : 1;
      value.adFreeCleanChecks = Number.isInteger(raw.adFreeCleanChecks) && raw.adFreeCleanChecks >= 2 && raw.adFreeCleanChecks <= 20 ? raw.adFreeCleanChecks : 3;
      value.adFreeRecheckDays = Number.isInteger(raw.adFreeRecheckDays) && raw.adFreeRecheckDays >= 1 && raw.adFreeRecheckDays <= 30 ? raw.adFreeRecheckDays : 7;
      value.catalogRequestAt = Number.isFinite(raw.catalogRequestAt) ? raw.catalogRequestAt : 0;
      return value;
    }
    catch (_) { return new Settings(); }
  }
  readStatus(): ServiceStatus {
    try { return JSON.parse(fs.readTextSync(this.directory + '/status.json')) as ServiceStatus; }
    catch (_) { return new ServiceStatus(); }
  }
  saveSettings(value: Settings): void { this.write('settings.json', JSON.stringify(value)); }
  saveStatus(value: ServiceStatus): void {
    value.updatedAt = Date.now();
    this.write('status.json', JSON.stringify(value));
  }
  private write(name: string, contents: string): void {
    const path: string = this.directory + '/' + name;
    const file: fs.File = fs.openSync(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, contents); } finally { fs.closeSync(file); }
    fs.renameSync(path + '.tmp', path);
  }
}
