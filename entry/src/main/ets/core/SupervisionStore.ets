import { fileIo as fs } from '@kit.CoreFileKit';

export class SupervisionControl {
  token: string = '';
  active: boolean = false;
  at: number = 0;
}

export function validSessionToken(token: string): boolean { return /^[0-9]{13,16}$/.test(token); }

// A tiny atomic file is readable by the authorized device shell. Never source
// this file as shell code; all fields are fixed tokens or validated numbers.
export class SupervisionStore {
  private directory: string;
  constructor(directory: string) { this.directory = directory; }
  read(): SupervisionControl {
    const value = new SupervisionControl();
    try {
      const parts = fs.readTextSync(this.directory + '/supervision-control.txt').trim().split(/\s+/);
      if (parts.length !== 3 || !validSessionToken(parts[0]) || !['active', 'stopped'].includes(parts[1]) ||
        !/^[0-9]+$/.test(parts[2])) { return value; }
      value.token = parts[0]; value.active = parts[1] === 'active'; value.at = Number(parts[2]);
    } catch (_) {}
    return value;
  }
  private write(token: string, active: boolean): void {
    if (!validSessionToken(token)) { throw new Error('Invalid supervision token'); }
    const p = this.directory + '/supervision-control.txt';
    const f = fs.openSync(p + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(f.fd, token + ' ' + (active ? 'active' : 'stopped') + ' ' + Date.now() + '\n'); }
    finally { fs.closeSync(f.fd); }
    fs.renameSync(p + '.tmp', p);
  }
  start(token: string): void { this.write(token, true); }
  stop(): void { const c = this.read(); if (c.token) { this.write(c.token, false); } }
  notice(): string {
    try { return fs.readTextSync(this.directory + '/supervision-notice.txt'); } catch (_) { return ''; }
  }
  setNotice(message: string): void {
    const p = this.directory + '/supervision-notice.txt';
    const f = fs.openSync(p, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(f.fd, message.slice(0, 300)); } finally { fs.closeSync(f.fd); }
  }
  allows(token: string): boolean {
    const c = this.read(); return validSessionToken(token) && c.token === token && c.active;
  }
}
