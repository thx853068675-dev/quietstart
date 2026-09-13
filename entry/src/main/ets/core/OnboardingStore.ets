import { fileIo as fs } from '@kit.CoreFileKit';
export class OnboardingState { completed: boolean = false; deferred: boolean = false; step: number = 0; }
export class OnboardingStore {
  private directory: string;
  constructor(directory: string) { this.directory = directory; }
  read(): OnboardingState {
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/onboarding.json')) as OnboardingState;
      const state = new OnboardingState(); state.completed = raw.completed === true; state.deferred = raw.deferred === true;
      state.step = Number.isInteger(raw.step) && raw.step >= 0 && raw.step <= 3 ? raw.step : 0; return state;
    } catch (_) { return new OnboardingState(); }
  }
  save(step: number, completed: boolean = false, deferred: boolean = false): void {
    const state = new OnboardingState(); state.step = step; state.completed = completed; state.deferred = deferred;
    const path = this.directory + '/onboarding.json';
    const file = fs.openSync(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, JSON.stringify(state)); } finally { fs.closeSync(file); } fs.renameSync(path + '.tmp', path);
  }
}
