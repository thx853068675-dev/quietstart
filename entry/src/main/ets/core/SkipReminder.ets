import { notificationManager } from '@kit.NotificationKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LocalStore } from './LocalStore';
import { wantAgent } from '@kit.AbilityKit';

export class ReminderState {
  mode: string = 'unknown';
  errorCode: number = 0;
  message: string = '静音通知，不振动；累计更新同一条通知，点击可查看运行记录。';
  updatedAt: number = 0;
  lastApp: string = '';
  lastPublishedAt: number = 0;
}

// Confirmed dismissals only. The system owns expiry, so no background timer or
// LiveView entitlement probe is needed. A fixed ID replaces rather than stacks.
export class SkipReminder {
  private directory: string;
  private busy: boolean = false;
  private generation: number = 0;
  private pendingReal: boolean = false;
  private readonly id: number = 70601;
  private readonly previewId: number = 70602;
  constructor(directory: string) { this.directory = directory; }
  read(): ReminderState {
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/reminder-status.json')) as ReminderState;
      if (!raw || typeof raw !== 'object' || raw.errorCode === 1003500005 || raw.mode === 'capsule') { return new ReminderState(); }
      return raw;
    } catch (_) { return new ReminderState(); }
  }
  private save(mode: string, message: string, app: string = '', publishedAt: number = 0, code: number = 0): void {
    const previous = this.read();
    const state = new ReminderState(); state.mode = mode; state.message = message; state.updatedAt = Date.now(); state.errorCode = code;
    state.lastApp = app || previous.lastApp || ''; state.lastPublishedAt = publishedAt || previous.lastPublishedAt || 0;
    const path = this.directory + '/reminder-status.json';
    const f = fs.openSync(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(f.fd, JSON.stringify(state)); } finally { fs.closeSync(f); }
    fs.renameSync(path + '.tmp', path);
  }
  private totals(): ReminderTotals {
    try {
      const raw = JSON.parse(fs.readTextSync(this.directory + '/reminder-totals.json')) as ReminderTotals;
      if (Number.isSafeInteger(raw.count) && raw.count >= 0 && typeof raw.lastApp === 'string') { return raw; }
    } catch (_) {}
    return new ReminderTotals();
  }
  private recordSuccess(app: string): void {
    const total = this.totals(); total.count = Math.min(Number.MAX_SAFE_INTEGER, total.count + 1); total.lastApp = app.slice(0, 48);
    const path = this.directory + '/reminder-totals.json';
    const f = fs.openSync(path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { fs.writeSync(f.fd, JSON.stringify(total)); } finally { fs.closeSync(f); }
    fs.renameSync(path + '.tmp', path);
  }
  async show(app: string, preview: boolean = false): Promise<void> {
    // Only the worker records actual confirmed successes. UI previews and
    // duration changes never write this separate counter or reset its value.
    if (!preview) { this.recordSuccess(app); }
    if (!new LocalStore(this.directory).readSettings().remindersEnabled) { return; }
    if (this.busy) { if (!preview) { this.pendingReal = true; } return; }
    await this.publish(preview);
  }
  async showLearned(app: string, approved: boolean): Promise<void> {
    try {
      const config = new LocalStore(this.directory).readSettings();
      if (!config.newRuleRemindersEnabled || !await notificationManager.isNotificationEnabled()) { return; }
      const action = await wantAgent.getWantAgent({
        wants: [{ bundleName: 'com.tonghongxiang.quietstart', abilityName: 'EntryAbility',
          parameters: { quietstartOpenRules: true } }],
        operationType: wantAgent.OperationType.START_ABILITY, requestCode: 70603,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      if (!new LocalStore(this.directory).readSettings().newRuleRemindersEnabled) { return; }
      await notificationManager.publish({ id: 70603, notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isAlertOnce: true, tapDismissed: true, wantAgent: action,
        autoDeletedTime: config.reminderDismissSeconds === 0 ? 0 : Date.now() + config.reminderDismissSeconds * 1000,
        notificationFlags: { soundEnabled: 2, vibrationEnabled: 2, lockScreenEnabled: 2 },
        content: { contentType: 0, normal: { title: '学会一种新样式',
          text: app.slice(0, 48) + (approved ? ' · 规则已启用' : ' · 等待确认启用'), additionalText: '点击查看规则' } } });
      if (!new LocalStore(this.directory).readSettings().newRuleRemindersEnabled) { await notificationManager.cancel(70603); }
    } catch (_) { /* Notification permission never prevents rule persistence. */ }
  }
  async refreshVisible(): Promise<void> {
    if (!new LocalStore(this.directory).readSettings().remindersEnabled) { return; }
    try {
      const active = await notificationManager.getActiveNotifications();
      if (active.some((item: notificationManager.NotificationRequest) => item.id === this.id || item.id === this.previewId)) {
        if (!this.busy) { await this.publish(this.totals().count === 0); }
      }
    } catch (_) { /* The selected duration still applies to the next update. */ }
  }
  private async publish(preview: boolean): Promise<void> {
    this.busy = true;
    const generation = this.generation;
    try {
      if (!await notificationManager.isNotificationEnabled()) {
        this.save('permission', '通知尚未允许，点“通知设置”开启。自动跳过不受影响。'); return;
      }
      const clickAction = await wantAgent.getWantAgent({
        wants: [{ bundleName: 'com.tonghongxiang.quietstart', abilityName: 'EntryAbility',
          parameters: { quietstartOpenRecords: true } }],
        operationType: wantAgent.OperationType.START_ABILITY, requestCode: this.id,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
      const config = new LocalStore(this.directory).readSettings();
      if (generation !== this.generation || !config.remindersEnabled) { return; }
      const total = this.totals();
      const seconds = config.reminderDismissSeconds;
      // Retire the old separate preview ID; every new publication uses one ID.
      try { await notificationManager.cancel(this.previewId); } catch (_) {}
      if (generation !== this.generation || !new LocalStore(this.directory).readSettings().remindersEnabled) { return; }
      await notificationManager.publish({ id: this.id, notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isAlertOnce: true, autoDeletedTime: seconds === 0 ? 0 : Date.now() + seconds * 1000,
        tapDismissed: true, wantAgent: clickAction,
        notificationFlags: { soundEnabled: 2, vibrationEnabled: 2, lockScreenEnabled: 2 },
        content: { contentType: 0 /* SDK NotificationContent uses the legacy BASIC_TEXT enum */,
          normal: { title: preview ? '跳过提醒 · 预览' : '已为你跳过 ' + total.count + ' 次',
            text: preview ? '累计更新同一条通知，预览不计入次数' : '最近：' + total.lastApp + ' · 开屏广告已跳过',
            additionalText: '点击查看运行记录' } } });
      if (generation !== this.generation || !new LocalStore(this.directory).readSettings().remindersEnabled) {
        await notificationManager.cancel(this.id); return;
      }
      if (new LocalStore(this.directory).readSettings().reminderDismissSeconds !== seconds) { this.pendingReal = true; }
      this.save('notification', '同一条通知累计更新；' + (seconds === 0 ? '不自动收起，可手动清除。' :
        '每次更新后 ' + seconds + ' 秒自动收起。') + '横幅显示由系统设置决定。',
        preview ? '' : total.lastApp, preview ? 0 : Date.now());
      if (preview) {
        try {
          const settings = await notificationManager.getNotificationSetting();
          if (settings.bannerEnabled === false) {
            this.save('notification', '预览已发送到通知中心；系统横幅已关闭，可在“通知设置”中开启横幅。');
          }
        } catch (_) {}
      }
    } catch (error) {
      try { this.save('unavailable', '通知发送未完成（' + ((error as BusinessError).code ?? '未知') +
        '），请检查通知设置；自动跳过不受影响。', '', 0, (error as BusinessError).code ?? 0); } catch (_) {}
    } finally {
      this.busy = false;
      if (this.pendingReal) {
        this.pendingReal = false;
        if (new LocalStore(this.directory).readSettings().remindersEnabled) { await this.publish(this.totals().count === 0); }
      }
    }
  }
  async clear(): Promise<void> {
    this.generation++; this.pendingReal = false;
    try { await notificationManager.cancel(this.id); } catch (_) {}
    try { await notificationManager.cancel(this.previewId); } catch (_) {}
  }
}

class ReminderTotals {
  count: number = 0;
  lastApp: string = '';
}
