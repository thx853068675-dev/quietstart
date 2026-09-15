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
export class WorkerFailure {
  terminal: boolean = true;
  at: number = 0;
  token: string = '';
  pid: number = 0;
  sessionStartedAt: number = 0;
  recoveryAttempt: number = 0;
  bundle: string = '';
  operation: string = '';
  operationAt: number = 0;
  heartbeatAt: number = 0;
  rpcAt: number = 0;
  apiVersion: number = 0;
  code: string = '';
  name: string = '';
  message: string = '';
  stack: string = '';
  context: string = '';
}
export class SystemFaultEvent {
  receivedAt: number = 0; name: string = ''; time: number = 0; reason: string = '';
  pid: number = 0; foreground: boolean = false; detail: string = '';
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
  recoveryAttemptKnown: boolean = false;
  recoveryReason: string = '';
  plannedAction: string = '';
  plannedActionAt: number = 0;
  selfStopVerified: boolean = false;
  stopDecision: string = 'continue';
  supervisorToken: string = '';
  workerPid: number = 0;
  supervisorEvents: SupervisorEvent[] = [];
  environment: ExitEnvironment = new ExitEnvironment();
  sessionStartedAt: number = 0;
  heartbeatAt: number = 0;
  rpcAt: number = 0;
  operation: string = '';
  sessionState: string = '';
  sessionError: string = '';
  sessionMessage: string = '';
  workerFailure?: WorkerFailure;
}
export class SupervisorEvent {
  token: string = ''; at: number = 0; supervisorPid: number = 0; attempt: number = 0;
  state: string = ''; cause: string = ''; workerPid: number = 0; uiTestPids: string = '';
  heartbeatAt: number = 0; rpcAt: number = 0; operation: string = ''; command: string = ''; exitCode: number = 0;
}
class StopIntent { token: string = ''; pid: number = 0; at: number = 0; attempt: number = 0; completed: boolean = false; }

export function verifiedSelfStop(intent: StopIntent, row: SystemExitRecord, token: string): boolean {
  const detail = row.detail;
  return intent.completed === true && /^[0-9]{13,16}$/.test(token) && intent.token === token &&
    Number.isInteger(intent.pid) && intent.pid > 0 && detail?.pid === intent.pid &&
    Number.isFinite(intent.at) && row.capturedAt >= intent.at && row.capturedAt - intent.at <= 120000 &&
    typeof detail.timestamp === 'number' && detail.timestamp >= intent.at && detail.timestamp - intent.at <= 15000;
}

export function shouldStopRecovery(row: SystemExitRecord): boolean {
  if (row.plannedAction === 'user-stop') { return true; }
  // Generic activation labels are NOT proof that a User Request was ours.
  return systemUserRequestedExit(row) && !row.selfStopVerified;
}

export function systemExitTitle(row: SystemExitRecord): string {
  if (row.selfStopVerified) { return '监督主动重建'; }
  if (row.reason === 9) { return '最近任务结束'; }
  if (systemUserRequestedExit(row)) { return '系统报告终止请求'; }
  return exitReasonLabel(row.reason);
}
class ExpectedExit { action: string = ''; at: number = 0; }

interface VendorExitDetails extends AbilityConstant.LastExitDetailInfo { killReason?: string; }
export function systemUserRequestedExit(row: SystemExitRecord): boolean {
  const detail = row.detail as VendorExitDetails | undefined;
  return userRequestedExit(row.reason, row.message) ||
    userRequestedExit(-1, typeof detail?.exitMsg === 'string' ? detail.exitMsg : '') ||
    userRequestedExit(-1, typeof detail?.killReason === 'string' ? detail.killReason : '');
}

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
  workerFailures(): WorkerFailure[] {
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/worker-failures.json')) as WorkerFailure[];
      return Array.isArray(raw) ? raw.filter((r: WorkerFailure) => r && Number.isFinite(r.at) &&
        Number.isInteger(r.pid) && typeof r.message === 'string').slice(0, 20) : [];
    } catch (_) { return []; }
  }
  recordWorkerFailure(row: WorkerFailure): void {
    // Only terminal errors write here. No screenshots, layout text or credentials.
    row.message = row.message.slice(0, 2000); row.stack = row.stack.slice(0, 6000);
    row.context = row.context.slice(0, 300); row.name = row.name.slice(0, 100); row.code = row.code.slice(0, 100);
    this.write('worker-failures.json', JSON.stringify([row].concat(this.workerFailures()).slice(0, 20)));
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
  timeline(): SupervisorEvent[] {
    try {
      const result: SupervisorEvent[] = [];
      const lines = fs.readTextSync(this.directory + '/supervisor-events.jsonl').split('\n').slice(-121);
      for (const line of lines) {
        try {
          const row = JSON.parse(line) as SupervisorEvent;
          if (/^[0-9]{13,16}$/.test(row.token) && Number.isFinite(row.at) && Number.isInteger(row.supervisorPid) &&
            typeof row.state === 'string' && typeof row.cause === 'string') { result.push(row); }
        } catch (_) {}
      }
      return result.slice(-120);
    } catch (_) { return []; }
  }
  importSupervisorEvents(text: string, token: string): void {
    if (!/^[0-9]{13,16}$/.test(token) || text.length > 65536) { return; }
    const rows = this.timeline();
    let changed = false;
    for (const line of text.split('\n').slice(-121)) {
      try {
        const event = JSON.parse(line) as SupervisorEvent;
        if (event.token !== token || !Number.isFinite(event.at) || !Number.isInteger(event.supervisorPid) ||
          typeof event.state !== 'string' || typeof event.cause !== 'string') { continue; }
        const encoded = JSON.stringify(event);
        if (!rows.some((old: SupervisorEvent) => JSON.stringify(old) === encoded)) { rows.push(event); changed = true; }
      } catch (_) {}
    }
    if (!changed) { return; }
    rows.sort((a: SupervisorEvent, b: SupervisorEvent) => a.at - b.at);
    this.write('supervisor-events.jsonl', rows.slice(-120).map((event: SupervisorEvent) => JSON.stringify(event)).join('\n') + '\n');
  }
  capture(launch: AbilityConstant.LaunchParam, environment: ExitEnvironment, recovery: string = '', attempt: number = -1, stopIntent: string = ''): SystemExitRecord {
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
    row.recoveryAttemptKnown = Number.isInteger(attempt) && attempt >= 0 && attempt <= 2147483647;
    row.recoveryAttempt = row.recoveryAttemptKnown ? attempt : 0;
    if (['process-exited', 'rpc-stalled', 'heartbeat-stalled', 'worker-ended', 'startup-timeout'].includes(recovery)) {
      row.recoveryReason = recovery;
      row.expectedAction = recovery;
    }
    try {
      const expected = JSON.parse(fs.readTextSync(this.directory + '/expected-exit.json')) as ExpectedExit;
      if (Date.now() >= expected.at && Date.now() - expected.at <= 120000 &&
        ['activation', 'module-install', 'user-stop', 'worker-restart'].includes(expected.action)) {
        row.plannedAction = expected.action; row.plannedActionAt = expected.at;
        if (!row.recoveryReason) { row.expectedAction = expected.action; }
      }
      fs.unlinkSync(this.directory + '/expected-exit.json');
    } catch (_) {}
    const status = new DebugStore(this.directory).readStatus();
    row.supervisorToken = status.supervisorToken;
    try {
      const parts = fs.readTextSync(this.directory + '/worker-health.txt').trim().split(/\s+/);
      if (parts[0] === status.supervisorToken && /^[0-9]+$/.test(parts[1])) { row.workerPid = Number(parts[1]); }
    } catch (_) {}
    try {
      const intent = JSON.parse(stopIntent || fs.readTextSync(this.directory + '/supervisor-stop-intent.json')) as StopIntent;
      const control = fs.readTextSync(this.directory + '/supervision-control.txt').trim().split(/\s+/);
      row.selfStopVerified = verifiedSelfStop(intent, row, control[0]);
      fs.unlinkSync(this.directory + '/supervisor-stop-intent.json');
    } catch (_) {}
    row.stopDecision = shouldStopRecovery(row) ? (row.plannedAction === 'user-stop' ? 'explicit-user-stop' : 'system-user-request') : row.selfStopVerified ? 'self-restart' : 'continue';
    row.supervisorEvents = this.timeline().filter((event: SupervisorEvent) => event.token === row.supervisorToken).slice(-12);
    row.sessionStartedAt = status.startedAt; row.heartbeatAt = status.heartbeatAt;
    row.rpcAt = status.rpcAt; row.operation = status.operation;
    row.sessionState = status.state; row.sessionError = status.errorCode; row.sessionMessage = status.message;
    row.workerFailure = this.workerFailures().find((failure: WorkerFailure) => failure.terminal !== false && failure.pid === row.workerPid &&
      failure.token === row.supervisorToken && failure.sessionStartedAt === row.sessionStartedAt);
    const old = this.read();
    const duplicate = row.detail?.timestamp && old.some((r: SystemExitRecord) => r.detail?.timestamp === row.detail?.timestamp &&
      r.detail?.pid === row.detail?.pid && r.reason === row.reason);
    if (!duplicate) { this.write('system-exits.json', JSON.stringify([row].concat(old).slice(0, 20))); }
    return row;
  }
  faultEvents(): SystemFaultEvent[] {
    try {
      const rows = JSON.parse(fs.readTextSync(this.directory + '/system-fault-events.json')) as SystemFaultEvent[];
      return Array.isArray(rows) ? rows.filter((r: SystemFaultEvent) => r && Number.isFinite(r.time) &&
        ['APP_KILLED', 'APP_CRASH', 'APP_FREEZE'].includes(r.name)).slice(0, 40) : [];
    } catch (_) { return []; }
  }
  recordFaultEvent(name: string, params: Record<string, Object>): void {
    if (!['APP_KILLED', 'APP_CRASH', 'APP_FREEZE'].includes(name)) { return; }
    const row = new SystemFaultEvent(); row.receivedAt = Date.now(); row.name = name;
    row.time = Number(params['time']);
    if (!Number.isFinite(row.time) || row.time <= 0) { return; }
    row.reason = typeof params['reason'] === 'string' ? String(params['reason']).slice(0, 300) : '';
    row.foreground = params['foreground'] === true;
    // Persist only exit metadata, never the full event payload (which may include paths or user data).
    const raw = params['last_exit_detail_info'];
    try {
      const detail = (typeof raw === 'string' ? JSON.parse(raw) : raw) as Record<string, Object>;
      if (detail && typeof detail === 'object') {
        const safe: Record<string, string | number> = {};
        for (const key of ['pid', 'uid', 'timestamp', 'process_state', 'rss', 'pss', 'kill_reason', 'exit_msg', 'process_name']) {
          const value = detail[key];
          if (typeof value === 'string' || typeof value === 'number') { safe[key] = String(value).slice(0, 500); }
        }
        row.detail = JSON.stringify(safe); row.pid = Number(detail['pid']) || 0;
      }
    } catch (_) {}
    if (!row.pid) { row.pid = Number(params['pid']) || 0; }
    const rows = this.faultEvents();
    if (rows.some((r: SystemFaultEvent) => r.name === row.name && r.time === row.time && r.pid === row.pid)) { return; }
    rows.push(row); rows.sort((a: SystemFaultEvent, b: SystemFaultEvent) => b.time - a.time);
    this.write('system-fault-events.json', JSON.stringify(rows.slice(0, 40)));
  }
  exportText(): string {
    return JSON.stringify({ schemaVersion: 4, systemFaultEvents: this.faultEvents(), workerFailures: this.workerFailures(), exportedAt: Date.now(), exits: this.read(), supervisorTimeline: this.timeline() }, null, 2);
  }
}
