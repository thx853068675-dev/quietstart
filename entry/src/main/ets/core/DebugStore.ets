import { fileIo as fs } from '@kit.CoreFileKit';

export class DebugRecord {
  processId: string = '';
  processStartedAt: number = 0;
  at: number = 0;
  bundle: string = '';
  result: string = '';
  message: string = '';
}

// Mirrors the debug worker's local status file without importing test-only APIs.
export class DebugStatus {
  running: boolean = false;
  startedAt: number = 0;
  expiresAt: number = 0;
  heartbeatAt: number = 0;
  progressAt: number = 0;
  rpcAt: number = 0;
  inputAt: number = 0;
  operation: string = '';
  operationAt: number = 0;
  supervisorToken: string = '';
  recoveryAttempt: number = 0;
  lastBundle: string = '';
  state: string = 'idle';
  message: string = '尚未收到调试会话状态，请先完成本机无线激活。';
  errorCode: string = '';
  attemptCount: number = 0;
  clickCount: number = 0;
  observedDismissedCount: number = 0;
  retainedCount: number = 0;
  unverifiedCount: number = 0;
  history: DebugRecord[] = [];
}

function nonnegative(value: number): number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : 0;
}

function safeText(value: string): string {
  return typeof value === 'string' ? value.slice(0, 1000) : '';
}

export function isDebugOnline(status: DebugStatus, now: number = Date.now()): boolean {
  const age: number = now - status.heartbeatAt;
  const responsive = !status.supervisorToken || (status.rpcAt > 0 && status.progressAt > 0 &&
    (status.state === 'sleeping' || (now >= status.rpcAt && now >= status.progressAt && now - status.rpcAt <= 30000 && now - status.progressAt <= 30000)));
  return responsive && status.running === true && status.heartbeatAt > 0 && age >= 0 && age <= 6000 &&
    Number.isFinite(status.expiresAt) && status.expiresAt >= 0 &&
    (status.expiresAt === 0 || now < status.expiresAt);
}

// A fresh manual UI launch after the final recovery died may not receive the
// supervisor's Want (for example while locked). Do not hide that spent budget.
export function exhaustedRecovery(status: DebugStatus, token: string, now: number = Date.now()): boolean {
  return token.length > 0 && status.supervisorToken === token && status.recoveryAttempt >= 3 &&
    (!status.running || now - status.heartbeatAt > 30000);
}

export class DebugStore {
  private directory: string;
  constructor(directory: string) {
    this.directory = directory;
  }

  readStatus(): DebugStatus {
    const status: DebugStatus = new DebugStatus();
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/debug-status.json')) as DebugStatus;
      if (!raw || typeof raw !== 'object') {
        return status;
      }
      if (typeof raw.expiresAt !== 'number' || !Number.isFinite(raw.expiresAt) || raw.expiresAt < 0) {
        return status;
      }
      status.running = raw.running === true;
      status.startedAt = nonnegative(raw.startedAt);
      status.expiresAt = nonnegative(raw.expiresAt);
      status.heartbeatAt = nonnegative(raw.heartbeatAt);
      status.progressAt = nonnegative(raw.progressAt); status.rpcAt = nonnegative(raw.rpcAt);
      status.inputAt = nonnegative(raw.inputAt); status.operation = safeText(raw.operation);
      status.operationAt = nonnegative(raw.operationAt); status.supervisorToken = safeText(raw.supervisorToken);
      status.recoveryAttempt = nonnegative(raw.recoveryAttempt);
      status.lastBundle = safeText(raw.lastBundle);
      status.state = safeText(raw.state) || 'idle';
      status.message = safeText(raw.message) || status.message;
      status.errorCode = safeText(raw.errorCode);
      status.attemptCount = Math.floor(nonnegative(raw.attemptCount));
      status.clickCount = Math.floor(nonnegative(raw.clickCount));
      status.observedDismissedCount = Math.floor(nonnegative(raw.observedDismissedCount));
      status.retainedCount = Math.floor(nonnegative(raw.retainedCount));
      status.unverifiedCount = Math.floor(nonnegative(raw.unverifiedCount));
      if (Array.isArray(raw.history)) {
        raw.history.slice(0, 200).forEach((source: DebugRecord) => {
          if (source && typeof source === 'object') {
            const record: DebugRecord = new DebugRecord();
            record.at = nonnegative(source.at);
            record.processId = safeText(source.processId);
            record.processStartedAt = nonnegative(source.processStartedAt);
            record.bundle = safeText(source.bundle);
            record.result = safeText(source.result);
            record.message = safeText(source.message);
            status.history.push(record);
          }
        });
      }
    } catch (_) {
      // A missing, partial or malformed file must never imply an active worker.
      return new DebugStatus();
    }
    return status;
  }
}

export class DebugProcess {
  id: string = '';
  bundle: string = '';
  startedAt: number = 0;
  endedAt: number = 0;
  result: string = 'decision';
  timing: string = '';
  records: DebugRecord[] = [];
}

export function groupDebugRecords(history: DebugRecord[]): DebugProcess[] {
  const groups: DebugProcess[] = [];
  let legacy: DebugProcess | undefined;
  // Deferred logging must not change event chronology. At equal milliseconds,
  // show preflight before input and input before its completion.
  const phases = ['decision', 'learned', 'attempt', 'clickSent', 'observedDismissed', 'retained', 'unverified', 'cancelled', 'error'];
  const ordered = history.slice().reverse().sort((a: DebugRecord, b: DebugRecord) =>
    a.at - b.at || (a.processId && a.processId === b.processId ? phases.indexOf(a.result) - phases.indexOf(b.result) : 0));
  for (const row of ordered) {
    const id = row.processId ? row.processId + ':' + row.bundle : '';
    let group = id ? groups.find((item: DebugProcess) => item.id === id) : undefined;
    if (!id && legacy && legacy.bundle === row.bundle && row.at - legacy.endedAt <= 15000 &&
      !['observedDismissed', 'retained', 'unverified', 'cancelled'].includes(legacy.result)) { group = legacy; }
    if (!group) {
      group = new DebugProcess(); group.id = id || 'legacy:' + row.bundle + ':' + row.at;
      group.bundle = row.bundle;
      group.startedAt = row.processStartedAt > 0 && row.processStartedAt <= row.at ? row.processStartedAt : row.at;
      groups.push(group);
    }
    legacy = id ? undefined : group;
    group.endedAt = Math.max(group.endedAt, row.at); group.records.push(row);
    if (row.result !== 'decision' || group.result === 'decision') { group.result = row.result; }
    const timing = /发现前台至点击 (\d+) ms/.exec(row.message);
    if (timing) { group.timing = '发出点击 ' + (Number(timing[1]) / 1000).toFixed(2) + ' 秒'; }
  }
  return groups.sort((a: DebugProcess, b: DebugProcess) => b.startedAt - a.startedAt).slice(0, 20);
}
