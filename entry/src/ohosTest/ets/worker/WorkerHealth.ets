import { fileIo as fs } from '@kit.CoreFileKit';

export class WorkerHealth {
  pulseAt: number = 0;
  progressAt: number = 0;
  rpcAt: number = 0;
  inputAt: number = 0;
  operation: string = 'initializing';
  operationAt: number = Date.now();
  sleeping: boolean = false;
  private directory: string;
  readonly token: string;
  readonly pid: number;
  constructor(directory: string, token: string = '', pid: number = 0) {
    this.directory = directory; this.token = token; this.pid = pid;
  }
  begin(operation: string): void { this.operation = operation; this.operationAt = Date.now(); }
  rpc(): void { this.rpcAt = Date.now(); }
  input(): void { this.inputAt = Date.now(); this.rpc(); }
  progress(sleeping: boolean): void {
    this.progressAt = Date.now(); this.sleeping = sleeping; this.begin(sleeping ? 'sleeping' : 'waiting');
  }
  save(): void {
    this.pulseAt = Date.now();
    if (!this.token) { return; }
    const p = this.directory + '/worker-health.txt';
    const f = fs.openSync(p + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    const values = [this.token, this.pid.toString(), Math.floor(this.pulseAt / 1000).toString(),
      Math.floor(this.progressAt / 1000).toString(), Math.floor(this.rpcAt / 1000).toString(),
      this.sleeping ? 'sleeping' : 'active', this.operation, Math.floor(this.operationAt / 1000).toString(),
      Math.floor(this.inputAt / 1000).toString()];
    try { fs.writeSync(f.fd, values.join(' ') + '\n'); } finally { fs.closeSync(f.fd); }
    fs.renameSync(p + '.tmp', p);
  }
}
