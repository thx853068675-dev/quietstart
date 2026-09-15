import { deviceInfo } from '@kit.BasicServicesKit';
import { LocalActivation } from '../../../main/ets/core/LocalActivation';
import { nativeLaunchCommand } from '../../../main/ets/core/AppLaunch';
import { captureLayout } from './LayoutCapture';
import { Driver, ON, ComponentEventType, UIElementInfo, abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { LearningStore, LearnedRule, OWN_BUNDLE } from '../../../main/ets/core/LearningStore';
import { manualSnapshot, manualEventSnapshot, SnapshotCandidate } from './LearningWorker';

export class ManualLearningWorker {
  private store: LearningStore;
  private at: number = 0;
  private armedUntil: number = 0;
  private event?: UIElementInfo;
  private eventAt: number = 0;
  private layout: string = '';
  private layoutAt: number = 0;
  private pending?: SnapshotCandidate;
  private launchAt: number = 0;
  private launchDeadline: number = 0;
  private entered: boolean = false;
  private directory: string;
  private returnedAt: number = 0;
  private delegator?: abilityDelegatorRegistry.AbilityDelegator;
  constructor(directory: string, delegator?: abilityDelegatorRegistry.AbilityDelegator) {
    this.directory = directory; this.store = new LearningStore(directory); this.delegator = delegator;
  }
  private async returnResult(bundle: string): Promise<void> {
    const request = this.store.readManualRequest(); const status = this.store.readManualStatus();
    if (!this.delegator || !request.at || status.at !== request.at || this.returnedAt === request.at ||
      !['saved', 'failed', 'unsupported', 'expired'].includes(status.state)) { return; }
    this.returnedAt = request.at;
    // Do not take focus from an unrelated application after a deliberate switch.
    if (bundle !== request.bundle && bundle !== OWN_BUNDLE) { return; }
    try { await this.delegator.startAbility({ bundleName: OWN_BUNDLE, abilityName: 'EntryAbility', moduleName: 'entry',
      parameters: { quietstartManualResult: request.at.toString() } }); } catch (_) {}
  }
  private arm(driver: Driver, bundle: string): void {
    const generation = this.at; this.armedUntil = Date.now() + 1500;
    driver.createUIEventObserver().once('componentEventOccur', ComponentEventType.COMPONENT_CLICKED,
      { timeout: 1500, on: ON.inWindow(bundle) }, (event: UIElementInfo) => {
        if (this.at === generation && event.bundleName === bundle && event.componentRect && !this.event) {
          this.event = event; this.eventAt = Date.now();
          this.store.saveDiagnostic(bundle, '收到手动点击：' + event.type + '，窗口 ' + event.windowId +
            '，范围 ' + JSON.stringify(event.componentRect));
        }
      });
  }
  async scan(driver: Driver, bundle: string): Promise<LearnedRule | undefined> {
    const r = this.store.readManualRequest();
    if (!r.at || Date.now() > r.until) {
      if (this.at && this.store.readManualStatus().state === 'listening') {
        this.store.saveManualStatus(this.at, 'expired', '60 秒内未收到可确认的关闭点击。可能本次没有广告，或系统未上报该按钮的点击事件。');
      }
      await this.returnResult(bundle);
      this.layout = ''; this.event = undefined; this.pending = undefined; this.at = 0; return undefined;
    }
    if (r.at !== this.at) {
      this.at = r.at; this.armedUntil = 0; this.event = undefined; this.pending = undefined;
      this.layout = ''; this.layoutAt = 0; this.entered = false; this.launchDeadline = 0;
      try {
        if (deviceInfo.sdkApiVersion >= 22 && deviceInfo.sdkApiVersion < 26) {
          // Window-only scans on older systems need not attach the native
          // accessibility client. Attach it before subscribing to real clicks.
          await driver.findComponents(ON.id('quietstart-manual-learn').inWindow(OWN_BUNDLE));
        }
        this.arm(driver, r.bundle);
      }
      catch (_) {
        this.store.saveManualStatus(r.at, 'unsupported', '当前系统未提供控件点击事件，无法完成手动学习。');
        await this.returnResult(bundle); return undefined;
      }
      this.store.saveManualStatus(r.at, 'listening', '请亲自点击广告的跳过或关闭按钮，完成后自动返回。');
    }
    if (this.store.readManualStatus().state === 'launching' && this.launchAt !== r.at) {
      this.launchAt = r.at;
      // Only an explicit active training request may use the authorized shell.
      // Android bridge packages need not exist in the native bundle inventory.
      if (bundle !== OWN_BUNDLE || !this.delegator) {
        this.store.saveManualStatus(r.at, 'failed', '启动已取消，请回到轻启重新开始。'); return undefined;
      }
      try {
        const info = await new LocalActivation(this.directory).readAppEntry(r.bundle);
        if (this.store.readManualRequest().at !== r.at) { return undefined; }
        const native = nativeLaunchCommand(info, r.bundle);
        let output = await new LocalActivation(this.directory).startAppEntry(r.bundle, native ||
          'aa start -b ' + r.bundle + ' -A action.system.home -e entity.system.home');
        if (this.store.readManualRequest().at !== r.at) { return undefined; }
        if (!native && !output.includes('start ability successfully') &&
          this.store.readManualRequest().at === r.at) {
          output = await new LocalActivation(this.directory).startAppEntry(r.bundle,
            'aa start -b ' + r.bundle + ' -A ohos.want.action.home -e entity.system.home');
        }
        if (this.store.readManualRequest().at !== r.at) { return undefined; }
        if (!output.includes('start ability successfully')) {
          this.store.saveDiagnostic(r.bundle, '强化学习启动失败：' + output.slice(0, 500));
          if (/10103101|not installed|not exist|bundle.*not found/i.test(output)) {
            // Both supported home routes have failed. Archive the unusable
            // entry, not its rules; a later real foreground visit revives it.
            if (!native) { this.store.hideApp(r.bundle, 'entry-unavailable'); }
            throw new Error('没有找到可用入口：应用可能已卸载，或卓易通入口已失效。可移出应用列表，或重新安装并打开后再学习');
          }
          throw new Error('应用未能启动，请先从桌面确认它能正常打开；详细错误已记入诊断');
        }
        this.launchDeadline = Date.now() + 10000;
        this.store.saveManualStatus(r.at, 'listening', '正在打开应用，请点击广告的关闭按钮。');
        this.armedUntil = 0;
      } catch (error) {
        this.store.saveManualStatus(r.at, 'failed', (error as Error).message);
      }
      return undefined;
    }
    if (this.store.readManualStatus().state !== 'listening') { await this.returnResult(bundle); return undefined; }
    if (!this.pending && Date.now() >= this.armedUntil) {
      try {
        this.arm(driver, r.bundle);
      } catch (_) {
        this.store.saveManualStatus(r.at, 'unsupported', '当前系统未提供控件点击事件，无法完成手动学习。'); await this.returnResult(bundle); return undefined;
      }
    }
    if (bundle !== r.bundle) {
      // The foreground app launches the target only after this listener is armed.
      if (this.launchDeadline && Date.now() > this.launchDeadline && !this.entered) {
        this.store.saveManualStatus(r.at, 'failed', '启动命令已发送，但 10 秒内未检测到目标窗口。请检查应用是否被锁定或入口已失效。');
        await this.returnResult(bundle); return undefined;
      }
      if (this.entered) { this.layout = ''; this.event = undefined; }
      if (bundle && this.entered) { this.store.saveManualStatus(r.at, 'cancelled', '已离开目标应用，本次学习结束；未改动旧规则。'); }
      return undefined;
    }
    this.entered = true;
    if (this.event && !this.pending) {
      if (this.layoutAt > 0 && this.eventAt - this.layoutAt <= 1800 && this.eventAt >= this.layoutAt) {
        this.pending = manualSnapshot(this.layout, bundle, this.event);
      }
      const event = this.event; this.event = undefined;
      if (!this.pending && deviceInfo.sdkApiVersion >= 22 && deviceInfo.sdkApiVersion < 26 && Date.now() - this.eventAt < 1800) {
        const current = await driver.findWindow({ bundleName: bundle });
        if (current && await current.getBundleName() === bundle) {
          this.pending = manualEventSnapshot(event, await current.getBounds());
        }
      }
      if (!this.pending) {
        this.armedUntil = 0;
        this.store.saveDiagnostic(bundle, '手动学习：未对应唯一控件；类型 ' + event.type + '，标识 ' + event.componentId + '，窗口 ' + event.windowId +
          '，范围 ' + JSON.stringify(event.componentRect) + '，快照间隔 ' + (this.eventAt - this.layoutAt) + ' ms');
        this.store.saveManualStatus(r.at, 'failed', this.layoutAt > 0 && this.eventAt - this.layoutAt <= 1800 ?
          '已收到点击，但无法对应唯一的关闭控件。按钮可能由整页画布绘制，或事件只指向大容器。' :
          '已收到点击，但点击前的界面快照未就绪或已过期。请重试，并等按钮出现后再点击。');
        await this.returnResult(bundle); return undefined;
      }
      if (this.pending) {
        // User demonstration is the authority. Disappearance is an outcome,
        // not a prerequisite for retaining an explicitly identified button.
        const latest = this.store.readManualRequest();
        if (latest.at !== r.at || Date.now() > latest.until) { this.pending = undefined; return undefined; }
        const rule = this.store.observe(this.pending.rule, true);
        if (rule) { this.store.decide(rule.key, 'approved'); }
        this.store.saveManualStatus(r.at, rule ? 'saved' : 'failed', rule ?
          '已按你的点击保存并启用；下次匹配相同按钮直接跳过。原有规则保留。' : '规则未保存，可能已达到 200 条上限。');
        await this.returnResult(bundle);
        this.layout = ''; this.pending = undefined; return rule;
      }
    }
    // On API 24 keep the listener and event processing in the same UiTest
    // connection. Do not create a competing CLI accessibility client here.
    if (deviceInfo.sdkApiVersion >= 22 && deviceInfo.sdkApiVersion < 26) { return undefined; }
    const path = this.directory + '/manual-layout.json';
    let fresh = '';
    const beforeRead = Date.now();
    try { if (await captureLayout(driver, path)) { fresh = fs.readTextSync(path); } }
    catch (_) {
      this.store.saveManualStatus(r.at, 'failed', '系统未能读取当前应用的控件布局，无法核对这次点击。请重新学习。');
      await this.returnResult(bundle); return undefined;
    }
    finally { try { fs.unlinkSync(path); } catch (_) {} }
    if (!this.event || this.eventAt < beforeRead) {
      this.layout = fresh; this.layoutAt = Date.now();
    }
    return undefined;
  }
  active(bundle: string): boolean {
    const r = this.store.readManualRequest();
    const status = this.store.readManualStatus();
    return !!r.at && Date.now() <= r.until && r.bundle === bundle && (status.at !== r.at || ['listening', 'launching'].includes(status.state));
  }
  eventBundle(): string { return this.event && Date.now() - this.eventAt < 1800 ? this.event.bundleName : ''; }
  hasActiveRequest(): boolean { return this.active(this.store.readManualRequest().bundle); }
}
