import { Driver, ON, ComponentEventType, UIElementInfo, abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { LearningStore, LearnedRule, OWN_BUNDLE } from '../../../main/ets/core/LearningStore';
import { manualSnapshot, snapshotTargetState, SnapshotCandidate } from './LearningWorker';

export class ManualLearningWorker {
  private store: LearningStore;
  private at: number = 0;
  private armedUntil: number = 0;
  private event?: UIElementInfo;
  private eventAt: number = 0;
  private layout: string = '';
  private layoutAt: number = 0;
  private pending?: SnapshotCandidate;
  private absent: number = 0;
  private verifyingUntil: number = 0;
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
      this.layout = ''; this.layoutAt = 0; this.absent = 0; this.entered = false;
      try { this.arm(driver, r.bundle); }
      catch (_) {
        this.store.saveManualStatus(r.at, 'unsupported', '当前系统未提供控件点击事件，无法完成手动学习。');
        await this.returnResult(bundle); return undefined;
      }
      this.store.saveManualStatus(r.at, 'listening', '请亲自点击广告的跳过或关闭按钮，完成后自动返回。');
    }
    if (this.store.readManualStatus().state !== 'listening') { await this.returnResult(bundle); return undefined; }
    if (bundle !== r.bundle) {
      // The foreground app launches the target only after this listener is armed.
      if (this.entered) { this.layout = ''; this.event = undefined; }
      if (bundle && this.entered) { this.store.saveManualStatus(r.at, 'cancelled', '已离开目标应用，本次学习结束；未改动旧规则。'); }
      return undefined;
    }
    this.entered = true;
    if (!this.pending && Date.now() >= this.armedUntil) {
      try {
        this.arm(driver, r.bundle);
      } catch (_) {
        this.store.saveManualStatus(r.at, 'unsupported', '当前系统未提供控件点击事件，无法完成手动学习。'); await this.returnResult(bundle); return undefined;
      }
    }
    if (this.event && !this.pending) {
      if (this.layoutAt > 0 && this.eventAt - this.layoutAt <= 1800 && this.eventAt >= this.layoutAt) {
        this.pending = manualSnapshot(this.layout, bundle, this.event);
      }
      const event = this.event; this.event = undefined;
      if (!this.pending) {
        this.armedUntil = 0;
        this.store.saveDiagnostic(bundle, '手动学习：未对应唯一控件；类型 ' + event.type + '，标识 ' + event.componentId + '，窗口 ' + event.windowId +
          '，范围 ' + JSON.stringify(event.componentRect) + '，快照间隔 ' + (this.eventAt - this.layoutAt) + ' ms');
        this.store.saveManualStatus(r.at, 'failed', this.layoutAt > 0 && this.eventAt - this.layoutAt <= 1800 ?
          '已收到点击，但无法对应唯一的关闭控件。按钮可能由整页画布绘制，或事件只指向大容器。' :
          '已收到点击，但点击前的界面快照未就绪或已过期。请重试，并等按钮出现后再点击。');
        await this.returnResult(bundle); return undefined;
      }
      if (this.pending) { this.verifyingUntil = Date.now() + 2400; this.absent = 0; }
    }
    const path = this.directory + '/manual-layout.json';
    let fresh = '';
    const beforeRead = Date.now();
    try { if (await driver.dumpLayout(path)) { fresh = fs.readTextSync(path); } }
    catch (_) {
      this.store.saveManualStatus(r.at, 'failed', '系统未能读取当前应用的控件布局，无法核对这次点击。请重新学习。');
      await this.returnResult(bundle); return undefined;
    }
    finally { try { fs.unlinkSync(path); } catch (_) {} }
    if (this.pending) {
      const state = snapshotTargetState(fresh, this.pending.rule, this.pending.adMarker);
      this.absent = state === 'absent' ? this.absent + 1 : 0;
      if (this.absent >= 2) {
        const latest = this.store.readManualRequest();
        if (latest.at !== r.at || Date.now() > latest.until) { this.pending = undefined; this.layout = ''; return undefined; }
        const rule = this.store.observe(this.pending.rule, true);
        if (rule) { this.store.decide(rule.key, 'approved'); }
        this.store.saveManualStatus(r.at, rule ? 'saved' : 'failed', rule ? '已保存手动识别规则并启用，原有规则保留。' : '规则未保存，可能已达到 200 条上限。');
        await this.returnResult(bundle);
        this.layout = ''; this.pending = undefined; return rule;
      }
      if (Date.now() > this.verifyingUntil) {
        this.store.saveManualStatus(r.at, 'failed', '点击后未确认目标消失，未生成规则。');
        await this.returnResult(bundle);
        this.layout = ''; this.pending = undefined;
      }
    } else if (!this.event || this.eventAt < beforeRead) {
      this.layout = fresh; this.layoutAt = Date.now();
    }
    return undefined;
  }
  active(bundle: string): boolean {
    const r = this.store.readManualRequest();
    const status = this.store.readManualStatus();
    return !!r.at && Date.now() <= r.until && r.bundle === bundle && (status.at !== r.at || status.state === 'listening');
  }
  hasActiveRequest(): boolean { return this.active(this.store.readManualRequest().bundle); }
}
