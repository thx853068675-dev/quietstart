import { captureLayout, closeLayoutConnection, LAYOUT_READ_INTERRUPTED } from './LayoutCapture';
import { stressBuild, consumeSupervisionStress } from '../../../main/ets/core/SupervisionStressProbe';
import { SystemExitStore, WorkerFailure } from '../../../main/ets/core/SystemExitStore';
import { ManualLearningWorker } from './ManualLearningWorker';
import { desktopAppNames } from '../../../main/ets/core/DesktopAppNames';
import { VisualRecognition } from './VisualRecognition';
import { RulePackStore } from '../../../main/ets/core/RulePackStore';
import { AdFreeStore, AdFreeEntry, CLEAN_STABLE_MS } from '../../../main/ets/core/AdFreeStore';
import { AppNameResolver } from '../../../main/ets/core/AppNameResolver';
import { abilityDelegatorRegistry, Component, Driver, ON, UiWindow } from '@kit.TestKit';
import { BusinessError, deviceInfo, power } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SkipReminder } from '../../../main/ets/core/SkipReminder';
import { LocalStore } from '../../../main/ets/core/LocalStore';
import { runtimeAppLabel, LearnedRule, LearningStore, OWN_BUNDLE, ruleState, sameRuleGeometry, validBundle, discoverableBundle } from '../../../main/ets/core/LearningStore';
import { findLearnedCandidate, discoverSnapshot, soleVisibleAppBundle, SnapshotCandidate, LearnedCandidate, learnedTargetState, snapshotTargetState, AdMarkerEvidence, readCandidateLabel, ScanReport } from './LearningWorker';
import { ENTRY_WINDOW_MS, MAX_RUN_SECONDS, isSplashButton, scanInterval } from './Rules';
import { process } from '@kit.ArkTS';
import { SupervisionStore } from '../../../main/ets/core/SupervisionStore';
import { WorkerHealth } from './WorkerHealth';

const TAG: string = 'QuietStartWorker';
const SAVED_LAYOUT_READ_MS: number = 1100;
const SAVED_LAYOUT_POST_MS: number = 150;
const SAVED_LAYOUT_TOTAL_MS: number = SAVED_LAYOUT_READ_MS + SAVED_LAYOUT_POST_MS;

// A non-focusable splash can be the active interactive window while no focused
// window is exposed by UiTest. If both filters return nothing, validate the
// sole visible app in a new complete display snapshot, then reacquire its window.
// Repeat this before input and after verification; never use a saved app name.
class ForegroundFrame {
  bundle: string = '';
  text: string = '';
  readAt: number = 0;
  readyAt: number = 0;
}
async function foregroundWindow(driver: Driver, directory: string, frame?: ForegroundFrame, allowSnapshot: boolean = true): Promise<UiWindow | undefined> {
  const focused = await driver.findWindow({ focused: true });
  if (focused) { return focused; }
  const active = await driver.findWindow({ active: true });
  if (active) { return active; }
  if (!allowSnapshot) { return undefined; }
  const path = directory + '/foreground-snapshot.json';
  try { fs.unlinkSync(path); } catch (_) {}
  try {
    const readAt = Date.now();
    if (!await captureLayout(driver, path)) { return undefined; }
    const text = fs.readTextSync(path);
    const readyAt = Date.now();
    const bundle = soleVisibleAppBundle(text);
    const window = bundle ? await driver.findWindow({ bundleName: bundle }) : undefined;
    if (frame && window && bundle) { frame.bundle = bundle; frame.text = text; frame.readAt = readAt; frame.readyAt = readyAt; }
    return window;
  } finally { try { fs.unlinkSync(path); } catch (_) {} }
}


export class DebugRecord {
  processId: string = '';
  processStartedAt: number = 0;
  at: number = 0;
  bundle: string = '';
  result: string = '';
  message: string = '';
}

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
  message: string = '';
  errorCode: string = '';
  attemptCount: number = 0;
  clickCount: number = 0;
  observedDismissedCount: number = 0;
  retainedCount: number = 0;
  unverifiedCount: number = 0;
  history: DebugRecord[] = [];
}

// Only one instance should be launched in an aa test run. UiTest calls below
// are all awaited serially; the heartbeat timer performs file writes only.
export async function run(delegator: abilityDelegatorRegistry.AbilityDelegator,
  runSeconds: number, supervisorToken: string = '', recoveryAttempt: number = 0): Promise<DebugStatus> {
  if (!Number.isFinite(runSeconds) || runSeconds < 0 || (runSeconds > 0 && runSeconds < 1) ||
    runSeconds > MAX_RUN_SECONDS) {
    throw new Error('SkipWorker requires runSeconds to be 0, or at least 1 and at most 43200.');
  }
  const directory: string = delegator.getAppContext().filesDir;
  const worker: SkipWorker = new SkipWorker(directory, runSeconds, delegator, supervisorToken, recoveryAttempt);
  return await worker.run();
}

class SkipWorker {
  private health: WorkerHealth;
  private supervision: SupervisionStore;
  private manual: ManualLearningWorker;
  private visual: VisualRecognition;
  private status: DebugStatus = new DebugStatus();
  private store: LocalStore;
  private reminder: SkipReminder;
  private directory: string;
  private sessionBundle: string = '';
  private sessionUntil: number = 0;
  private sessionAttempted: boolean = false;
  private verificationBundle: string = '';
  private verificationUntil: number = 0;
  private absentObservations: number = 0;
  private presentObservations: number = 0;
  private verifyingMarker?: AdMarkerEvidence;
  private storageFailed: boolean = false;
  private heartbeatTimer: number = -1;
  private learning: LearningStore;
  private rulePacks: RulePackStore;
  private names: AppNameResolver;
  private delegator: abilityDelegatorRegistry.AbilityDelegator;
  private learnedMatch?: LearnedCandidate;
  private verifyingRule?: LearnedRule;
  private observedKeys: string[] = [];
  private learningProbe?: SnapshotCandidate;
  private learningProbeAt: number = 0;
  private diagnosticBundle: string = '';
  private diagnosticReason: string = '';
  private pendingObservation: string = '';
  private recordedAndroidApps: string[] = [];
  private processSequence: number = 0;
  private processId: string = '';
  private processStartedAt: number = 0;
  private verificationProcessId: string = '';
  private verificationProcessStartedAt: number = 0;
  private desktopMetadataVisited: boolean = false;
  private pendingObservationMs: number = 0;
  private diagnosticKey: string = '';
  private candidateTraceSession: string = '';
  private diagnosticAt: number = 0;
  private scanStartedAt: number = 0;
  private verificationStartedAt: number = 0;
  private adFree: AdFreeStore;
  private cleanEligible: boolean = false;
  private cleanSamples: number = 0;
  private cleanFirstAt: number = 0;
  private cleanLastAt: number = 0;
  private cleanFinished: boolean = false;
  private nextPowerCheckAt: number = 0;
  private screenActive: boolean = true;
  private allowStress: boolean = stressBuild();
  private journalAt: number = 0;
  private layoutReadFailures: number = 0;
  private transitionScanUntil: number = 0;
  private foregroundFrame: ForegroundFrame = new ForegroundFrame();
  private foregroundNeedsSnapshot: boolean = false;
  private recordedBundle: string = '';

  constructor(directory: string, runSeconds: number, delegator: abilityDelegatorRegistry.AbilityDelegator,
    supervisorToken: string, recoveryAttempt: number) {
    this.health = new WorkerHealth(directory, supervisorToken, process.pid);
    this.supervision = new SupervisionStore(directory);
    this.status.supervisorToken = supervisorToken;
    this.status.recoveryAttempt = recoveryAttempt;
    this.directory = directory;
    this.manual = new ManualLearningWorker(directory, delegator);
    this.visual = new VisualRecognition(directory);
    this.delegator = delegator;
    this.store = new LocalStore(directory);
    this.reminder = new SkipReminder(directory);
    this.learning = new LearningStore(directory);
    this.rulePacks = new RulePackStore(directory);
    this.adFree = new AdFreeStore(directory);
    this.names = new AppNameResolver(directory);
    this.status.startedAt = Date.now();
    this.status.expiresAt = runSeconds === 0 ? 0 : this.status.startedAt + runSeconds * 1000;
  }

  async run(): Promise<DebugStatus> {
    if (this.health.token && !this.supervision.allows(this.health.token)) { return this.status; }
    this.status.running = true;
    this.setState('initializing', '正在初始化官方 UiTest 调试会话');
    try {
      // A new activation clears the previous session's stop request while
      // preserving the user's switch, whitelist and other settings.
      const settings = this.store.readSettings();
      if (!this.health.token) { settings.stopRequested = false; this.store.saveSettings(settings); }
      this.saveStatus();
      this.heartbeatTimer = setInterval(() => {
        try {
          this.saveStatus();
        } catch (error) {
          if (this.storageFailed) { return; }
          this.storageFailed = true;
          this.reportError(error as BusinessError, '状态文件写入失败');
        }
      }, 2000);
      const driver: Driver = Driver.create();
      if (!driver) { throw new Error('Official UiTest Driver initialization returned null'); }
      while (!this.isExpired() && !this.storageFailed) {
        try {
          if (this.store.readSettings().stopRequested === true ||
            (this.health.token && !this.supervision.allows(this.health.token))) {
            if (this.verificationBundle) {
              this.finishUnverified('用户结束会话，尚未完成验证');
            }
            this.setState('finished', '用户已结束本次调试会话');
            return this.status;
          }
          if (this.health.token && this.screenActive && Date.now() - this.journalAt > 60000) {
            this.journalAt = Date.now();
            try {
              const journal = await this.delegator.executeShellCommand('cat /data/local/tmp/quietstart-supervisor/supervisor-events.jsonl', 1);
              if (journal.exitCode === 0) { new SystemExitStore(this.directory).importSupervisorEvents(journal.stdResult, this.health.token); }
            } catch (_) {}
          }
          this.health.begin('session-control');
          if (this.allowStress) { await consumeSupervisionStress(this.directory, this.health.token); }
          this.health.begin('scan');
          await this.scan(driver);
          this.layoutReadFailures = 0;
          this.health.progress(!this.screenActive);
          if (this.screenActive) { this.names.tick(); }
        } catch (error) {
          this.cleanSamples = 0; this.cleanFirstAt = 0; this.cleanLastAt = 0;
          const failure = error as BusinessError;
          if (failure.code === LAYOUT_READ_INTERRUPTED && ++this.layoutReadFailures <= 2) {
            this.learningProbe = undefined; this.cleanEligible = false;
            this.reportError(failure, '布局读取中断，连接已释放；等待下一帧重建', false);
            await driver.delayMs(80); continue;
          }
          if (failure.code !== 17000004) {
            this.finishUnverified('UiTest 接口失败，无法完成验证');
            this.reportError(failure, '工作会话发生异常，已停止本次点击会话');
            break;
          }
          // Window/component references can expire while the user changes apps.
          // Discard the stale reference; never turn this into a coordinate click.
          if (this.verificationBundle) {
            this.absentObservations = 0;
            this.presentObservations = 0;
            if (Date.now() >= this.verificationUntil) { this.finishUnverified('页面持续更新，未取得稳定验证结果'); }
          }
          this.setState(this.verificationBundle ? 'verifying' : 'waiting', '界面切换中，等待稳定后重新检查');
        }
        const interval: number = this.manual.hasActiveRequest() ? 150 :
          (this.screenActive && Date.now() < this.transitionScanUntil ? 80 : this.status.state === 'watching' ? scanInterval(Date.now() - (this.sessionUntil - ENTRY_WINDOW_MS)) :
          (this.status.state === 'verifying' ? 200 : (this.status.state === 'sleeping' ? 1000 : 500)));
        const remaining: number = this.status.expiresAt === 0 ? interval : this.status.expiresAt - Date.now();
        if (remaining > 0 && !this.storageFailed) {
          if (this.status.state === 'sleeping') {
            await new Promise<void>((resolve) => { setTimeout(resolve, Math.min(interval, remaining)); });
          } else {
            this.health.begin('delay');
            await driver.delayMs(Math.min(interval, remaining));
          }
        }
      }
      if (!this.storageFailed && this.status.state !== 'error') {
        if (this.verificationBundle) {
          this.finishUnverified('调试会话结束，尚未完成验证');
        }
        this.setState('finished', '本次限时调试会话已结束');
      }
    } catch (error) {
      this.reportError(error as BusinessError, '工作会话发生异常，已停止本次点击会话');
    } finally {
      this.finishObservation('检测会话结束，检查未完成');
      this.names.close();
      closeLayoutConnection();
      if (this.heartbeatTimer !== -1) {
        clearInterval(this.heartbeatTimer);
        this.heartbeatTimer = -1;
      }
      this.status.running = false;
      this.health.begin('ended');
      try {
        this.saveStatus();
      } catch (error) {
        this.reportError(error as BusinessError, '最终状态文件写入失败');
      }
    }
    return this.status;
  }

  private async scan(driver: Driver): Promise<void> {
    this.scanStartedAt = Date.now();
    if (Date.now() >= this.nextPowerCheckAt) {
      this.nextPowerCheckAt = Date.now() + 500;
      try { this.screenActive = power.isActive(); } catch (_) { this.screenActive = true; }
    }
    if (!this.screenActive) {
      this.finishObservation('屏幕已关闭，检查未完成');
      this.cleanEligible = false; this.sessionBundle = '';
      if (this.verificationBundle) { this.finishUnverified('设备已灭屏，停止界面读取'); }
      this.setState('sleeping', '屏幕已关闭，暂停窗口和广告扫描'); return;
    }
    this.health.begin('foreground');
    const foregroundStarted = Date.now();
    this.foregroundFrame = new ForegroundFrame();
    // During the first second without focus, query lightweight window state
    // again instead of exporting the launcher/animation tree repeatedly.
    const manualEventMode = deviceInfo.sdkApiVersion >= 22 && deviceInfo.sdkApiVersion < 26 && this.manual.hasActiveRequest();
    const allowFallback = !manualEventMode && (deviceInfo.sdkApiVersion >= 26 || this.foregroundNeedsSnapshot ||
      (this.transitionScanUntil > 0 && Date.now() >= this.transitionScanUntil - 1000));
    const focusedWindow = await foregroundWindow(driver, this.directory,
      deviceInfo.sdkApiVersion < 26 ? this.foregroundFrame : undefined, allowFallback);
    const bundle: string = focusedWindow ? await focusedWindow.getBundleName() : (manualEventMode ? this.manual.eventBundle() : '');
    this.health.rpc();
    this.foregroundNeedsSnapshot = !!this.foregroundFrame.bundle;
    const foregroundMs = Date.now() - foregroundStarted;
    if (foregroundMs > 250) { hilog.info(0, TAG, 'slow foreground ms=%{public}d bundle=%{public}s', foregroundMs, bundle); }
    // Launch transitions briefly have no focused/active app. Avoid another
    // half-second idle wait, but retain normal idle and screen-off cadence.
    if (!bundle && this.transitionScanUntil === 0) { this.transitionScanUntil = Date.now() + 2000; }
    else if (bundle) { this.transitionScanUntil = 0; }
    this.status.lastBundle = bundle;
    if (!manualEventMode && bundle === 'com.ohos.sceneboard' && !this.desktopMetadataVisited) {
      // One bounded attempt per desktop visit, never a timed screenshot loop.
      this.desktopMetadataVisited = true;
      await this.readDesktopNames(driver);
    } else if (bundle && bundle !== 'com.ohos.sceneboard') {
      this.desktopMetadataVisited = false;
    }
    if (bundle !== this.sessionBundle) { this.finishObservation(bundle ? '已离开应用，检查未完成' : '前台窗口丢失，检查未完成'); }
    if (!bundle) { this.cleanEligible = false; this.sessionBundle = ''; }
    if (bundle && bundle !== this.sessionBundle) {
      this.sessionBundle = bundle;
      this.processStartedAt = Date.now();
      this.processId = this.status.startedAt + ':' + (++this.processSequence);
      this.sessionUntil = Date.now() + ENTRY_WINDOW_MS;
      this.sessionAttempted = false;
      this.observedKeys = [];
      this.learningProbe = undefined;
      this.cleanEligible = this.store.readSettings().autoAdFree &&
        !this.learning.readRules().some((rule: LearnedRule) => rule.bundle === bundle);
      this.cleanSamples = 0; this.cleanFirstAt = 0; this.cleanLastAt = 0; this.cleanFinished = false;
    }

    if (bundle !== this.recordedBundle && this.mayDiscover(bundle)) {
      this.learning.recordSeenApp(bundle);
      this.recordedBundle = bundle;
      this.names.requestSoon();
    } else if (!discoverableBundle(bundle)) { this.recordedBundle = ''; }

    this.health.begin('manual-learning');
    const manualRule = await this.manual.scan(driver, bundle);
    if (manualRule) {
      this.adFree.evidence(bundle); this.learning.recordSeenApp(bundle);
      this.record(bundle, 'learned', '手动点击已确认，规则已保存并直接启用');
      this.reminder.showLearned(this.learning.displayName(bundle), true).catch(() => {});
    }
    if (this.manual.active(bundle)) {
      this.cleanEligible = false; this.sessionAttempted = true;
      this.setState('watching', '强化学习中：由你点击关闭，暂不自动操作'); return;
    }
    if (this.verificationBundle) {
      await this.verifyDismissal(driver, bundle);
      return;
    }
    if (!this.allowedBySettings(bundle) && !this.mayDiscover(bundle)) {
      if (discoverableBundle(bundle)) {
        const settings = this.store.readSettings();
        this.diagnose(bundle, settings.ignoredPackages.includes(bundle) ? '此应用已暂停：不学习、不点击，可在应用管理中恢复' :
          (!settings.learningEnabled ? '学习新规则已关闭，且此应用当前未允许自动点击' :
            (!settings.discoverApps && !settings.packages.includes(bundle) ? '自动发现已关闭，且此应用未开启：未扫描广告' : '自动跳过总开关已关闭，当前未执行点击')));
      }
      this.setState('waiting', '待命：打开应用即可自动发现；新规则确认后才会点击');
      return;
    }
    const quietSettings = this.store.readSettings();
    const automaticQuiet = quietSettings.autoAdFree && this.adFree.paused(bundle, Date.now(), quietSettings);
    if (automaticQuiet && !this.learning.readRules().some((rule: LearnedRule) => rule.bundle === bundle)) {
      this.cleanEligible = false;
      if (this.status.state !== 'quietApp') { this.diagnose(bundle, '多次完整检查未见广告线索，已暂停此应用的扫描；按 ' + quietSettings.adFreeRecheckDays + ' 天间隔复查，可在应用管理中立即恢复'); }
      this.setState('quietApp', '此应用位于无广告观察名单，暂不读取广告控件'); return;
    }
    if (this.cleanFinished || this.sessionAttempted || Date.now() > this.sessionUntil) {
      if (Date.now() > this.sessionUntil) { this.cleanFinished = true; }
      if (!this.sessionAttempted && this.status.state !== 'sessionComplete') {
        this.diagnose(bundle, '本次启动观察已结束（最长 12 秒），未发送点击。最近判断：' +
          (this.pendingObservation || (this.diagnosticBundle === bundle ? this.diagnosticReason : '未取得可识别的广告控件；不能据此判断是否有广告')));
        this.pendingObservation = '';
      }
      this.setState('sessionComplete', '本次应用启动检查已结束，等待下次进入');
      return;
    }
    this.setState('watching', '正在检查此应用的开屏广告控件');
    if (deviceInfo.sdkApiVersion >= 20) {
      await this.scanSnapshot(driver, bundle);
      return;
    }
    const matchStartedAt: number = Date.now();
    const candidate: Component | undefined = await this.findCandidate(driver, bundle, focusedWindow!);
    const matchMs: number = Date.now() - matchStartedAt;
    if (!candidate || !this.learnedMatch || !await candidate.isEnabled() || !await candidate.isClickable()) {
      return;
    }
    const buttonBounds = await candidate.getBounds();
    const windowBounds = await focusedWindow!.getBounds();
    if (!isSplashButton(buttonBounds, windowBounds)) {
      return;
    }

    if (this.learnedMatch) {
      const rule = this.learnedMatch.rule;
      const width = windowBounds.right - windowBounds.left;
      const height = windowBounds.bottom - windowBounds.top;
      if (Math.abs((buttonBounds.left - windowBounds.left) / width - rule.left) > 0.035 ||
        Math.abs((buttonBounds.top - windowBounds.top) / height - rule.top) > 0.035 ||
        Math.abs((buttonBounds.right - windowBounds.left) / width - rule.right) > 0.035 ||
        Math.abs((buttonBounds.bottom - windowBounds.top) / height - rule.bottom) > 0.035 ||
        await readCandidateLabel(this.learnedMatch) !== rule.label) { return; }
    }
    // Recheck foreground, current settings and approval after all component reads.
    const beforeClickWindow = await foregroundWindow(driver, this.directory);
    if (!beforeClickWindow || await beforeClickWindow.getBundleName() !== bundle ||
      !this.allowedBySettings(bundle) || this.storageFailed || Date.now() > this.sessionUntil || this.isExpired() ||
      (!this.learnedMatch || !this.approvedMatch(this.learnedMatch.rule))) { return; }
    this.sessionAttempted = true;
    this.verificationProcessId = this.processId;
    this.verificationProcessStartedAt = this.processStartedAt;
    this.verifyingRule = this.learnedMatch?.rule;
    this.verifyingMarker = this.learnedMatch?.adMarker;
    if (this.verifyingRule) { this.learning.outcome(this.verifyingRule.key, 'attempt'); }
    this.status.attemptCount += 1;
    this.record(bundle, 'attempt', '已核对前台、应用选择、广告依据和已学习的按钮位置；匹配 ' + matchMs +
      ' ms，复核 ' + (Date.now() - matchStartedAt - matchMs) + ' ms，发现前台至点击 ' +
      (Date.now() - (this.sessionUntil - ENTRY_WINDOW_MS)) + ' ms');
    this.health.begin('input'); this.health.save();
    await candidate.click();
    this.health.input();
    this.status.clickCount += 1;
    this.record(bundle, 'clickSent', 'UiTest 点击调用成功，等待检查广告是否消失');
    this.verificationStartedAt = Date.now();
    this.verificationBundle = bundle;
    this.verificationUntil = this.status.expiresAt === 0 ? Date.now() + 5000 :
      Math.min(Date.now() + 5000, this.status.expiresAt);
    this.absentObservations = 0;
    this.presentObservations = 0;
    this.setState('verifying', '已发送点击，正在核对广告控件是否消失');
  }

  private allowedBySettings(bundle: string): boolean {
    if (this.health.token && !this.supervision.allows(this.health.token)) { return false; }
    if (!validBundle(bundle) || bundle === OWN_BUNDLE) {
      return false;
    }
    const settings = this.store.readSettings();
    return settings.enabled === true && settings.stopRequested !== true && !settings.ignoredPackages.includes(bundle) &&
      Array.isArray(settings.packages) && (settings.packages.includes(bundle) ||
        this.learning.readRules().some((r: LearnedRule) => r.bundle === bundle && r.autoApproved === true &&
          ruleState(r, this.learning.readDecisions()) === 'approved'));
  }

  private mayDiscover(bundle: string): boolean {
    const settings = this.store.readSettings();
    return discoverableBundle(bundle) && settings.learningEnabled && !settings.stopRequested &&
      !settings.ignoredPackages.includes(bundle) && (settings.discoverApps || settings.packages.includes(bundle));
  }

  private isExpired(): boolean {
    return this.status.expiresAt > 0 && Date.now() >= this.status.expiresAt;
  }

  private async findCandidate(driver: Driver, bundle: string, window: UiWindow): Promise<Component | undefined> {
    this.learnedMatch = undefined;
    const settings = this.store.readSettings();
    if (!settings.learningEnabled && !this.learning.readRules().some((rule: LearnedRule) => rule.bundle === bundle)) {
      this.diagnose(bundle, '学习新规则已关闭，且此应用没有已保存规则：未扫描广告');
      return undefined;
    }
    const report = new ScanReport();
    const matchStarted = Date.now();
    this.health.begin('legacy-recognition');
    const found = await findLearnedCandidate(driver, bundle, await window.getBounds(), report);
    if (!found) {
      if (this.observedKeys.length === 0) { this.diagnose(bundle, report.reason); }
      return undefined;
    }
    if (!this.acceptCandidate(bundle, found.rule, Date.now() - matchStarted)) { return undefined; }
    this.diagnose(bundle, '已匹配启用的学习规则');
    this.learnedMatch = found;
    return found.target;
  }

  private acceptCandidate(bundle: string, rule: LearnedRule, matchMs: number): boolean {
    this.learning.resolveCandidate(rule);
    const settings = this.store.readSettings();
    if ((!this.allowedBySettings(bundle) && !this.mayDiscover(bundle)) || Date.now() > this.sessionUntil) { return false; }
    if (this.mayDiscover(bundle) && !this.observedKeys.includes(rule.key)) {
      this.observedKeys.push(rule.key);
      const isNew = !this.learning.readRules().some((r: LearnedRule) => r.key === rule.key);
      const stored = this.learning.observe(rule, settings.autoEnableRules);
      if (stored && isNew) {
        const approved = ruleState(stored, this.learning.readDecisions()) === 'approved';
        this.reminder.showLearned(this.learning.displayName(bundle), approved).catch(() => {});
        if (approved) { this.record(bundle, 'learned', '发现新样式，已按设置自动启用'); }
      }
      if (stored && isNew && ruleState(stored, this.learning.readDecisions()) === 'pending') {
        this.diagnose(bundle, '已保存新规则，请到规则页确认启用');
        this.record(bundle, 'learned', '发现新跳过样式，已保存到规则页，确认启用后才会点击');
      }
    }
    if (!this.approvedMatch(rule)) {
      const stored = this.learning.readRules().find((item: LearnedRule) => item.key === rule.key);
      const state = stored ? ruleState(stored, this.learning.readDecisions()) : '';
      const target = '；识别 ' + matchMs + ' ms，目标「' + (rule.example || rule.label) + '」，位置 ' +
        Math.round(rule.left * 100) + '% / ' + Math.round(rule.top * 100) + '%（左 / 上）';
      const reason = state === 'pending' ? '已发现规则，等待你确认启用' :
        (state === 'suspended' ? '连续确认目标仍在，规则已暂停' : (state === 'rejected' ? '此规则已被停用' :
          (settings.learningEnabled ? '样式与已保存规则不符，等待新样式' : '学习已关闭，未收集新规则')));
      this.diagnose(bundle, reason + target);
      return false;
    }
    if (!this.allowedBySettings(bundle)) {
      this.diagnose(bundle, '规则已确认，应用自动跳过尚未开启'); return false;
    }
    return true;
  }

  private async readDiscovery(driver: Driver, bundle: string, report: ScanReport): Promise<SnapshotCandidate | undefined> {
    const path = this.directory + '/discovery-snapshot.json';
    try { fs.unlinkSync(path); } catch (_) {}
    try {
      const decisions = this.learning.readDecisions();
      const approved = this.learning.readRules().filter((rule: LearnedRule) => rule.bundle === bundle && ruleState(rule, decisions) === 'approved');
      const pack = this.rulePacks.read();
      report.reason = '界面读取：系统未返回有效布局';
      report.collectTrace = this.candidateTraceSession !== bundle + ':' + this.sessionUntil;
      report.imageMarker = undefined; report.imageRegions = []; report.candidateTrace = '';
      const frame = this.foregroundFrame; this.foregroundFrame = new ForegroundFrame();
      const reuseForeground = deviceInfo.sdkApiVersion < 26 && frame.bundle === bundle && !!frame.text &&
        Date.now() - frame.readyAt <= 75 && frame.readyAt - frame.readAt <= SAVED_LAYOUT_READ_MS;
      report.coordinateReadAt = reuseForeground ? frame.readAt : Date.now();
      this.health.begin('discovery-layout');
      const layout = reuseForeground ? frame.text : (await captureLayout(driver, path) ? fs.readTextSync(path) : '');
      report.coordinateReadyAt = reuseForeground ? frame.readyAt : Date.now();
      if (reuseForeground) { hilog.info(0, TAG, 'reuse current foreground layout bundle=%{public}s age=%{public}d', bundle, Date.now() - frame.readyAt); }
      this.health.begin('recognition');
      // Both backends produce a current full tree. Select an approved button
      // before discovery; API 26 retains its native capture and tighter read limit.
      const fastRules = approved.filter((rule: LearnedRule) => !!rule.profile && !!rule.buttonType);
      let candidate = layout && fastRules.length ?
        discoverSnapshot(layout, bundle, report, pack, fastRules, true) : undefined;
      report.approvedSnapshot = !!candidate?.approvedButton && !!candidate?.approvedRuleKey;
      if (report.approvedSnapshot && candidate) { candidate.rule.key = candidate.approvedRuleKey; }
      if (!candidate) { candidate = layout ? discoverSnapshot(layout, bundle, report, pack, approved) : undefined; }
      if (report.androidBridge && !this.recordedAndroidApps.includes(bundle)) {
        this.learning.recordAndroidApp(bundle); this.recordedAndroidApps.push(bundle);
      }
      if (!candidate && report.imageRegions.length) {
        this.health.begin('visual-recognition');
        candidate = await this.visual.discover(driver, bundle, layout, path, report, this.rulePacks.read(),
          bundle + ':' + this.sessionUntil, (rule: LearnedRule) => this.approvedMatch(rule));
      }
      if (!candidate && report.candidateTrace) {
        this.candidateTraceSession = bundle + ':' + this.sessionUntil;
        try { this.learning.saveCandidateTrace(bundle, report.candidateTrace); } catch (_) {}
      }
      if (candidate || report.adEvidence) { this.cleanEligible = false; if (!report.approvedSnapshot) { this.adFree.evidence(bundle); } }
      if (!report.cleanPage) { this.cleanSamples = 0; this.cleanFirstAt = 0; this.cleanLastAt = 0; }
      if (report.cleanPage && this.cleanEligible) {
        const now = Date.now();
        if (this.cleanLastAt > 0 && now - this.cleanLastAt > 2500) { this.cleanSamples = 0; this.cleanFirstAt = 0; }
        this.cleanSamples++; if (!this.cleanFirstAt) { this.cleanFirstAt = now; } this.cleanLastAt = now;
        if (!this.cleanFinished && this.cleanSamples >= 8 && now - this.cleanFirstAt >= CLEAN_STABLE_MS && now <= this.sessionUntil) {
          const settings = this.store.readSettings();
          if (settings.autoAdFree && this.mayDiscover(bundle) &&
            !this.learning.readRules().some((rule: LearnedRule) => rule.bundle === bundle)) {
            const previous = this.adFree.read(settings).find((entry: AdFreeEntry) => entry.bundle === bundle)?.lastCleanAt ?? 0;
            const paused = this.adFree.completeCleanLaunch(bundle, this.sessionUntil - ENTRY_WINDOW_MS, settings);
            const counted = (this.adFree.read(settings).find((entry: AdFreeEntry) => entry.bundle === bundle)?.lastCleanAt ?? 0) > previous;
            this.cleanFinished = true;
            report.reason = '连续稳定观察 6 秒未见广告线索；' + (paused ? '已达到门槛，自动暂停检测' :
              (counted ? '有效检查已计数' : '距上次有效检查不足 30 分钟，本次不重复计数'));
            this.pendingObservation = '';
            this.learning.saveDiagnostic(bundle, report.reason);
            this.record(bundle, paused ? 'quietApp' : 'decision', report.reason);
            this.setState(paused ? 'quietApp' : 'sessionComplete', '本次未见广告检查已结束，等待下次进入');
          }
        }
      }
      if (!candidate && !this.cleanFinished && this.store.readSettings().autoAdFree &&
        !this.learning.readRules().some((rule: LearnedRule) => rule.bundle === bundle)) {
        report.reason += '；未计数：' + (!this.cleanEligible ? '本次进入曾出现广告线索或检测中断' :
          !report.cleanPage ? report.cleanReason : '连续完整观察 ' + Math.min(6, Math.floor((Date.now() - this.cleanFirstAt) / 1000)) + '/6 秒');
      }
      return candidate;
    } finally { try { fs.unlinkSync(path); } catch (_) {} }
  }

  // Execution preflight cannot discover rules, acquire evidence or invoke OCR.
  private async readClickTarget(driver: Driver, bundle: string, selected: LearnedRule,
    report: ScanReport): Promise<SnapshotCandidate | undefined> {
    const path = this.directory + '/discovery-snapshot.json';
    report.reason = '已选规则已删除、停用或不再可用';
    const saved = this.learning.readRules().find((rule: LearnedRule) => rule.key === selected.key);
    if (!saved || ruleState(saved, this.learning.readDecisions()) !== 'approved') { return undefined; }
    report.imageMarker = undefined; report.imageRegions = []; report.collectTrace = false;
    try {
      report.coordinateReadAt = Date.now();
      this.health.begin('click-preflight-layout');
      const captured = await captureLayout(driver, path);
      report.coordinateReadyAt = Date.now();
      const layout = captured ? fs.readTextSync(path) : '';
      const candidate = layout ? discoverSnapshot(layout, bundle, report, this.rulePacks.read(), [saved], true) : undefined;
      return candidate?.approvedButton ? candidate : undefined;
    } finally { try { fs.unlinkSync(path); } catch (_) {} }
  }

  private clickSnapshotExpiry(report: ScanReport): string {
    const captureMs = report.coordinateReadyAt - report.coordinateReadAt;
    const postMs = Date.now() - report.coordinateReadyAt;
    const totalMs = Date.now() - report.coordinateReadAt;
    const timing = '（读取 ' + captureMs + ' ms，读取后复核 ' + postMs + ' ms，总计 ' + totalMs + ' ms）';
    // Saved-button execution tolerates a slower platform export but strictly
    // bounds processing after its return. This is a freshness budget, not
    // a promise about visual onset or input completion time.
    const saved = report.approvedSnapshot;
    const readLimit = saved && deviceInfo.sdkApiVersion < 26 ? SAVED_LAYOUT_READ_MS : 700;
    const postLimit = saved && deviceInfo.sdkApiVersion < 26 ? SAVED_LAYOUT_POST_MS : 300;
    const totalLimit = saved && deviceInfo.sdkApiVersion < 26 ? SAVED_LAYOUT_TOTAL_MS : 800;
    if (captureMs > readLimit) { return '界面读取超过 ' + readLimit + ' ms' + timing; }
    if (postMs > postLimit) { return '读取后复核超过 ' + postLimit + ' ms' + timing; }
    if (totalMs > totalLimit) { return '读取与复核总计超过 ' + totalLimit + ' ms' + timing; }
    return '';
  }

  private async scanSnapshot(driver: Driver, bundle: string): Promise<void> {
    const settings = this.store.readSettings();
    if (!settings.learningEnabled && !this.learning.readRules().some((rule: LearnedRule) => rule.bundle === bundle)) {
      this.diagnose(bundle, '学习新规则已关闭，且此应用没有已保存规则：未扫描广告'); return;
    }
    const started = Date.now();
    const report = new ScanReport();
    const first = await this.readDiscovery(driver, bundle, report);
    if (!first) {
      this.learningProbe = undefined;
      if (this.cleanFinished) { return; }
      if (this.observedKeys.length === 0) {
        if (settings.autoAdFree && !this.learning.readRules().some((rule: LearnedRule) => rule.bundle === bundle)) {
          this.pendingObservation = report.reason;
          this.pendingObservationMs = Math.max(0, Date.now() - started);
        } else { this.diagnose(bundle, report.reason); }
      }
      return;
    }
    this.pendingObservation = '';
    // New learning needs two successive normal scans; do not add native reads.
    // API 24 approved targets can reuse the current validated snapshot.
    if (!report.approvedSnapshot) { this.learning.resolveCandidate(first.rule); }
    let confirmedLearningFrame = false;
    if (!report.approvedSnapshot && !this.learning.readRules().some((rule: LearnedRule) => rule.key === first.rule.key)) {
      const previous = this.learningProbe;
      const age = Date.now() - this.learningProbeAt;
      this.learningProbe = first; this.learningProbeAt = Date.now();
      if (!previous || age > 1500 || previous.windowId !== first.windowId ||
        !sameRuleGeometry(previous.rule, first.rule) ||
        Math.abs(previous.bounds.left - first.bounds.left) > 2 ||
        Math.abs(previous.bounds.top - first.bounds.top) > 2 ||
        Math.abs(previous.bounds.right - first.bounds.right) > 2 ||
        Math.abs(previous.bounds.bottom - first.bounds.bottom) > 2) {
        this.diagnose(bundle, '发现新样式，等待下一帧确认后保存'); return;
      }
      confirmedLearningFrame = true;
    }
    if (!report.approvedSnapshot && !this.acceptCandidate(bundle, first.rule, Date.now() - started)) { return; }
    const matchMs = Date.now() - started;
    // Revalidate only the selected enabled button in a fresh tree.
    // No discovery, rule learning or OCR is permitted on this execution path.
    hilog.info(0, TAG, 'candidate saved=%{public}s read=%{public}d post=%{public}d', String(report.approvedSnapshot), report.coordinateReadyAt - report.coordinateReadAt, Date.now() - report.coordinateReadyAt);
    const currentFrame = report.approvedSnapshot || (deviceInfo.sdkApiVersion < 26 && confirmedLearningFrame);
    if (currentFrame && this.clickSnapshotExpiry(report)) {
      this.diagnose(bundle, '当前快照已超时：' + this.clickSnapshotExpiry(report) + '，丢弃并等待下一帧'); return;
    }
    const freshStarted = Date.now();
    const fresh = currentFrame ? first : await this.readClickTarget(driver, bundle, first.rule, report);
    if (!fresh) { this.diagnose(bundle, '点击复核未通过：' + report.reason); return; }
    if (!currentFrame) { this.learning.resolveCandidate(fresh.rule); }
    if (fresh.rule.key !== first.rule.key || !sameRuleGeometry(fresh.rule, first.rule) ||
      fresh.windowId !== first.windowId ||
      Math.abs(fresh.bounds.left - first.bounds.left) > 2 || Math.abs(fresh.bounds.top - first.bounds.top) > 2 ||
      Math.abs(fresh.bounds.right - first.bounds.right) > 2 || Math.abs(fresh.bounds.bottom - first.bounds.bottom) > 2 ||
      fresh.window.left !== first.window.left || fresh.window.top !== first.window.top ||
      fresh.window.right !== first.window.right || fresh.window.bottom !== first.window.bottom) {
      this.diagnose(bundle, '点击复核：两帧目标或窗口位置发生变化，重新识别'); return;
    }
    const window = await foregroundWindow(driver, this.directory);
    if (!window || await window.getBundleName() !== bundle) {
      this.diagnose(bundle, '点击复核：前台已切换，取消点击'); return;
    }
    if (currentFrame) {
      const bounds = await window.getBounds();
      if (bounds.left !== fresh.window.left || bounds.top !== fresh.window.top ||
        bounds.right !== fresh.window.right || bounds.bottom !== fresh.window.bottom) {
        this.diagnose(bundle, '快速复核：当前窗口范围与快照不同，取消点击'); return;
      }
    }
    const expiry = this.clickSnapshotExpiry(report);
    if (expiry) { this.diagnose(bundle, '点击复核：' + expiry + '，未发送点击，稍后重新读取'); return; }
    if (currentFrame ? !this.currentApprovalAllows(bundle, fresh.rule) : (!this.allowedBySettings(bundle) || !this.approvedMatch(fresh.rule))) {
      this.diagnose(bundle, !this.allowedBySettings(bundle) ? '点击复核：应用已暂停、总开关关闭或会话已结束，取消点击' :
        '点击复核：规则已删除、停用或重新学习，当前目标未获批准，取消点击'); return;
    }
    if (this.storageFailed || Date.now() > this.sessionUntil || this.isExpired()) {
      this.diagnose(bundle, '点击复核：存储异常或本次观察时间已结束'); return;
    }
    // File reads above can take time. Unsent, stale input must remain retryable.
    const finalExpiry = this.clickSnapshotExpiry(report);
    if (finalExpiry) { this.diagnose(bundle, '点击取消：' + finalExpiry + '，未发送点击，稍后重新读取'); return; }
    const clickStarted = Date.now();
    const preflightMs = clickStarted - freshStarted;
    const foregroundMs = clickStarted - (this.sessionUntil - ENTRY_WINDOW_MS);
    this.sessionAttempted = true;
    this.verificationProcessId = this.processId;
    this.verificationProcessStartedAt = this.processStartedAt;
    this.verifyingRule = fresh.rule;
    this.verifyingMarker = fresh.adMarker;
    this.status.attemptCount += 1;
    let inputMs = 0;
    // Consume the opportunity only when calling input. An uncertain input error
    // must not trigger a second tap; record the dispatched attempt even on error.
    try {
      this.health.begin('input'); this.health.save();
      await driver.click(Math.round((fresh.bounds.left + fresh.bounds.right) / 2),
        Math.round((fresh.bounds.top + fresh.bounds.bottom) / 2));
      this.health.input();
      inputMs = Date.now() - clickStarted;
      this.status.clickCount += 1;
      this.verificationStartedAt = Date.now();
      this.verificationBundle = bundle;
      this.verificationUntil = this.status.expiresAt === 0 ? Date.now() + 5000 :
        Math.min(Date.now() + 5000, this.status.expiresAt);
      this.absentObservations = 0; this.presentObservations = 0;
    } finally {
      if (report.approvedSnapshot && !this.observedKeys.includes(fresh.rule.key) && this.mayDiscover(bundle) && this.approvedMatch(fresh.rule)) {
        this.observedKeys.push(fresh.rule.key); this.learning.observe(fresh.rule, this.store.readSettings().autoEnableRules);
      }
      this.learning.outcome(fresh.rule.key, 'attempt');
      this.record(bundle, 'attempt', (currentFrame ? (confirmedLearningFrame ? '两帧学习后复用新快照 ' : '已启用规则新快照匹配 ') : '双快照匹配 ') + matchMs + ' ms，复核 ' + preflightMs +
        ' ms（读取 ' + (report.coordinateReadyAt - report.coordinateReadAt) + ' ms，读取后 ' + (clickStarted - report.coordinateReadyAt) + ' ms），发现前台至点击 ' + foregroundMs + ' ms', clickStarted);
    }
    this.diagnose(bundle, (currentFrame ? '最新布局匹配与当前窗口复核通过；识别 ' : '已匹配启用的学习规则，双快照复核通过；识别 ') + matchMs + ' ms，复核 ' +
      preflightMs + (fresh.approvedButton ? ' ms；已启用按钮匹配，无需广告识别或 OCR；目标「' : fresh.adMarker?.source === 'image-ocr' ? ' ms；广告依据：图片文字识别；目标「' : fresh.adMarker?.source === 'image-memory' ? ' ms；广告依据：已学习布局，无需 OCR；目标「' : ' ms；目标「') + (fresh.rule.example || fresh.rule.label) + '」，点击位置 (' +
      Math.round((fresh.bounds.left + fresh.bounds.right) / 2) + ', ' + Math.round((fresh.bounds.top + fresh.bounds.bottom) / 2) + ')', clickStarted);
    this.record(bundle, 'clickSent', '已点击最新界面中的已确认目标；输入调用 ' + inputMs + ' ms', this.verificationStartedAt);
    this.setState('verifying', '已发送点击，正在核对广告控件是否消失');
  }

  private async readDesktopNames(driver: Driver): Promise<void> {
    const bundles = this.learning.missingAppNames().map((app) => app.bundleName);
    if (!bundles.length) { return; }
    const path = this.directory + '/desktop-names-snapshot.json';
    try {
      try { fs.unlinkSync(path); } catch (_) {}
      if (!await captureLayout(driver, path)) { return; }
      const layout = fs.readTextSync(path);
      const names = desktopAppNames(layout, bundles);
      for (const bundle of Object.keys(names)) {
        if (this.learning.needsName(bundle)) { this.learning.saveAppName(bundle, names[bundle]); }
      }
    } catch (_) { /* Names are optional and must not stop ad detection. */ }
    finally { try { fs.unlinkSync(path); } catch (_) {} }
  }

  private finishObservation(reason: string): void {
    if (!this.pendingObservation) { return; }
    const detail = this.pendingObservation + '\n本轮检查 ' + this.pendingObservationMs + ' ms';
    this.pendingObservation = '';
    this.learning.saveDiagnostic(this.sessionBundle, reason + '；' + detail);
    this.record(this.sessionBundle, 'decision', reason + '；' + detail);
  }

  private diagnose(bundle: string, reason: string, eventAt: number = Date.now()): void {
    if (!discoverableBundle(bundle)) { return; }
    const key = reason.replace(/\d+ ms/g, '# ms');
    if (this.diagnosticBundle === bundle && this.diagnosticKey === key && Date.now() - this.diagnosticAt < 5000) { return; }
    this.diagnosticKey = key;
    this.diagnosticBundle = bundle; this.diagnosticReason = reason; this.diagnosticAt = Date.now();
    const detail = reason + '\n本轮检查 ' + Math.max(0, eventAt - this.scanStartedAt) +
      ' ms · 发现前台后 ' + Math.max(0, eventAt - (this.sessionUntil - ENTRY_WINDOW_MS)) + ' ms';
    this.learning.saveDiagnostic(bundle, detail);
    this.record(bundle, 'decision', detail, eventAt);
  }

  private currentApprovalAllows(bundle: string, current: LearnedRule): boolean {
    if ((this.health.token && !this.supervision.allows(this.health.token)) || !validBundle(bundle) || bundle === OWN_BUNDLE) { return false; }
    const settings = this.store.readSettings();
    if (!settings.enabled || settings.stopRequested || settings.ignoredPackages.includes(bundle)) { return false; }
    const saved = this.learning.readRules().find((rule: LearnedRule) => rule.key === current.key);
    if (!saved || !sameRuleGeometry(saved, current) || ruleState(saved, this.learning.readDecisions()) !== 'approved' ||
      (!settings.packages.includes(bundle) && !saved.autoApproved)) { return false; }
    current.firstSeen = saved.firstSeen; return true;
  }

  private approvedMatch(current: LearnedRule): boolean {
    const stored = this.learning.readRules().find((rule: LearnedRule) => rule.key === current.key);
    const approved = stored !== undefined && sameRuleGeometry(stored, current) &&
      ruleState(stored, this.learning.readDecisions()) === 'approved';
    if (approved && stored) { current.firstSeen = stored.firstSeen; }
    return approved;
  }

  private finishUnverified(message: string): void {
    if (!this.verificationBundle) { return; }
    this.status.unverifiedCount += 1;
    if (this.verifyingRule) { this.learning.outcome(this.verifyingRule.key, 'unverified', this.verifyingRule.firstSeen); }
    this.record(this.verificationBundle, 'unverified', message + '；核对已进行 ' + Math.max(0, Date.now() - this.verificationStartedAt) + ' ms；未计为跳过失败');
    this.setState('unverified', '本次验证结果不确定，不再点击');
    this.verificationBundle = '';
  }

  private async verifyDismissal(driver: Driver, bundle: string): Promise<void> {
    if (this.verifyingRule && !this.learning.readRules().some((rule: LearnedRule) =>
      rule.key === this.verifyingRule!.key && rule.firstSeen === this.verifyingRule!.firstSeen)) {
      this.record(this.verificationBundle, 'cancelled', '原规则已删除或重新学习，结束旧规则的消失核对，不计入新规则统计');
      this.verificationBundle = ''; this.setState('waiting', '规则已更新，等待下次打开应用'); return;
    }
    if (bundle && bundle !== this.verificationBundle) {
      this.finishUnverified('点击后前台已切换，不能据此判断广告是否消失');
      return;
    }
    if (Date.now() >= this.verificationUntil) {
      this.finishUnverified('验证时间已到，未取得足够的稳定样本');
      return;
    }
    if (!bundle || !this.verifyingRule) {
      this.absentObservations = 0; this.presentObservations = 0;
      return;
    }
    let observation: string = 'unknown';
    let livePage: boolean = false;
    if (deviceInfo.sdkApiVersion >= 20) {
      const path = this.directory + '/dismissal-snapshot.json';
      // Temporary tree stays in the app sandbox and is deleted after each read.
      try { fs.unlinkSync(path); } catch (_) {}
      try {
        if (await captureLayout(driver, path)) {
          observation = snapshotTargetState(fs.readTextSync(path), this.verifyingRule, this.verifyingMarker, this.rulePacks.read());
          livePage = observation !== 'unknown';
        }
      } finally { try { fs.unlinkSync(path); } catch (_) {} }
    } else {
      const currentWindow = await foregroundWindow(driver, this.directory);
      if (currentWindow && await currentWindow.getBundleName() === bundle) {
        observation = await learnedTargetState(driver, this.verifyingRule,
          await currentWindow.getBounds(), this.verifyingMarker);
        const visibleNodes = await driver.findComponents(ON.inWindow(bundle));
        livePage = Array.isArray(visibleNodes) && visibleNodes.length > 0;
      }
    }
    const finalWindow = await foregroundWindow(driver, this.directory);
    const finalBundle = finalWindow ? await finalWindow.getBundleName() : '';
    if (finalBundle && finalBundle !== bundle) {
      this.finishUnverified('验证过程中前台切换');
      return;
    }
    const stable = livePage && finalBundle === bundle;
    this.absentObservations = stable && observation === 'absent' ? this.absentObservations + 1 : 0;
    this.presentObservations = stable && observation === 'present' ? this.presentObservations + 1 : 0;
    if (this.absentObservations >= 2 && Date.now() <= this.verificationUntil) {
      this.status.observedDismissedCount += 1;
      this.learning.outcome(this.verifyingRule.key, 'success', this.verifyingRule.firstSeen);
      this.record(bundle, 'observedDismissed', '点击后核对 ' + (Date.now() - this.verificationStartedAt) + ' ms；同一应用中连续两次确认目标「' +
        this.verifyingRule.label + '」及原位置广告标记消失');
      this.setState('observedDismissed', '已观察到本次开屏控件消失');
      const name = this.learning.managedApps([bundle]).find((app) => app.bundleName === bundle)?.label ?? bundle;
      this.reminder.show(runtimeAppLabel(name, this.learning.androidApps().includes(bundle))).catch(() => {});
      this.verificationBundle = '';
    } else if (Date.now() >= this.verificationUntil - 200 && this.presentObservations >= 2) {
      this.status.retainedCount += 1;
      this.learning.outcome(this.verifyingRule.key, 'retained', this.verifyingRule.firstSeen);
      this.record(bundle, 'retained', '核对 ' + (Date.now() - this.verificationStartedAt) + ' ms 后连续两次仍找到目标「' + this.verifyingRule.label + '」，本次启动不再点击');
      this.setState('retained', '已观察到目标仍在');
      this.verificationBundle = '';
    } else if (Date.now() >= this.verificationUntil) {
      this.finishUnverified(observation === 'blocked' ? '跳过目标已消失，但原位置广告标记仍在' : '页面不可读或样本不足（' + observation + '，连续消失样本 ' + this.absentObservations + '）');
    }
  }

  private setState(state: string, message: string): void {
    if (this.status.state !== state) {
      hilog.info(0x0000, TAG, 'state=%{public}s %{public}s', state, message);
    }
    this.status.state = state;
    this.status.message = message;
  }

  private record(bundle: string, result: string, message: string, eventAt: number = Date.now()): void {
    const item: DebugRecord = new DebugRecord();
    item.at = eventAt;
    const verifying = bundle === this.verificationBundle && !!this.verificationProcessId;
    item.processId = verifying ? this.verificationProcessId : this.processId;
    item.processStartedAt = verifying ? this.verificationProcessStartedAt : this.processStartedAt;
    item.bundle = bundle;
    item.result = result;
    item.message = message;
    this.status.history.unshift(item);
    this.status.history.sort((a: DebugRecord, b: DebugRecord) => b.at - a.at);
    // Bound detail volume without turning every step into a separate process.
    const counts: Record<string, number> = {};
    this.status.history = this.status.history.filter((row: DebugRecord) => {
      const key = row.processId + ':' + row.bundle;
      counts[key] = (counts[key] ?? 0) + 1;
      return counts[key] <= 40;
    });
    const ids: string[] = [];
    for (const row of this.status.history) {
      const key = row.processId + ':' + row.bundle;
      if (!ids.includes(key)) { ids.push(key); }
    }
    this.status.history = this.status.history.filter((row: DebugRecord) => ids.indexOf(row.processId + ':' + row.bundle) < 20);
    while (this.status.history.length > 200) {
      const oldest = this.status.history[this.status.history.length - 1];
      this.status.history = this.status.history.filter((row: DebugRecord) => row.processId !== oldest.processId || row.bundle !== oldest.bundle);
    }
    hilog.info(0x0000, TAG, '%{public}s bundle=%{public}s %{public}s', result, bundle, message);
  }

  private reportError(error: BusinessError, message: string, terminal: boolean = true): void {
    const failure = new WorkerFailure();
    failure.at = Date.now(); failure.token = this.health.token; failure.pid = process.pid;
    failure.sessionStartedAt = this.status.startedAt; failure.recoveryAttempt = this.status.recoveryAttempt;
    failure.bundle = this.status.lastBundle; failure.operation = this.health.operation;
    failure.operationAt = this.health.operationAt; failure.heartbeatAt = this.status.heartbeatAt;
    failure.rpcAt = this.health.rpcAt; failure.apiVersion = deviceInfo.sdkApiVersion;
    failure.code = error && (typeof error.code === 'number' || typeof error.code === 'string') ? String(error.code) : 'NO_CODE';
    failure.name = error && typeof error.name === 'string' ? error.name : 'UnknownError';
    failure.message = error && typeof error.message === 'string' ? error.message : String(error);
    failure.stack = error && typeof error.stack === 'string' ? error.stack : '';
    failure.context = message; failure.terminal = terminal;
    // Persist before changing phase to ended or the next worker replaces status.
    try { new SystemExitStore(this.directory).recordWorkerFailure(failure); }
    catch (_) { hilog.error(0x0000, TAG, 'Failed to persist worker failure'); }
    if (!terminal) {
      this.setState('waiting', message);
      this.record(this.status.lastBundle, 'decision', message + '；' + failure.message); return;
    }
    this.status.errorCode = failure.code;
    this.setState('error', message);
    this.record(this.status.lastBundle, 'error', `${message}; phase=${failure.operation}; code=${failure.code}; ${failure.message}`);
    hilog.error(0x0000, TAG, 'terminal phase=%{public}s code=%{public}s name=%{public}s message=%{public}s stack=%{public}s',
      failure.operation, failure.code, failure.name, failure.message, failure.stack);
  }

  private saveStatus(): void {
    this.health.save();
    this.status.heartbeatAt = Date.now();
    this.status.progressAt = this.health.progressAt; this.status.rpcAt = this.health.rpcAt;
    this.status.inputAt = this.health.inputAt; this.status.operation = this.health.operation;
    this.status.operationAt = this.health.operationAt;
    const path: string = this.directory + '/debug-status.json';
    const file: fs.File = fs.openSync(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, JSON.stringify(this.status));
    } finally {
      fs.closeSync(file);
    }
    fs.renameSync(path + '.tmp', path);
  }
}
