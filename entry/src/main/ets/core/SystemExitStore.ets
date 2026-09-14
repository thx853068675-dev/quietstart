import { AbilityConstant } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { DebugStore } from './DebugStore';

export class ExitEnvironment {
  osVersion: string = '';
  apiVersion: number = 0;
  model: string = '';
  appVersion: string = '';
  workerVersion: number = 0;
}
export class SystemExitRecord {
  capturedAt: number = 0;
  reason: number = -1;
  message: string = '';
  detail?: AbilityConstant.LastExitDetailInfo;
  launchReason: number = -1;
  launchMessage: string = '';
  launchUTCTime?: number;
  launchUptime?: number;
  expectedAction: string = '';
  recoveryAttempt: number = 0;
  environment: ExitEnvironment = new ExitEnvironment();
  sessionStartedAt: number = 0;
  heartbeatAt: number = 0;
  rpcAt: number = 0;
  operation: string = '';
  sessionState: string = '';
  sessionError: string = '';
}
class ExpectedExit { action: string = ''; at: number = 0; }

export function userRequestedExit(reason: number, message: string): boolean {
  const normalized = message.trim().toLowerCase();
  // Some vendor builds return NORMAL with this explicit system message.
  return reason === 9 || normalized === 'user request' || normalized === 'kill reason: user request';
}

export function exitReasonLabel(reason: number): string {
  const labels = ['系统未说明', '应用无响应', '正常或直接终止', '原生进程崩溃', '应用代码异常',
    '应用卡死', '系统性能管控', '系统资源管控', '应用升级', '最近任务结束', '系统终止信号'];
  return Number.isInteger(reason) && reason >= 0 && reason < labels.length ? labels[reason] : '未提供退出原因';
}

export class SystemExitStore {
  private directory: string;
  constructor(directory: string) { this.directory = directory; }
  private write(name: string, value: string): void {
    const p = this.directory + '/' + name;
    const f = fs.openSync(p + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(f.fd, value); } finally { fs.closeSync(f.fd); }
    fs.renameSync(p + '.tmp', p);
  }
  markExpected(action: string): void {
    if (!['activation', 'module-install', 'user-stop', 'worker-restart'].includes(action)) { return; }
    const expected = new ExpectedExit(); expected.action = action; expected.at = Date.now();
    this.write('expected-exit.json', JSON.stringify(expected));
  }
  read(): SystemExitRecord[] {
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/system-exits.json')) as SystemExitRecord[];
      return Array.isArray(raw) ? raw.filter((r: SystemExitRecord) => r && Number.isFinite(r.capturedAt) &&
        Number.isInteger(r.reason) && r.environment !== undefined).slice(0, 20) : [];
    } catch (_) { return []; }
  }
  capture(launch: AbilityConstant.LaunchParam, environment: ExitEnvironment, recovery: string = '', attempt: number = 0): SystemExitRecord {
    const row = new SystemExitRecord(); row.capturedAt = Date.now();
    row.reason = Number.isInteger(launch.lastExitReason) ? launch.lastExitReason : -1;
    row.message = typeof launch.lastExitMessage === 'string' ? launch.lastExitMessage : '';
    // Preserve every system-provided detail: PID/name/UID, subreason/message,
    // timestamp, RSS/PSS, and optional processState. Missing stays missing.
    row.detail = launch.lastExitDetailInfo;
    row.launchReason = Number.isInteger(launch.launchReason) ? launch.launchReason : -1;
    row.launchMessage = launch.launchReasonMessage ?? '';
    row.launchUTCTime = launch.launchUTCTime; row.launchUptime = launch.launchUptime;
    row.environment = environment;
    row.recoveryAttempt = Number.isInteger(attempt) && attempt >= 0 && attempt <= 3 ? attempt : 0;
    if (['process-exited', 'rpc-stalled', 'heartbeat-stalled', 'worker-ended', 'startup-timeout'].includes(recovery)) {
      row.expectedAction = recovery;
    }
    try {
      const expected = JSON.parse(fs.readTextSync(this.directory + '/expected-exit.json')) as ExpectedExit;
      if (Date.now() >= expected.at && Date.now() - expected.at <= 120000 &&
        ['activation', 'module-install', 'user-stop', 'worker-restart'].includes(expected.action)) { row.expectedAction = expected.action; }
      fs.unlinkSync(this.directory + '/expected-exit.json');
    } catch (_) {}
    const status = new DebugStore(this.directory).readStatus();
    row.sessionStartedAt = status.startedAt; row.heartbeatAt = status.heartbeatAt;
    row.rpcAt = status.rpcAt; row.operation = status.operation;
    row.sessionState = status.state; row.sessionError = status.errorCode;
    const old = this.read();
    const duplicate = row.detail?.timestamp && old.some((r: SystemExitRecord) => r.detail?.timestamp === row.detail?.timestamp &&
      r.detail?.pid === row.detail?.pid && r.reason === row.reason);
    if (!duplicate) { this.write('system-exits.json', JSON.stringify([row].concat(old).slice(0, 20))); }
    return row;
  }
  exportText(): string { return JSON.stringify(this.read(), null, 2); }
}
