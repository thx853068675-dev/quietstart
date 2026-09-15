import { StatMetric } from '../components/StatMetric';
import { ButtonSample } from '../components/ButtonSample';
import { RECOGNITION_STRATEGIES, RecognitionStrategy, RecognitionProfile, ruleStrategyId,
  profileForRule, shapeName, contentName, targetName, evidenceName, layerName, ProfileLayer, strategySample } from '../core/RecognitionProfile';
import { WorkerInstaller } from '../core/WorkerInstaller';
import { SupervisionStore } from '../core/SupervisionStore';
import { SystemExitRecord, systemExitTitle, SystemExitStore } from '../core/SystemExitStore';
import { pasteboard } from '@kit.BasicServicesKit';
import { PauseProgress, pauseProgress } from '../core/PauseProgress';
import { strategyProblem, strategyPreview } from '../core/StrategyEditor';
import { RecognitionRule } from '../core/RulePack';
import { RulePackStore } from '../core/RulePackStore';
import { appGroup } from '../core/AppGrouping';
import { AdFreeEntry, AdFreeStore } from '../core/AdFreeStore';
import { ruleStrategy, runtimeAppLabel, InstalledApp, LearnedRule, LearningStore, RuleDecision, LearningDiagnostic, LearnedAppGroup, groupLearnedRules, ruleState } from '../core/LearningStore';
import { notificationManager } from '@kit.NotificationKit';
import { ReminderState, SkipReminder } from '../core/SkipReminder';
import { common, bundleManager } from '@kit.AbilityKit';
import { OnboardingStore } from '../core/OnboardingStore';
import { KeyboardAvoidMode, SymbolGlyphModifier, SegmentButton, SegmentButtonOptions } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { LocalStore, Settings } from '../core/LocalStore';
import { DebugRecord, DebugStatus, DebugStore, DebugProcess, groupDebugRecords, isDebugOnline } from '../core/DebugStore';
import { ActivationState, LocalActivation } from '../core/LocalActivation';
import { RulePhonePreview } from '../components/RulePhonePreview';
import { themeColorMode } from '../core/Theme';

@Entry
@Component
struct Index {
  @StorageLink('quietstartForeground') @Watch('syncForeground') foreground: boolean = true;
  @State private expandedProcess: string = '';
  private rulePacks?: RulePackStore;
  @State strategyRules: RecognitionRule[] = [];
  @State strategyCustom: boolean = false;
  @State strategyEdit: number = -1;
  private detailScroller: Scroller = new Scroller();
  @State strategyAdvanced: boolean = false;
  @State strategyWordsOpen: boolean = false;
  @State strategyFocus: string = '';
  @State strategyRuleKey: string = '';
  @State ruleQuery: string = '';
  @State autoEnableRules: boolean = false;
  @State newRuleReminders: boolean = true;
  @State manualMessage: string = '';
  @State manualActive: boolean = false;
  @State strategyAppQuery: string = '';
  @State strategyExcludeWord: string = '';
  @State pauseOptionsOpen: boolean = false;
  @State connectionStepsOpen: boolean = false;
  @State renameOpen: boolean = false;
  @State strategyExample: string = '';
  @State strategyValue: string = '';
  @State strategyField: string = 'text';
  @State strategyMatch: string = 'contains';
  @State strategyAction: string = 'skip';
  @State strategyLength: string = '12';
  @State strategyExclude: string = '';
  @State strategyBundles: string = '';
  @State rulePackCount: number = 0;
  @State rulePackMessage: string = '';
  @State appVersion: string = '';
  @State @Watch('resetDetailScroll') detail: string = '';
  @State remindersEnabled: boolean = false;
  @State reminderAutoDismiss: boolean = true;
  @State reminderSeconds: number = 5;
  private reminderSliding: boolean = false;
  @State themeMode: string = 'system';
  @State reminderState: ReminderState = new ReminderState();
  private reminder?: SkipReminder;
  @State skipEnabled: boolean = false;
  @State allowedPackages: string[] = [];
  @State debugStatus: DebugStatus = new DebugStatus();
  @State systemExits: SystemExitRecord[] = [];
  @State exitExpanded: number = 0;
  @State supervisionNotice: string = '';
  @State online: boolean = false;
  @State secondsLeft: number = 0;
  @State notice: string = '';
  @State page: number = 0;
  @State query: string = '';
  @State searchEditing: boolean = false;
  @State appFilter: number[] = [0];
  @State appFilterOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: '自动跳过（0）' }, { text: '待观察（0）' }, { text: '已暂停（0）' }], multiply: false, fontSize: 12, selectedFontSize: 12,
    fontColor: $r('app.color.muted'), selectedFontColor: $r('app.color.accent'),
    backgroundColor: $r('app.color.soft'), selectedBackgroundColor: $r('app.color.surface')
  });
  @State @Watch('syncRuleIndex') showAllRules: boolean = false;
  @State @Watch('syncRuleFilter') ruleFilter: number[] = [0];
  @State ruleFilterOptions: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: '待确认（0）' }, { text: '全部规则（0）' }], multiply: false,
    fontColor: $r('app.color.muted'), selectedFontColor: $r('app.color.accent'),
    backgroundColor: $r('app.color.soft'), selectedBackgroundColor: $r('app.color.surface')
  });
  @State wizardOpen: boolean = false;
  @State wizardStep: number = 0;
  private onboarding?: OnboardingStore;
  @State rulePages: Record<string, string> = {};
  @State autoAdFree: boolean = true;
  @State adFreeMinDays: number = 1;
  @State adFreeCleanChecks: number = 3;
  @State adFreeRecheckDays: number = 7;
  @State adFreeEntries: AdFreeEntry[] = [];
  private adFree?: AdFreeStore;
  @State learningEnabled: boolean = true;
  @State managedApps: InstalledApp[] = [];
  @State androidApps: string[] = [];
  @State discoverApps: boolean = true;
  @State ignoredPackages: string[] = [];
  @State editingBundle: string = '';
  @State editingName: string = '';
  @State learnedRules: LearnedRule[] = [];
  @State decisions: RuleDecision[] = [];
  @State diagnostics: LearningDiagnostic[] = [];
  @State advanced: boolean = false;
  @State testing: boolean = false;
  @State testResult: string = '';
  @State debugPort: string = '';
  @State activation: ActivationState = new ActivationState();
  @State activating: boolean = false;
  private activator?: LocalActivation;
  private refreshTimer: number = -1;
  private testTimer: number = -1;
  @State catalogBusy: boolean = false;
  @State catalogMessage: string = '';
  @State learningPreparing: boolean = false;
  private connectionTimer: number = -1;
  private connectionHandledAt: number = 0;
  private catalogSync?: Promise<boolean>;
  private catalogCheckedAt: number = 0;
  private store?: LocalStore;
  private debugStore?: DebugStore;
  private learningStore?: LearningStore;
  private tabsController: HdsTabsController = new HdsTabsController();
  private searchController: SearchController = new SearchController();
  // Keep the last scroll item above the standard floating tab bar and its margin.
  private readonly tabContentBottomSpace: number = 96;

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    try { this.appVersion = bundleManager.getBundleInfoForSelfSync(0).versionName; } catch (_) {}
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const directory: string = context.getApplicationContext().filesDir;
    this.store = new LocalStore(directory);
    this.rulePacks = new RulePackStore(directory);
    this.refreshRulePack();
    this.onboarding = new OnboardingStore(directory);
    const setup = this.onboarding.read();
    this.wizardOpen = !setup.completed && !setup.deferred; this.wizardStep = setup.step;
    this.reminder = new SkipReminder(directory);
    this.debugStore = new DebugStore(directory);
    this.learningStore = new LearningStore(directory);
    this.learningStore.clearLegacyAppIcons();
    this.adFree = new AdFreeStore(directory);
    this.activation = new LocalActivation(directory).readState();
    this.debugPort = this.activation.port;
    this.refresh();
    this.syncForeground();
    if (AppStorage.get<boolean>('quietstartProbe') === true) {
      AppStorage.set<boolean>('quietstartProbe', false);
      this.wizardOpen = false; this.startProbe();
    }
  }

  private refreshRulePack(): void {
    if (!this.rulePacks) { return; }
    const pack = this.rulePacks.read();
    this.strategyRules = pack.rules; this.strategyCustom = this.rulePacks.preferences().rules !== undefined;
    this.rulePackCount = pack.rules.length;
  }

  private openStrategy(): void {
    this.refreshRulePack();
    this.strategyFocus = ''; this.strategyRuleKey = ''; this.strategyWordsOpen = false;
    this.strategyEdit = -1; this.rulePackMessage = ''; this.detail = 'strategy';
  }
  private editStrategy(index: number): void {
    const rule = this.strategyRules[index] || new RecognitionRule();
    this.strategyAdvanced = false; this.strategyAppQuery = ''; this.strategyExcludeWord = ''; this.strategyExample = rule.value ? rule.value + (rule.match === 'contains' ? ' 3秒' : '') : '';
    this.strategyEdit = index; this.strategyValue = rule.value; this.strategyField = rule.field;
    this.strategyMatch = rule.match; this.strategyAction = rule.action; this.strategyLength = rule.maxLength.toString();
    this.strategyExclude = rule.exclude.join('，'); this.strategyBundles = rule.bundles.join('，'); this.rulePackMessage = '';
    this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }
  private resetDetailScroll(): void { this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0 }); }
  private openRecognitionStrategy(rule?: LearnedRule): void {
    this.strategyFocus = rule ? ruleStrategyId(rule) : ''; this.strategyRuleKey = rule?.key ?? '';
    this.strategyEdit = -1; this.strategyWordsOpen = false; this.detail = 'strategy';
  }
  private strategySampleProfile(id: string): RecognitionProfile {
    const rule = this.learnedRules.find((r: LearnedRule) => r.key === this.strategyRuleKey);
    return rule && ruleStrategyId(rule) === id ? profileForRule(rule) : strategySample(id);
  }
  private strategySampleAspect(): number { return this.learnedRules.find((r: LearnedRule) => r.key === this.strategyRuleKey)?.aspect ?? 0.62; }
  private strategyDraft(): RecognitionRule {
    const rule = new RecognitionRule(); rule.id = this.strategyRules[this.strategyEdit]?.id || ('local-' + Date.now());
    rule.value = this.strategyValue.trim(); rule.field = this.strategyField; rule.match = this.strategyMatch;
    rule.action = this.strategyAction; rule.maxLength = Number(this.strategyLength);
    rule.exclude = this.strategyExclude.split(/[,，\n]/).map((v: string) => v.trim()).filter((v: string) => !!v);
    rule.bundles = this.strategyBundles.split(/[,，\n]/).map((v: string) => v.trim()).filter((v: string) => !!v);
    return rule;
  }
  private saveStrategy(): void {
    try {
      const rules = JSON.parse(JSON.stringify(this.strategyRules)) as RecognitionRule[];
      const rule = this.strategyDraft();
      const problem = strategyProblem(rule);
      if (problem) { this.rulePackMessage = problem; return; }
      if (this.strategyEdit === rules.length) { rules.push(rule); } else { rules[this.strategyEdit] = rule; }
      if (!this.rulePacks) { throw new Error('存储尚未就绪，请稍后重试'); }
      this.rulePacks.setLocalRules(rules); this.refreshRulePack(); this.strategyEdit = -1; this.rulePackMessage = '已保存到本机';
    } catch (error) { this.rulePackMessage = '未保存：' + (error as Error).message; }
  }
  private removeStrategy(index: number): void {
    try { this.rulePacks?.setLocalRules(this.strategyRules.filter((_: RecognitionRule, i: number) => i !== index));
      this.refreshRulePack(); this.rulePackMessage = '已移除此条件';
    } catch (error) { this.rulePackMessage = (error as Error).message; }
  }

  private syncForeground(): void {
    if (!this.foreground) {
      this.reminderSliding = false;
      clearInterval(this.connectionTimer); this.connectionTimer = -1;
    }
    if (this.refreshTimer !== -1) { clearInterval(this.refreshTimer); this.refreshTimer = -1; }
    if (this.foreground && this.store) {
      this.refresh();
      if (this.page === 1) { this.syncAppCatalog(); }
      this.refreshTimer = setInterval(() => { this.refresh(); }, 2000);
    }
  }

  aboutToDisappear(): void {
    clearInterval(this.connectionTimer); this.connectionTimer = -1;
    clearInterval(this.refreshTimer);
    clearTimeout(this.testTimer);
  }

  private refresh(): void {
    if (AppStorage.get<boolean>('quietstartOpenRecords') === true) {
      AppStorage.set<boolean>('quietstartOpenRecords', false); this.detail = 'records';
    }
    const config: Settings = this.store?.readSettings() ?? new Settings();
    if (AppStorage.get<boolean>('quietstartOpenRules') === true) {
      AppStorage.set<boolean>('quietstartOpenRules', false);
      this.showAllRules = true; this.ruleFilter = [1]; this.ruleQuery = ''; this.go(2);
    }
    this.autoEnableRules = config.autoEnableRules;
    this.newRuleReminders = config.newRuleRemindersEnabled;
    const request = this.learningStore?.readManualRequest();
    const manual = this.learningStore?.readManualStatus();
    this.manualActive = !!request?.at && request.bundle === this.editingBundle && Date.now() < request.until &&
      (manual?.at !== request.at || ['listening', 'launching'].includes(manual.state));
    this.manualMessage = request?.bundle === this.editingBundle && manual?.at === request.at ? manual.message : '';
    if (this.foreground && request?.at && Date.now() <= request.until + 60000 && manual?.at === request.at &&
      ['saved', 'failed', 'expired', 'unsupported', 'cancelled'].includes(manual.state) && !this.learningStore?.manualResultAcknowledged(request.at)) {
      this.learningStore?.acknowledgeManualResult(request.at);
      this.editingBundle = request.bundle; this.editingName = this.appName(request.bundle); this.detail = 'app';
      this.manualActive = false; this.manualMessage = manual.message;
      this.getUIContext().showAlertDialog({ title: manual.state === 'saved' ? '学习成功' : manual.state === 'cancelled' ? '学习已结束' : '本次未学到规则',
        message: manual.message, confirm: { value: '知道了', action: () => {} } });
    }
    this.skipEnabled = config.enabled === true;
    this.learningEnabled = config.learningEnabled;
    this.autoAdFree = config.autoAdFree;
    this.adFreeMinDays = config.adFreeMinDays; this.adFreeCleanChecks = config.adFreeCleanChecks; this.adFreeRecheckDays = config.adFreeRecheckDays;
    this.adFreeEntries = this.adFree?.read(config) ?? [];
    this.remindersEnabled = config.remindersEnabled;
    if (!this.reminderSliding) {
      this.reminderAutoDismiss = config.reminderDismissSeconds > 0;
      if (config.reminderDismissSeconds > 0) { this.reminderSeconds = config.reminderDismissSeconds; }
    }
    this.themeMode = config.themeMode;
    this.reminderState = this.reminder?.read() ?? new ReminderState();
    this.androidApps = this.learningStore?.androidApps() ?? [];
    this.managedApps = this.learningStore?.managedApps(config.packages, config.ignoredPackages) ?? [];
    this.discoverApps = config.discoverApps;
    this.ignoredPackages = config.ignoredPackages;
    this.learnedRules = this.learningStore?.readRules() ?? [];
    this.decisions = this.learningStore?.readDecisions() ?? [];
    this.diagnostics = this.learningStore?.readDiagnostics() ?? [];
    this.allowedPackages = Array.isArray(config.packages) ? config.packages : [];
    this.allowedPackages = this.allowedPackages.concat(this.learnedRules.filter((r: LearnedRule) =>
      r.autoApproved === true && ruleState(r, this.decisions) === 'approved').map((r: LearnedRule) => r.bundle)).filter((b: string, i: number, all: string[]) => all.indexOf(b) === i);
    this.refreshFilterCounts();
    this.debugStatus = this.debugStore?.readStatus() ?? new DebugStatus();
    this.online = isDebugOnline(this.debugStatus);
    if (this.wizardOpen && this.wizardStep === 2 && this.online) { this.wizardStep = 3; this.onboarding?.save(3); }
    this.secondsLeft = this.online ? Math.max(0, Math.ceil((this.debugStatus.expiresAt - Date.now()) / 1000)) : 0;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.activation = new LocalActivation(context.getApplicationContext().filesDir).readState();
    this.systemExits = new SystemExitStore(context.getApplicationContext().filesDir).read();
    this.supervisionNotice = new SupervisionStore(context.getApplicationContext().filesDir).notice();
    this.activating = this.activation.startedAt > 0 && this.activation.finishedAt === 0 &&
      !this.online;
    if (this.foreground && this.activation.startedAt > this.connectionHandledAt &&
      (this.activating || (this.activation.success && Date.now() - this.activation.finishedAt < 10000))) {
      this.watchConnection();
    }
    const resume = AppStorage.get<string>('quietstartInstallResume') ?? '';
    if (resume) {
      AppStorage.set<string>('quietstartInstallResume', '');
      if (resume === this.activation.installToken && !this.activation.finishedAt && !this.online) {
        this.activateLocally(resume).catch(() => {});
      }
    }
  }

  private refreshFilterCounts(): void {
    const counts: number[] = [0, 0, 0];
    this.managedApps.forEach((app: InstalledApp) => { counts[this.appCategory(app.bundleName)]++; });
    const skipping = '自动跳过（' + counts[0] + '）';
    const observing = '待观察（' + counts[1] + '）';
    const paused = '已暂停（' + counts[2] + '）';
    const pending = '待确认（' + this.pendingCount() + '）';
    const allRules = '全部规则（' + this.learnedRules.length + '）';
    // Replace options only when counts change; leave the selected tab untouched.
    if (this.appFilterOptions.buttons[0].text !== skipping || this.appFilterOptions.buttons[1].text !== observing ||
      this.appFilterOptions.buttons[2].text !== paused) {
      this.appFilterOptions = SegmentButtonOptions.capsule({
        buttons: [{ text: skipping }, { text: observing }, { text: paused }], multiply: false, fontSize: 12, selectedFontSize: 12,
        fontColor: $r('app.color.muted'), selectedFontColor: $r('app.color.accent'),
        backgroundColor: $r('app.color.soft'), selectedBackgroundColor: $r('app.color.surface')
      });
    }
    if (this.ruleFilterOptions.buttons[0].text !== pending || this.ruleFilterOptions.buttons[1].text !== allRules) {
      this.ruleFilterOptions = SegmentButtonOptions.capsule({
        buttons: [{ text: pending }, { text: allRules }], multiply: false,
        fontColor: $r('app.color.muted'), selectedFontColor: $r('app.color.accent'),
        backgroundColor: $r('app.color.soft'), selectedBackgroundColor: $r('app.color.surface')
      });
    }
  }

  private watchConnection(): void {
    if (this.connectionTimer !== -1) { return; }
    // Poll only small connection state files; leave rule/catalog refresh alone.
    this.detail = ''; this.page = 0; this.wizardOpen = false;
    this.tabsController.changeIndex(0);
    this.connectionTimer = setInterval(() => {
      const directory = (this.getUIContext().getHostContext() as common.UIAbilityContext).getApplicationContext().filesDir;
      this.activation = new LocalActivation(directory).readState();
      const status = new DebugStore(directory).readStatus();
      const connected = isDebugOnline(status) && status.startedAt >= this.activation.startedAt;
      if (connected || this.activation.finishedAt > 0) {
        clearInterval(this.connectionTimer); this.connectionTimer = -1;
        this.connectionHandledAt = this.activation.startedAt; this.activating = false;
        if (connected) {
          this.detail = ''; this.page = 0; this.tabsController.changeIndex(0);
          if (this.wizardStep === 2) { this.onboarding?.save(3, true); this.wizardStep = 3; }
        } else { this.detail = 'activation'; this.notice = this.activation.message; }
        this.refresh();
      } else { this.online = false; this.activating = true; }
    }, 250);
  }

  private async activateLocally(resumeToken: string = ''): Promise<void> {
    const resumeHash = resumeToken && resumeToken === this.activation.installToken && !this.activation.finishedAt ? this.activation.installHash : '';
    if ((this.activating && !resumeHash) || this.online) { return; }
    this.activating = true; this.notice = ''; this.supervisionNotice = '';
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.activator?.close();
    this.activator = new LocalActivation(context.getApplicationContext().filesDir,
      (shell, progress) => new WorkerInstaller(context.resourceManager, context.getApplicationContext().filesDir).ensure(shell, progress, resumeHash));
    try {
      const connecting = this.activator.activate(resumeHash ? this.activation.port : this.debugPort);
      this.refresh();
      await connecting;
    }
    catch (error) { this.notice = (error as Error).message; this.detail = 'activation'; }
    this.refresh();
  }

  private async openDeveloperSetup(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await context.startAbility({ bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility', uri: 'about_device', action: 'ohos.want.action.viewData' });
    } catch (_) {
      try {
        await context.startAbility({ bundleName: 'com.huawei.hmos.settings', abilityName: 'com.huawei.hmos.settings.MainAbility' });
        this.notice = '请在系统设置中点击设备名称，进入“关于本机”。';
      } catch (_) { this.notice = '请打开系统设置 → 关于本机，连续快速点击“软件版本”7 次。'; }
    }
  }

  private async openSystemSettings(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try { await context.startAbility({ bundleName: 'com.huawei.hmos.settings', abilityName: 'com.huawei.hmos.settings.MainAbility', uri: 'system_wireless_commissioning', action: 'ohos.want.action.viewData' }); }
    catch (_) { this.notice = '请打开系统设置 → 系统 → 开发者选项 → 无线调试。'; }
  }

  private selectApp(bundle: string, value: boolean): void {
    if (!this.store) { return; }
    this.learningStore?.recordSeenApp(bundle);
    const settings = this.store.readSettings();
    settings.packages = settings.packages.filter((item: string) => item !== bundle);
    settings.ignoredPackages = settings.ignoredPackages.filter((item: string) => item !== bundle);
    if (value) { this.adFree?.release(bundle); settings.packages.push(bundle); } else { settings.ignoredPackages.push(bundle); }
    this.saveSettings(settings, value ? '已开启此应用；只有确认过的规则才会点击。' : '已暂停此应用的学习和跳过，重新开启后才会继续。');
  }

  private setLearning(value: boolean): void {
    if (!this.store) { return; }
    const settings = this.store.readSettings();
    settings.learningEnabled = value;
    this.saveSettings(settings, value ? '持续学习已开启，打开应用即可收集开屏样式。' : '已暂停收集新规则，已确认的规则仍可使用。');
  }

  private isQuietApp(bundle: string): boolean {
    return !this.ignoredPackages.includes(bundle) && this.autoAdFree && this.adFreeEntries.some((x: AdFreeEntry) => x.bundle === bundle && x.updatedAt <= Date.now() && x.pausedUntil > Date.now()) &&
      !this.learnedRules.some((rule: LearnedRule) => rule.bundle === bundle);
  }
  private releaseQuietApp(bundle: string): void {
    try { this.adFree?.release(bundle); this.notice = '已恢复检测，重新打开此应用即可检查开屏广告。'; this.refresh(); }
    catch (_) { this.notice = '恢复未完成，请重试。'; }
  }
  private setAutoAdFree(value: boolean): void {
    if (!this.store) { return; }
    const settings = this.store.readSettings(); settings.autoAdFree = value;
    this.saveSettings(settings, value ? '已开启保守自动名单，多次完整检查后才会暂停扫描。' : '已关闭自动名单，所有未手动暂停的应用恢复正常检测。');
  }

  private adFreeValue(key: string): number {
    return key === 'days' ? this.adFreeMinDays : (key === 'checks' ? this.adFreeCleanChecks : this.adFreeRecheckDays);
  }
  private adjustAdFree(key: string, delta: number): void {
    if (!this.store) { return; }
    const settings = this.store.readSettings();
    if (key === 'days') { settings.adFreeMinDays = Math.max(1, Math.min(7, settings.adFreeMinDays + delta)); }
    else if (key === 'checks') { settings.adFreeCleanChecks = Math.max(2, Math.min(20, settings.adFreeCleanChecks + delta)); }
    else { settings.adFreeRecheckDays = Math.max(1, Math.min(30, settings.adFreeRecheckDays + delta)); }
    this.store.saveSettings(settings); this.refresh();
  }

  private async syncAppCatalog(force: boolean = false): Promise<boolean> {
    if (this.catalogSync) { return this.catalogSync; }
    if (!this.online || !this.learningStore) { return false; }
    if (!force && Date.now() - this.catalogCheckedAt < 30000) { return true; }
    this.catalogBusy = true;
    const directory = (this.getUIContext().getHostContext() as common.UIAbilityContext).getApplicationContext().filesDir;
    const started = Date.now();
    this.catalogSync = new LocalActivation(directory).readInstalledApps().then((text: string) => {
      const removed = this.learningStore?.syncNativeCatalog(text, started) ?? 0;
      this.catalogCheckedAt = Date.now();
      this.catalogMessage = removed ? '已移出 ' + removed + ' 个已卸载应用，规则保留' : '';
      this.refresh(); return true;
    }).catch(() => {
      this.catalogMessage = '暂未同步，已保留现有列表'; return false;
    }).finally(() => { this.catalogBusy = false; this.catalogSync = undefined; });
    return this.catalogSync;
  }
  private removeManagedApp(): void {
    const bundle = this.editingBundle;
    this.getUIContext().showAlertDialog({ title: '移出应用列表？',
      message: '保留规则和备注名。再次打开此应用后会自动恢复到列表。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '移出', action: () => {
        if (this.learningStore?.readManualRequest().bundle === bundle) { this.learningStore?.cancelManualLearning(); }
        this.learningStore?.hideApp(bundle); this.go(1); this.refresh();
      } }
    });
  }

  private async startManualLearning(): Promise<void> {
    if (!this.online) { this.notice = '请先完成本机连接，再开始强化学习。'; return; }
    if (this.learningPreparing) { return; }
    const bundle = this.editingBundle; this.learningPreparing = true;
    try {
      if (!await this.syncAppCatalog(true)) { this.notice = '暂时无法检查应用状态，请确认本机连接后重试。'; return; }
      if (bundle !== this.editingBundle || this.detail !== 'app' || !this.foreground) { return; }
      if (this.learningStore?.appUnavailable(bundle)) { this.notice = '应用已卸载或已移出列表。重新安装并打开后可再次学习，原有规则已保留。'; return; }
      this.searchController.stopEditing(); this.searchEditing = false;
      this.learningStore?.startManualLearning(bundle);
      if (this.store) {
        const settings = this.store.readSettings();
        settings.ignoredPackages = settings.ignoredPackages.filter((b: string) => b !== this.editingBundle);
        if (!settings.packages.includes(this.editingBundle)) { settings.packages.push(this.editingBundle); }
        this.store.saveSettings(settings); this.adFree?.release(this.editingBundle);
      }
      this.notice = ''; this.refresh();
      const request = this.learningStore?.readManualRequest();
      if (!request?.at) { throw new Error('学习请求未保存'); }
      let ready = false;
      for (let attempt = 0; attempt < 80; attempt++) {
        if (this.learningStore?.readManualRequest().at !== request.at) { return; }
        const status = this.learningStore?.readManualStatus();
        if (status?.at === request.at) {
          if (status.state !== 'listening') { this.refresh(); return; }
          ready = true; break;
        }
        await new Promise<void>((resolve) => { setTimeout(resolve, 100); });
      }
      if (!ready || !this.foreground) {
        this.learningStore?.saveManualStatus(request.at, 'failed', ready ? '轻启已离开前台，请返回后重新开始。' : '工作模块未能及时准备点击监听，请确认本机连接在线后重试。');
        this.refresh(); return;
      }
      // Resolve the declared entry on the phone; this also handles bridge apps
      // that are absent from the native bundle catalog and icons inside folders.
      this.learningStore?.saveManualStatus(request.at, 'launching', '正在打开应用…');
      this.refresh();
    } catch (_) { this.notice = '未能准备强化学习，请检查本机连接后重试。'; }
    finally { this.learningPreparing = false; }
  }
  private setAutoEnable(value: boolean): void {
    if (!this.store) { return; }
    const settings = this.store.readSettings(); settings.autoEnableRules = value;
    this.saveSettings(settings, value ? '以后自动识别的新规则将直接启用；已停用规则保持不变。' : '以后自动识别的新规则需确认启用。');
  }
  private async setNewRuleReminder(value: boolean): Promise<void> {
    if (!this.store) { return; }
    const settings = this.store.readSettings(); settings.newRuleRemindersEnabled = value;
    this.saveSettings(settings, value ? '学到新规则时通知' : '已关闭新规则通知');
    if (value) {
      try { await notificationManager.requestEnableNotification(this.getUIContext().getHostContext() as common.UIAbilityContext); }
      catch (_) { this.notice = '请在系统通知设置中允许轻启通知。'; }
    } else { try { await notificationManager.cancel(70603); } catch (_) {} }
  }
  private deleteRule(rule: LearnedRule): void {
    this.getUIContext().showAlertDialog({
      title: '删除这条规则？',
      message: '仅删除' + this.appName(rule.bundle) + '当前这条规则及其统计，其他规则保留。以后再次识别到此样式时，可重新学习。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => {
        try { this.learningStore?.deleteRule(rule.key); this.notice = '已删除这条规则，其他规则保留。'; }
        catch (_) { this.notice = '未能删除规则，请重试。'; }
        this.refresh();
      } }
    });
  }
  private resetRules(bundle: string): void {
    const count = this.learnedRules.filter((rule: LearnedRule) => rule.bundle === bundle).length;
    if (!count || !this.learningStore || !this.store) { return; }
    this.getUIContext().showAlertDialog({
      title: '重新学习' + this.appName(bundle) + '？',
      message: '将删除此应用的全部 ' + count + ' 条规则、启用状态和规则统计。重新打开此应用并出现广告后，会重新收集；新规则仍需你确认。此操作也会恢复此应用的学习，并开启“学习新规则”。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除并重新学习', action: () => {
        try {
          this.learningStore!.resetAppRules(bundle);
          this.adFree?.release(bundle);
          const settings = this.store!.readSettings();
          settings.learningEnabled = true;
          settings.ignoredPackages = settings.ignoredPackages.filter((item: string) => item !== bundle);
          if (!settings.packages.includes(bundle)) { settings.packages.push(bundle); }
          this.store!.saveSettings(settings);
          this.rulePages = {};
          this.notice = '已删除规则。重新打开' + this.appName(bundle) + '，出现开屏广告后会重新学习；新规则需确认启用。';
        } catch (_) { this.notice = '重新学习设置未全部完成，请检查规则和学习开关后重试。'; }
        this.refresh();
      } }
    });
  }

  private decide(rule: LearnedRule, state: string): void {
    try {
      if (state === 'approved' && this.store) {
        const settings = this.store.readSettings();
        if (!settings.packages.includes(rule.bundle)) { settings.packages.push(rule.bundle); }
        settings.ignoredPackages = settings.ignoredPackages.filter((bundle: string) => bundle !== rule.bundle);
        this.store.saveSettings(settings);
      }
      this.learningStore?.decide(rule.key, state);
      this.notice = state === 'approved' ? '规则已启用，下次进入该应用时生效。' : '规则已停用。';
    } catch (_) { this.notice = '规则保存失败，请重试。'; }
    this.refresh();
  }

  private appCategory(bundle: string): number {
    return appGroup(bundle, this.allowedPackages, this.ignoredPackages, this.learnedRules,
      this.decisions, this.adFreeEntries, this.autoAdFree, Date.now());
  }

  private appStatus(bundle: string): string {
    if (this.ignoredPackages.includes(bundle)) { return '手动暂停 · 不学习、不点击'; }
    if (this.isQuietApp(bundle)) { return '多次未见广告 · 自动暂停，定期复查'; }
    const ownRules = this.learnedRules.filter((rule: LearnedRule) => rule.bundle === bundle);
    const pending = ownRules.filter((rule: LearnedRule) => ruleState(rule, this.decisions) === 'pending').length;
    if (this.appCategory(bundle) === 0) { return pending > 0 ? '自动跳过已就绪 · ' + pending + ' 个新样式待确认' : '已确认规则就绪 · 自动跳过'; }
    if (pending > 0) { return '发现 ' + pending + ' 个新样式 · 待你确认'; }
    if (ownRules.some((rule: LearnedRule) => ruleState(rule, this.decisions) === 'approved')) { return '规则已就绪 · 待开启自动跳过'; }
    if (ownRules.length > 0) { return '规则未启用或需要复核 · 可查看规则'; }
    return this.learningEnabled ? '尚未确认广告 · 打开应用后继续观察' : '学习新规则已关闭 · 开启后继续观察';
  }

  private observationProgress(bundle: string): PauseProgress {
    const result = new PauseProgress();
    if (this.learnedRules.some((rule: LearnedRule) => rule.bundle === bundle)) {
      result.remaining = '已有广告规则，不参与自动暂停'; return result;
    }
    if (!this.autoAdFree) { result.remaining = '自动暂停未开启'; return result; }
    const value = pauseProgress(this.adFreeEntries.find((entry: AdFreeEntry) => entry.bundle === bundle),
      this.adFreeMinDays, this.adFreeCleanChecks, Date.now());
    if (!this.online) { value.remaining += '；连接后继续'; }
    else if (!this.learningEnabled) { value.remaining += '；开启学习后继续'; }
    else if (!this.discoverApps && !this.allowedPackages.includes(bundle)) { value.remaining += '；开启自动发现后继续'; }
    return value;
  }

  private appGroupHint(): string {
    return this.appFilter[0] === 0 ? (this.online && this.skipEnabled ? '已启用的广告样式会自动跳过。' : '连接并开启自动跳过后生效。') :
      (this.appFilter[0] === 1 ? '稳定观察 6 秒，信息不稳最多 12 秒；有效检查间隔 30 分钟，广告线索会重置进度。' :
        '自动暂停定期复查，手动暂停需自行恢复。');
  }

  private appList(): InstalledApp[] {
    const query = this.query.trim().toLowerCase();
    return this.managedApps.filter((app: InstalledApp) =>
      this.appCategory(app.bundleName) === (this.appFilter[0] ?? 0) &&
      (!query || app.label.toLowerCase().includes(query) || app.bundleName.toLowerCase().includes(query)))
      .sort((a: InstalledApp, b: InstalledApp) => Number(this.allowedPackages.includes(b.bundleName)) -
        Number(this.allowedPackages.includes(a.bundleName)) || a.label.localeCompare(b.label, 'zh-CN'));
  }

  private ruleList(): LearnedRule[] {
    const query = this.ruleQuery.trim().toLowerCase();
    return this.learnedRules.filter((rule: LearnedRule) => (!query ||
      [this.appName(rule.bundle), rule.bundle, rule.label, rule.example ?? '', ruleStrategyId(rule), ruleStrategy(rule)].join(' ').toLowerCase().includes(query)) &&
      (this.showAllRules || ['pending', 'suspended'].includes(ruleState(rule, this.decisions))));
  }

  private stateLabel(rule: LearnedRule): string {
    const state = ruleState(rule, this.decisions);
    if (state === 'approved') { return '已启用'; }
    if (state === 'rejected') { return '已停用'; }
    if (state === 'suspended') { return '已暂停，待重新确认'; }
    return '待确认';
  }

  private setEnabled(value: boolean): void {
    if (!this.store) { return; }
    const settings: Settings = this.store.readSettings();
    settings.enabled = value;
    settings.testUntil = 0;
    this.saveSettings(settings, value ? '总开关已开启；仅执行已开启应用中你确认过的规则。' : '总开关已关闭，调试会话不再发送新的点击。');
  }

  private endSession(): void {
    if (!this.store) { return; }
    const settings: Settings = this.store.readSettings();
    settings.enabled = false;
    settings.stopRequested = true;
    const directory = (this.getUIContext().getHostContext() as common.UIAbilityContext).getApplicationContext().filesDir;
    try {
      new SupervisionStore(directory).stop();
      new SystemExitStore(directory).markExpected('user-stop');
    } catch (_) { this.notice = '未能停止自动恢复，请重试。'; return; }
    this.saveSettings(settings, '正在结束连接与自动恢复。需要时可重新连接。');
  }

  private copyExitRecords(): void {
    const directory = (this.getUIContext().getHostContext() as common.UIAbilityContext).getApplicationContext().filesDir;
    pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
      new SystemExitStore(directory).exportText())).then(() => { this.notice = '完整退出记录已复制';
      this.getUIContext().getPromptAction().showToast({ message: '完整退出记录已复制' });
    }).catch(() => { this.getUIContext().getPromptAction().showToast({ message: '复制失败，请重试' }); });
  }

  private exitAction(row: SystemExitRecord): string {
    if (row.selfStopVerified) { return '已核对监督终止命令、进程与时间'; }
    if (row.recoveryReason) { return '恢复检查第 ' + row.recoveryAttempt + ' 次 · ' + row.recoveryReason; }
    if (row.expectedAction === 'activation') { return '本机连接启动'; }
    if (row.expectedAction === 'module-install') { return '工作模块安装'; }
    if (row.expectedAction === 'worker-restart') { return '工作会话重建'; }
    if (row.expectedAction === 'user-stop') { return '主动结束连接'; }
    return row.recoveryAttempt > 0 ? '恢复检查第 ' + row.recoveryAttempt + ' 次' : '';
  }

  @Builder
  healthPage() {
    Column({ space: 12 }) {
      Text('退出记录').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).width('100%')
      Text('包含系统退出原因与恢复时间线。未提供的原因不作推断。')
        .fontSize(12).lineHeight(19).fontColor($r('app.color.muted')).width('100%')
      Button('复制完整记录').id('quietstart-copy-exits').height(40).width('100%').enabled(true)
        .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.copyExitRecords(); })
      if (!this.systemExits.length) { Text('尚无系统退出记录').fontSize(14).fontColor($r('app.color.muted')) }
      ForEach(this.systemExits, (row: SystemExitRecord) => {
        Column({ space: 8 }) {
          Row() {
            Text(systemExitTitle(row)).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).layoutWeight(1)
            Text(this.timeLabel(row.detail?.timestamp || row.capturedAt)).fontSize(11).fontColor($r('app.color.muted'))
          }.width('100%')
          if (this.exitAction(row)) { Text(this.exitAction(row)).fontSize(12).fontColor($r('app.color.accent')).width('100%') }
          Text(row.message || row.detail?.exitMsg || '系统未附带详细说明').fontSize(12).lineHeight(20).fontColor($r('app.color.muted')).width('100%')
          Text(row.environment.osVersion + ' · API ' + row.environment.apiVersion + ' · 轻启 ' + row.environment.appVersion)
            .fontSize(11).lineHeight(18).fontColor($r('app.color.muted')).width('100%')
          if (this.exitExpanded === row.capturedAt) {
            Text(JSON.stringify(row, null, 2)).fontSize(11).lineHeight(17).fontColor($r('app.color.muted')).width('100%').copyOption(CopyOptions.InApp)
          }
          Button(this.exitExpanded === row.capturedAt ? '收起详细数据' : '查看详细数据').height(30).width('100%')
            .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).fontSize(12)
            .onClick(() => { this.exitExpanded = this.exitExpanded === row.capturedAt ? 0 : row.capturedAt; })
        }.padding(14).width('100%').borderRadius(16).backgroundColor($r('app.color.surface'))
      }, (row: SystemExitRecord) => row.capturedAt.toString())
    }.width('100%')
  }

  private saveSettings(settings: Settings, success: string): void {
    try {
      this.store?.saveSettings(settings);
      this.notice = success;
    } catch (_) {
      this.notice = '保存失败，请重试；当前设置以重新读取的结果为准。';
    }
    this.refresh();
  }

  private startProbe(): void {
    clearTimeout(this.testTimer);
    this.testResult = '';
    this.testing = true;
    this.testTimer = setTimeout(() => {
      if (this.testResult.length === 0) {
        this.testResult = '30 秒内未收到测试点击，请返回检查本机连接。';
      }
    }, 30000);
  }

  @Builder
  appIcon(bundle: string, size: number) {
    Stack() {
      Text(this.appName(bundle).substring(0, 1)).fontSize(size * 0.45).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent'))

    }.width(size).height(size).backgroundColor($r('app.color.soft')).borderRadius(size * 0.25).clip(true)
  }

  private appName(bundle: string): string {
    if (bundle === 'com.tonghongxiang.quietstart') { return '轻启'; }
    return runtimeAppLabel(this.managedApps.find((app: InstalledApp) => app.bundleName === bundle)?.label || this.learningStore?.displayName(bundle) || bundle || '暂无', this.androidApps.includes(bundle));
  }

  private resultLabel(result: string): string {
    if (result === 'decision') { return '识别详情'; }
    if (result === 'quietApp') { return '暂停扫描'; }
    if (result === 'cancelled') { return '本次核对已取消'; }
    if (result === 'learned') { return '发现新规则'; }
    if (result === 'attempt') { return '准备点击'; }
    if (result === 'clickSent') { return '点击已发送'; }
    if (result === 'observedDismissed') { return '观察到消失'; }
    if (result === 'unverified') { return '消失未确认'; }
    if (result === 'retained') { return '目标仍在'; }
    if (result === 'error') { return '会话错误'; }
    return result;
  }

  private timeLabel(value: number): string {
    if (value <= 0) { return '--:--:--'; }
    const date: Date = new Date(value);
    return date.getHours().toString().padStart(2, '0') + ':' +
      date.getMinutes().toString().padStart(2, '0') + ':' + date.getSeconds().toString().padStart(2, '0');
  }

  private rulePosition(rule: LearnedRule): string {
    const x = (rule.left + rule.right) / 2;
    const y = (rule.top + rule.bottom) / 2;
    return (y < 0.38 ? '上方' : (y > 0.70 ? '下方' : '中部')) +
      (x < 0.35 ? '偏左' : (x > 0.65 ? '偏右' : '居中'));
  }

  private ruleGroups(): LearnedAppGroup[] {
    return groupLearnedRules(this.ruleList());
  }

  private groupRenderKey(group: LearnedAppGroup): string {
    return group.bundle + ':' + group.rules.map((rule: LearnedRule) => rule.key + ':' + rule.lastSeen + ':' +
      rule.attempts + ':' + rule.successes + ':' + rule.retained + ':' + rule.unverified + ':' + ruleState(rule, this.decisions)).join(';');
  }

  private rulePageIndex(group: LearnedAppGroup): number {
    const index = group.rules.findIndex((rule: LearnedRule) => rule.key === this.rulePages[group.bundle]);
    return Math.max(0, index);
  }

  private rememberRulePage(group: LearnedAppGroup, index: number): void {
    if (!group.rules[index] || this.rulePages[group.bundle] === group.rules[index].key) { return; }
    const pages: Record<string, string> = {};
    for (const bundle of Object.keys(this.rulePages)) { pages[bundle] = this.rulePages[bundle]; }
    pages[group.bundle] = group.rules[index].key;
    this.rulePages = pages;
  }

  onBackPress(): boolean {
    if (this.wizardOpen) { if (this.wizardStep > 0 && !this.activating) { this.wizardMove(this.wizardStep - 1); } return true; }
    if (this.testing) { this.testing = false; clearTimeout(this.testTimer); return true; }
    if (this.detail) { if (this.detail === 'strategy' && this.strategyEdit >= 0) { this.strategyEdit = -1; } else { this.detail = ''; } return true; }
    return false;
  }

  private syncRuleFilter(): void { if (this.showAllRules !== (this.ruleFilter[0] === 1)) { this.showAllRules = this.ruleFilter[0] === 1; } }
  private syncRuleIndex(): void { if (this.ruleFilter[0] !== (this.showAllRules ? 1 : 0)) { this.ruleFilter = [this.showAllRules ? 1 : 0]; } }
  private wizardMove(step: number): void { this.wizardStep = step; this.onboarding?.save(step); }
  private startWizard(): void { this.detail = ''; this.wizardOpen = true; this.wizardMove(0); }
  private finishWizard(): void {
    if (!this.online) { this.wizardMove(2); return; }
    this.onboarding?.save(3, true); this.wizardOpen = false; this.go(0);
  }
  private deferWizard(): void { this.onboarding?.save(this.wizardStep, false, true); this.wizardOpen = false; this.go(0); }

  private go(index: number): void {
    this.detail = ''; this.page = index; this.notice = '';
    this.searchController.stopEditing(); this.searchEditing = false;
    this.tabsController.changeIndex(index);
    if (index === 1) { this.syncAppCatalog(); }
  }
  private approvedCount(): number {
    return this.learnedRules.filter((rule: LearnedRule) => this.allowedPackages.includes(rule.bundle) && ruleState(rule, this.decisions) === 'approved').length;
  }
  private pendingCount(): number {
    return this.learnedRules.filter((rule: LearnedRule) => ['pending', 'suspended'].includes(ruleState(rule, this.decisions))).length;
  }
  private guideTitle(): string {
    if (!this.online) { return '先让轻启连接上手机'; }
    if (!this.skipEnabled) { return '自动跳过未开启'; }
    if (this.pendingCount()) { return '' + this.pendingCount() + ' 条规则待确认'; }
    if (!this.approvedCount()) { return '打开应用，开始学习'; }
    return '规则已就绪，正常使用即可';
  }
  private guideDescription(): string {
    if (this.activating) { return this.activation.message || '正在建立本机连接…'; }
    if (!this.online) { return '开启开发者模式和无线调试，填写端口即可连接。'; }
    if (!this.skipEnabled) { return '开启后，仅跳过你已确认并启用的广告样式。'; }
    if (this.pendingCount()) { return '核对按钮文字与位置，启用后自动跳过。'; }
    if (!this.approvedCount()) { return '遇到开屏广告后，到规则页确认样式。'; }
    return '新样式会出现在规则页。';
  }
  private guideAction(): string {
    if (this.activating) { return ''; }
    if (!this.online) { return '开始本机连接'; }
    if (!this.skipEnabled) { return '开启自动跳过'; }
    if (this.pendingCount()) { return '去确认规则'; }
    if (!this.approvedCount() && (!this.learningEnabled || !this.discoverApps)) { return '开启自动发现与学习'; }
    return '';
  }
  private continueGuide(): void {
    if (!this.online) { this.detail = 'activation'; }
    else if (!this.skipEnabled) { this.setEnabled(true); }
    else if (this.pendingCount()) { this.ruleQuery = ''; this.showAllRules = false; this.go(2); }
    else if (!this.approvedCount() && (!this.learningEnabled || !this.discoverApps)) { this.setDiscovery(true); this.setLearning(true); }

  }
  private setDiscovery(value: boolean): void {
    if (!this.store) { return; }
    const settings = this.store.readSettings(); settings.discoverApps = value;
    this.saveSettings(settings, value ? '自动发现已开启。打开应用即可记录，新规则仍需你确认。' : '已暂停发现新应用；已开启的应用按现有设置工作。');
  }
  private editApp(app: InstalledApp): void {
    this.renameOpen = false;
    this.editingBundle = app.bundleName; this.editingName = app.label === app.bundleName ? '' : app.label; this.detail = 'app';
    this.syncAppCatalog();
  }
  private renameApp(): void {
    try { this.learningStore?.renameSeenApp(this.editingBundle, this.editingName); this.notice = '名称已保存。'; this.refresh(); }
    catch (error) { this.notice = (error as Error).message; }
  }

  private setTheme(mode: string): void {
    if (!this.store || this.themeMode === mode) { return; }
    const settings = this.store.readSettings();
    const previous = settings.themeMode; settings.themeMode = mode;
    try {
      this.store.saveSettings(settings);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.getApplicationContext().setColorMode(themeColorMode(mode));
      this.themeMode = mode;
    } catch (_) {
      settings.themeMode = previous; this.store.saveSettings(settings);
      this.notice = '外观切换未完成，请重试。';
    }
  }

  private async setReminders(value: boolean): Promise<void> {
    if (!this.store) { return; }
    const settings = this.store.readSettings(); settings.remindersEnabled = value;
    this.saveSettings(settings, value ? '已开启跳过通知，可预览实际效果。' : '已关闭跳过提醒。');
    if (!value) { await this.reminder?.clear(); return; }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      if (!await notificationManager.isNotificationEnabled()) { await notificationManager.requestEnableNotification(context); }
    } catch (_) { this.notice = '通知尚未允许，可点“通知设置”开启；自动跳过不受影响。'; }
  }
  private async setReminderDuration(seconds: number): Promise<void> {
    if (!this.store) { return; }
    const settings = this.store.readSettings(); settings.reminderDismissSeconds = seconds;
    this.store.saveSettings(settings); this.refresh();
    await this.reminder?.refreshVisible(); this.refresh();
  }
  private async previewReminder(): Promise<void> {
    await this.reminder?.show('轻启', true); this.refresh();
  }
  private async openNotificationSettings(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try { await notificationManager.openNotificationSettings(context); }
    catch (_) { this.notice = '请打开系统设置 → 通知 → 轻启，允许通知。'; }
  }

  @Builder
  titleBlock(title: string, subtitle: string) {
    Column({ space: 5 }) {
      Text(title).fontSize(27).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
      if (subtitle) { Text(subtitle).fontSize(13).lineHeight(20).fontColor($r('app.color.muted')) }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4, bottom: 4 })
  }

  @Builder
  sectionLabel(title: string) {
    Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
  }

  @Builder
  actionRow(title: string, subtitle: string, action: () => void) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
        Text(subtitle).fontSize(12).lineHeight(18).fontColor($r('app.color.muted'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(25).fontColor($r('app.color.muted'))
    }.width('100%').padding(16).borderRadius(18).backgroundColor($r('app.color.surface'))
      .onClick(action)
  }

  @Builder
  homePage() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 5 }) {
          Row({ space: 8 }) {
            Text('轻启').fontSize(27).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
            if (this.appVersion) {
              Text('v' + this.appVersion).id('quietstart-app-version').fontSize(12).fontColor($r('app.color.muted'))
            }
          }.alignItems(VerticalAlign.Center)
          Text('每次开启，直达所想。').fontSize(13).lineHeight(20).fontColor($r('app.color.muted'))
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 4, bottom: 4 })
        Column({ space: 16 }) {
          Row({ space: 12 }) {
            Text(this.activating ? '正在连接轻启' : this.online ? (this.skipEnabled ? '正在为你守候' : '暂歇片刻') : '连接后，即刻开始')
              .fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink')).layoutWeight(1)
            Row({ space: 4 }) {
              Text(this.activating ? '连接中' : this.online ? '在线' : '未连接').id('quietstart-debug-status').fontSize(12)
                .fontColor(this.online ? $r('app.color.accent') : $r('app.color.warning'))
              if (this.online) { SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([$r('app.color.accent')]).width(14).height(20) }
            }.id('quietstart-connection-details').height(32).alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center)
              .padding({ left: 12, right: 10 }).borderRadius(16)
              .backgroundColor(this.online ? $r('app.color.soft') : $r('app.color.warning_bg'))
              .accessibilityText(this.online ? '在线，查看连接详情' : '未连接')
              .onClick(() => { if (this.online) { this.detail = 'activation'; } })
          }.width('100%')
          Row() {
            Text('自动跳过').fontSize(15).fontColor($r('app.color.ink')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.skipEnabled }).id('quietstart-toggle').enabled(!this.activating)
              .selectedColor($r('app.color.accent')).onChange((value: boolean) => { this.setEnabled(value); })
          }.width('100%')
          Row({ space: 14 }) {
            StatMetric({ value: this.managedApps.filter((app: InstalledApp) => this.appCategory(app.bundleName) === 0).length.toString(), label: '跳过应用' })
            StatMetric({ value: this.approvedCount().toString(), label: '启用规则' })
            StatMetric({ value: this.debugStatus.clickCount.toString(), label: '本次已跳过' })
          }.width('100%')
          Divider().color($r('app.color.line'))
          Column({ space: 6 }) {
            if (this.activating) { LoadingProgress().width(24).height(24).color($r('app.color.accent')) }
            if (this.online) {
              Text(this.guideTitle()).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).width('100%')
            }
            Text(this.guideDescription()).fontSize(13).lineHeight(21).fontColor($r('app.color.muted')).width('100%')
          }.width('100%')
          if (this.guideAction()) {
            Button(this.guideAction()).id('quietstart-next-step').width('100%').height(44)
              .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
              .onClick(() => { this.continueGuide(); })
          }
          if (!this.online && this.supervisionNotice) {
            Text(this.supervisionNotice).id('quietstart-recovery-notice').fontSize(12).lineHeight(20).fontColor($r('app.color.warning')).width('100%')
          }
          if (this.online) { this.sessionDetails(); }
        }.width('100%').padding(18).borderRadius(22).backgroundColor($r('app.color.surface'))
        Row({ space: 12 }) {
          Button('运行记录').id('quietstart-home-records').height(44).layoutWeight(1).fontSize(14)
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
            .onClick(() => { this.detail = 'records'; })
          Button('使用指南').id('quietstart-home-help').height(44).layoutWeight(1).fontSize(14)
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
            .onClick(() => { this.detail = 'help'; })
        }.width('100%')
      }.padding({ left: 20, right: 20, top: 12, bottom: this.tabContentBottomSpace })
        .width('100%').constraintSize({ maxWidth: 620 })
    }.align(Alignment.Top).width('100%').height('100%')
  }

  @Builder
  appsPage() {
    Column({ space: 12 }) {
      if (!this.searchEditing) {
        Row() {
          Text('应用').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink')).layoutWeight(1)
          Button(this.catalogBusy ? '同步中' : '刷新').id('quietstart-refresh-apps').height(32).fontSize(13)
            .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).enabled(!this.catalogBusy && this.online)
            .onClick(() => { this.syncAppCatalog(true); })
        }.width('100%')
        if (this.catalogMessage) { Text(this.catalogMessage).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
      }
      Search({ value: this.query, placeholder: '搜索当前分区的应用', controller: this.searchController }).id('quietstart-app-search')
        .width('100%').height(46).flexShrink(0).textFont({ size: 16 }).fontColor($r('app.color.ink'))
        .placeholderColor($r('app.color.muted')).searchIcon({ color: $r('app.color.accent') })
        .cancelButton({ style: CancelButtonStyle.INPUT, icon: { color: $r('app.color.muted') } })
        .backgroundColor($r('app.color.surface')).borderRadius(14)
        .onChange((value: string) => { this.query = value; })
        .onEditChange((value: boolean) => { this.searchEditing = value; })
      SegmentButton({ options: this.appFilterOptions, selectedIndexes: $appFilter })
        .id('quietstart-filter-apps').width('100%')
      Text(this.appGroupHint()).id('quietstart-app-group-hint').fontSize(12).lineHeight(19)
        .fontColor($r('app.color.muted')).width('100%')
      if (this.appList().length === 0) {
        Text(this.query.trim() ? '未找到应用，请切换分区查找。' :
          (this.appFilter[0] === 0 ? '暂无应用，确认并启用规则后会出现在这里。' :
            (this.appFilter[0] === 1 ? '暂无应用，连接后打开新应用即可记录。' : '暂无暂停应用。')))
          .fontSize(14).fontColor($r('app.color.muted')).padding(24)
      }
      if (!this.online || !this.discoverApps || !this.learningEnabled) {
        Button(!this.online ? '先完成本机连接' : '开启自动发现与学习').id('quietstart-discovery-ready').height(38).width('100%')
          .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
          .onClick(() => { if (!this.online) { this.detail = 'activation'; } else { this.setDiscovery(true); this.setLearning(true); } })
      }
      List({ space: 8 }) {
        ForEach(this.appList(), (app: InstalledApp) => {
          ListItem() {
            Row({ space: 10 }) {
              this.appIcon(app.bundleName, 40)
              Column({ space: 4 }) {
                Text(runtimeAppLabel(app.label === app.bundleName ? '未命名应用' : app.label, this.androidApps.includes(app.bundleName))).onClick(() => { this.editApp(app); }).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.appStatus(app.bundleName)).fontSize(11).lineHeight(16).fontColor($r('app.color.muted'))
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.appCategory(app.bundleName) === 1) {
                  if (this.observationProgress(app.bundleName).progress) {
                    Text(this.observationProgress(app.bundleName).progress).id('quietstart-observation-progress-' + app.bundleName)
                      .fontSize(12).lineHeight(18).fontColor($r('app.color.accent'))
                  }
                  Text(this.observationProgress(app.bundleName).remaining).id('quietstart-observation-remaining-' + app.bundleName)
                    .fontSize(11).lineHeight(16).fontColor($r('app.color.muted'))
                }
                if (app.label === app.bundleName) {
                  Text(app.bundleName).fontSize(10).fontColor($r('app.color.muted')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button('管理').id('quietstart-manage-' + app.bundleName).fontSize(12).height(32)
                .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.editApp(app); })
            }.padding(12).width('100%').borderRadius(16).backgroundColor($r('app.color.surface'))
          }
        }, (app: InstalledApp) => app.bundleName)
      }.layoutWeight(1).width('100%').contentEndOffset(this.tabContentBottomSpace)
    }.padding({ left: 20, right: 20, top: 12 }).width('100%').layoutWeight(1)
  }

  @Builder
  ruleDetails(rule: LearnedRule, index: number) {
    Column({ space: 10 }) {
      RulePhonePreview({ rule: rule, positionLabel: this.rulePosition(rule) })
      Row({ space: 10 }) {
        StatMetric({ value: rule.successes.toString(), label: '确认消失' })
        StatMetric({ value: rule.attempts.toString(), label: '尝试点击' })
        StatMetric({ value: rule.unverified.toString(), label: '未能确认' })
      }.width('100%')
      Row({ space: 10 }) {
        if (ruleState(rule, this.decisions) === 'approved') {
          Button('停用此规则').id('quietstart-reject-' + rule.key).height(42).layoutWeight(1).fontSize(14)
            .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent'))
            .onClick(() => { this.decide(rule, 'rejected'); })
        } else {
          Button('启用此规则').id('quietstart-approve-' + rule.key).height(42).layoutWeight(1).fontSize(14)
            .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
            .onClick(() => { this.decide(rule, 'approved'); })
        }
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([$r('app.color.muted')])
        }.id('quietstart-delete-rule-' + rule.key).width(42).height(42)
          .backgroundColor($r('app.color.soft')).accessibilityText('删除当前规则')
          .onClick(() => { this.deleteRule(rule); })
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Center).id('quietstart-rule-' + rule.key)
  }

  @Builder
  learningPage() {
    Scroll() {
      Column({ space: 14 }) {
        this.titleBlock('规则', '')
        SegmentButton({ options: this.ruleFilterOptions, selectedIndexes: $ruleFilter })
          .id('quietstart-rule-filter').width('100%')
        Search({ value: this.ruleQuery, placeholder: '搜索应用、按钮或策略编号' }).id('quietstart-rule-search')
          .width('100%').height(42).textFont({ size: 14 }).fontColor($r('app.color.ink'))
          .placeholderColor($r('app.color.muted')).searchIcon({ color: $r('app.color.accent') })
          .cancelButton({ style: CancelButtonStyle.INPUT, icon: { color: $r('app.color.muted') } })
          .backgroundColor($r('app.color.surface')).borderRadius(14)
          .onChange((value: string) => { this.ruleQuery = value; this.syncRuleIndex(); })
        if (this.ruleList().length === 0) {
          Column({ space: 12 }) {
            Text(this.ruleQuery ? '没有匹配的规则' : (this.showAllRules ? '暂无规则' : (this.learnedRules.length ? '暂时没有待确认规则' : '从打开一个应用开始'))).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
            Text(this.ruleQuery ? '换个关键词，或切换至全部规则。' : (this.learnedRules.length ? '遇到新样式时，再来确认。' : '连接并开启学习后，打开应用即可发现新样式。'))
              .fontSize(13).lineHeight(21).fontColor($r('app.color.muted'))
            if (this.learnedRules.length && !this.showAllRules) {
              Button('查看全部规则').height(40).width('100%')
                .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
                .onClick(() => { this.showAllRules = true; })
            }
          }.padding(20).borderRadius(18).backgroundColor($r('app.color.surface')).width('100%').alignItems(HorizontalAlign.Start)
        }
        ForEach(this.ruleGroups(), (group: LearnedAppGroup) => {
          Column({ space: 4 }) {
            Row({ space: 8 }) {
              Row({ space: 8 }) {
                this.appIcon(group.bundle, 32)
                Text(this.appName(group.bundle)).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink')).layoutWeight(1)
              }.layoutWeight(1)
              Button(ruleStrategyId(group.rules[this.rulePageIndex(group)]) + ' · ' +
                (group.rules[this.rulePageIndex(group)].origin === 'manual' ? '手动学习' : '自动识别'))
                .id('quietstart-rule-strategy-' + group.rules[this.rulePageIndex(group)].key)
                .width(104).height(28).padding({ left: 6, right: 6 }).fontSize(11)
                .fontColor($r('app.color.accent')).backgroundColor($r('app.color.soft'))
                .accessibilityText('查看识别策略 ' + ruleStrategyId(group.rules[this.rulePageIndex(group)]) + ' ' + ruleStrategy(group.rules[this.rulePageIndex(group)]))
                .onClick(() => { this.openRecognitionStrategy(group.rules[this.rulePageIndex(group)]); })
              Row() {
                Text(group.rules.length > 1 ? (this.rulePageIndex(group) + 1) + ' / ' + group.rules.length : '1 条规则')
                  .id('quietstart-rule-page-' + group.bundle).fontSize(12).fontColor($r('app.color.muted'))
              }.layoutWeight(1).justifyContent(FlexAlign.End)
            }.width('100%')
            if (group.rules.length > 1) {
              Swiper() {
                ForEach(group.rules, (rule: LearnedRule, index: number) => {
                  Column() { this.ruleDetails(rule, index); }.width('100%').padding({ bottom: 28 })
                }, (rule: LearnedRule) => rule.key)
              }.id('quietstart-rule-swiper-' + group.bundle).width('100%').index(this.rulePageIndex(group))
                .displayCount(1).vertical(false).autoPlay(false).loop(false).nestedScroll(SwiperNestedScrollMode.SELF_ONLY)
                .indicator(Indicator.dot().itemWidth(6).itemHeight(6).selectedItemWidth(6).selectedItemHeight(6)
                  .color($r('app.color.line')).selectedColor($r('app.color.accent')).bottom(0))
                .onChange((index: number) => { this.rememberRulePage(group, index); })
            } else { this.ruleDetails(group.rules[0], 0); }
          }.id('quietstart-rule-group-' + group.bundle).padding(16).width('100%')
            .backgroundColor($r('app.color.surface')).borderRadius(20)
        }, (group: LearnedAppGroup) => this.groupRenderKey(group))
      }.padding({ left: 20, right: 20, top: 12, bottom: this.tabContentBottomSpace }).width('100%').constraintSize({ maxWidth: 620 })
    }.align(Alignment.Top).width('100%').height('100%')
  }

  @Builder
  themeOption(mode: string, label: string) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 9 }) {
        Stack({ alignContent: Alignment.TopStart }) {
          if (mode === 'system') {
            Rect().width('50%').height('100%').fill('#19261F').position({ x: '50%', y: 0 })
          }
          Column({ space: 6 }) {
            Rect().width('45%').height(5).radius(3).fill(mode === 'dark' ? '#A6C5B4' : '#6C8C7C')
            Rect().width('100%').height(16).radius(4).fill(mode === 'dark' ? '#304137' : '#DDE7E0')
            Rect().width('70%').height(4).radius(2).fill(mode === 'dark' ? '#667E6D' : '#B7C7BD')
          }.width('100%').padding(10).alignItems(HorizontalAlign.Start)
        }.height(64).width('100%').backgroundColor(mode === 'dark' ? '#19261F' : '#F4F7F5').borderRadius(10).clip(true)
        Row({ space: 4 }) {
          Text(label).fontSize(12).fontWeight(this.themeMode === mode ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.themeMode === mode ? $r('app.color.accent') : $r('app.color.ink'))
          if (this.themeMode === mode) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(13).fontColor([$r('app.color.accent')])
          }
        }.width('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      }.padding(8).width('100%')
    }.id('quietstart-theme-' + mode).layoutWeight(1).borderRadius(14)
      .backgroundColor(this.themeMode === mode ? $r('app.color.soft') : Color.Transparent)
      .border({ width: this.themeMode === mode ? 1.5 : 0.5, color: this.themeMode === mode ? $r('app.color.accent') : $r('app.color.line') }).borderRadius(14)
      .accessibilityText(label + (this.themeMode === mode ? '，已选择' : '，未选择')).onClick(() => { this.setTheme(mode); })
  }

  @Builder
  adFreeControl(label: string, key: string, minimum: number, maximum: number, unit: string) {
    Row({ space: 8 }) {
      Text(label).fontSize(14).fontColor($r('app.color.ink')).layoutWeight(1)
      Button('−').id('quietstart-adfree-' + key + '-minus').width(32).height(32).padding(0).fontSize(18)
        .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).enabled(this.adFreeValue(key) > minimum)
        .accessibilityText('减少' + label).onClick(() => { this.adjustAdFree(key, -1); })
      Text(this.adFreeValue(key) + ' ' + unit).id('quietstart-adfree-' + key + '-value').fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink')).width(52).textAlign(TextAlign.Center)
      Button('+').id('quietstart-adfree-' + key + '-plus').width(32).height(32).padding(0).fontSize(18)
        .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).enabled(this.adFreeValue(key) < maximum)
        .accessibilityText('增加' + label).onClick(() => { this.adjustAdFree(key, 1); })
    }.width('100%')
  }

  @Builder
  strategyPage() {
    Column({ space: 14 }) {
      if (this.strategyEdit >= 0) {
        Column({ space: 14 }) {
          Text(this.strategyField === 'text' ? '1 · 按钮上写着什么？' : '1 · 图标的说明是什么？').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).width('100%')
          Text((this.strategyAction === 'skip' ? '寻找跳过按钮' : '寻找关闭按钮') + (this.strategyBundles ? ' · 仅限指定应用' : ' · 适用所有应用'))
            .fontSize(12).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.strategyValue, placeholder: '例如：跳过、关闭广告' }).id('quietstart-strategy-value').maxLength(24)
            .height(46).backgroundColor($r('app.color.soft')).fontColor($r('app.color.ink'))
            .onChange((v: string) => { this.strategyValue = v; this.rulePackMessage = ''; })
          if (this.strategyValue.trim().length < 2) { Text('至少填写 2 个字，例如“跳过”。').fontSize(12).fontColor($r('app.color.warning')).width('100%') }
          Text('常用文字').fontSize(12).fontColor($r('app.color.muted')).width('100%')
          Row({ space: 8 }) {
            ForEach(['跳过', '关闭', '关闭广告'], (word: string) => {
              Button(word).height(30).fontSize(13).layoutWeight(1).backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent'))
                .onClick(() => { this.strategyValue = word; this.strategyAction = word === '跳过' ? 'skip' : 'close';
                  this.strategyExample = word + (this.strategyMatch === 'contains' ? ' 3秒' : ''); this.rulePackMessage = ''; })
            })
          }.width('100%')
          Text('2 · 怎样算匹配？').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).width('100%')
          Row({ space: 8 }) {
            Button('包含这些字').id('quietstart-match-contains').height(38).fontSize(14).layoutWeight(1)
              .backgroundColor(this.strategyMatch === 'contains' ? $r('app.color.accent') : $r('app.color.soft'))
              .fontColor(this.strategyMatch === 'contains' ? $r('app.color.on_accent') : $r('app.color.muted')).onClick(() => { this.strategyMatch = 'contains'; })
            Button('只有这些字').id('quietstart-match-equals').height(38).fontSize(14).layoutWeight(1)
              .backgroundColor(this.strategyMatch === 'equals' ? $r('app.color.accent') : $r('app.color.soft'))
              .fontColor(this.strategyMatch === 'equals' ? $r('app.color.on_accent') : $r('app.color.muted')).onClick(() => { this.strategyMatch = 'equals'; })
          }.width('100%')
          Text(this.strategyMatch === 'contains' ? '例如：' + this.strategyValue + ' 3秒（可包含倒计时，仍受字数限制）' : '只匹配“' + this.strategyValue + '”，前后不能带倒计时（忽略空格）')
            .fontSize(12).lineHeight(18).fontColor($r('app.color.muted')).width('100%')
        Column({ space: 10 }) {
          Text('试一试，不会点击手机').fontSize(16).fontColor($r('app.color.ink')).width('100%')
          TextInput({ text: this.strategyExample, placeholder: '输入广告按钮上的完整文字' }).id('quietstart-strategy-example').maxLength(64)
            .height(44).backgroundColor($r('app.color.soft')).fontColor($r('app.color.ink')).onChange((v: string) => { this.strategyExample = v; })
          Text((strategyPreview(this.strategyDraft(), this.strategyExample) === '能匹配这段文字' ? '✓ ' : '· ') + strategyPreview(this.strategyDraft(), this.strategyExample)).id('quietstart-strategy-preview')
            .fontSize(14).lineHeight(20).fontColor(strategyPreview(this.strategyDraft(), this.strategyExample) === '能匹配这段文字' ? $r('app.color.accent') : $r('app.color.warning')).width('100%')
          Text('这里只测试文字。实际跳过还需核对应用、广告依据和按钮位置。').fontSize(12).lineHeight(18).fontColor($r('app.color.muted')).width('100%')
        }.padding(16).borderRadius(18).backgroundColor($r('app.color.surface')).width('100%')
          Text('3 · 哪些情况不要匹配？').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.strategyDraft().exclude, (word: string, index: number) => {
              Button(word + ' ×').height(36).fontSize(13).margin({ right: 6, bottom: 6 })
                .accessibilityText('移除排除词 ' + word).backgroundColor($r('app.color.soft')).fontColor($r('app.color.ink'))
                .onClick(() => { this.strategyExclude = this.strategyDraft().exclude.filter((_: string, i: number) => i !== index).join('，'); })
            })
          }.width('100%')
          Row({ space: 8 }) {
            TextInput({ text: this.strategyExcludeWord, placeholder: '添加排除词，如片头' }).id('quietstart-exclude-input').maxLength(24)
              .layoutWeight(1).height(44).backgroundColor($r('app.color.soft')).fontColor($r('app.color.ink'))
              .onChange((value: string) => { this.strategyExcludeWord = value; })
            Button('添加').height(44).enabled(!!this.strategyExcludeWord.trim()).fontColor($r('app.color.accent')).backgroundColor($r('app.color.soft'))
              .onClick(() => { this.strategyExclude = [...this.strategyDraft().exclude, this.strategyExcludeWord.trim()].join('，'); this.strategyExcludeWord = ''; })
          }.width('100%')
          if (this.strategyDraft().exclude.length > 24) { Text('最多保留 24 个排除词，请移除多余项。').fontSize(12).fontColor($r('app.color.warning')) }
          Text('含任一排除词时不匹配。').fontSize(12).fontColor($r('app.color.muted')).width('100%')
        }.padding(16).borderRadius(18).backgroundColor($r('app.color.surface')).width('100%')
        Button(this.strategyAdvanced ? '收起高级设置' : '高级设置 · 通常无需修改').id('quietstart-strategy-advanced')
          .height(38).fontSize(14).width('100%').backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent'))
          .onClick(() => { this.strategyAdvanced = !this.strategyAdvanced; })
        if (this.strategyAdvanced) {
          Column({ space: 12 }) {
            Text('从哪里读取文字').fontSize(14).fontColor($r('app.color.ink')).width('100%')
            Select([{ value: '按钮显示的文字' }, { value: '图标的无障碍说明' }]).selected(this.strategyField === 'text' ? 0 : 1)
              .value(this.strategyField === 'text' ? '按钮显示的文字' : '图标的无障碍说明').onSelect((i: number) => { this.strategyField = i === 0 ? 'text' : 'description'; })
            Text('无障碍说明可用于没有显示文字的关闭图标。').fontSize(12).fontColor($r('app.color.muted')).width('100%')
            Row({ space: 10 }) {
              Text('这是什么按钮').fontSize(14).fontColor($r('app.color.ink')).layoutWeight(1)
              Select([{ value: '跳过广告' }, { value: '关闭广告' }]).selected(this.strategyAction === 'skip' ? 0 : 1)
                .value(this.strategyAction === 'skip' ? '跳过广告' : '关闭广告').onSelect((i: number) => { this.strategyAction = i === 0 ? 'skip' : 'close'; })
            }.width('100%')
            Row({ space: 10 }) {
              Text('按钮总字数上限').fontSize(14).fontColor($r('app.color.ink')).layoutWeight(1)
              TextInput({ text: this.strategyLength }).id('quietstart-strategy-length').type(InputType.Number).width(72).maxLength(2)
                .backgroundColor($r('app.color.soft')).fontColor($r('app.color.ink')).onChange((v: string) => { this.strategyLength = v; })
            }.width('100%')
            if (!Number.isInteger(Number(this.strategyLength)) || Number(this.strategyLength) < this.strategyValue.trim().length || Number(this.strategyLength) > 32) {
              Text('请填写 ' + Math.max(2, this.strategyValue.trim().length) + '～32 的整数。').fontSize(12).fontColor($r('app.color.warning')).width('100%')
            }
            Text('包含倒计时，空格不计。避免把正文长句误当成按钮。').fontSize(12).lineHeight(18).fontColor($r('app.color.muted')).width('100%')
            Text('适用应用').fontSize(14).fontColor($r('app.color.ink')).width('100%')
            Button(this.strategyBundles ? '已限定应用 · 点击恢复所有应用' : '所有应用').height(40).width('100%')
              .fontColor($r('app.color.accent')).backgroundColor($r('app.color.soft')).onClick(() => { this.strategyBundles = ''; })
            TextInput({ text: this.strategyAppQuery, placeholder: '搜索已记录的应用，勾选后仅在这些应用生效' }).id('quietstart-scope-search')
              .height(44).fontColor($r('app.color.ink')).backgroundColor($r('app.color.soft')).onChange((v: string) => { this.strategyAppQuery = v; })
            if (this.strategyAppQuery.trim()) {
              ForEach(this.managedApps.filter((app: InstalledApp) => (app.label + app.bundleName).toLowerCase().includes(this.strategyAppQuery.trim().toLowerCase())).slice(0, 8), (app: InstalledApp) => {
                Button({ type: ButtonType.Normal }) {
                  Column({ space: 3 }) {
                    Text((this.strategyDraft().bundles.includes(app.bundleName) ? '✓ ' : '+ ') + this.appName(app.bundleName)).fontSize(14).fontColor($r('app.color.ink'))
                    Text(app.bundleName).fontSize(11).fontColor($r('app.color.muted'))
                  }.alignItems(HorizontalAlign.Start).width('100%').padding(10)
                }.width('100%').backgroundColor($r('app.color.soft')).borderRadius(12)
                  .onClick(() => { const bundles = this.strategyDraft().bundles; this.strategyBundles = (bundles.includes(app.bundleName) ? bundles.filter((b: string) => b !== app.bundleName) : [...bundles, app.bundleName]).join('，'); })
              }, (app: InstalledApp) => app.bundleName)
              if (!this.managedApps.some((app: InstalledApp) => (app.label + app.bundleName).toLowerCase().includes(this.strategyAppQuery.trim().toLowerCase()))) {
                Text('没有找到已记录的应用，可在下方填写包名。').fontSize(12).fontColor($r('app.color.muted'))
              }
            }
            Text('已选包名 · 可手动补充').fontSize(14).fontColor($r('app.color.ink')).width('100%')
            TextInput({ text: this.strategyBundles, placeholder: '留空适用所有应用' }).backgroundColor($r('app.color.soft'))
              .fontColor($r('app.color.ink')).onChange((v: string) => { this.strategyBundles = v; })
            Text('填写应用包名，如 com.example.app；多个用逗号分隔。').fontSize(12).lineHeight(18).fontColor($r('app.color.muted')).width('100%')
          }.padding(16).borderRadius(18).backgroundColor($r('app.color.surface')).width('100%')
        }
      } else {
        Text('已有规则优先匹配；新样式先读控件，图片文字最后兜底。').fontSize(12).fontColor($r('app.color.muted')).width('100%')
        if (this.strategyFocus) {
          Button('查看全部 8 种识别方式').height(36).width('100%').fontColor($r('app.color.accent')).backgroundColor($r('app.color.soft'))
            .onClick(() => { this.strategyFocus = ''; this.strategyRuleKey = ''; this.resetDetailScroll(); })
        }
        ForEach(RECOGNITION_STRATEGIES.filter((s: RecognitionStrategy) => !this.strategyFocus || this.strategyFocus === s.id), (item: RecognitionStrategy) => {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text(item.id).fontSize(12).fontWeight(FontWeight.Bold).fontColor($r('app.color.accent'))
                .padding({ left: 8, right: 8, top: 5, bottom: 5 }).backgroundColor($r('app.color.soft')).borderRadius(8)
              Text(item.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).layoutWeight(1)
              Text(this.learnedRules.filter((r: LearnedRule) => ruleStrategyId(r) === item.id).length + ' 条').fontSize(11).fontColor($r('app.color.muted'))
            }.width('100%')
            Row({ space: 12 }) {
              ButtonSample({ profile: this.strategySampleProfile(item.id), aspect: this.strategySampleAspect(), sampleWidth: 112, sampleHeight: 64 })
              Text(item.example).fontSize(12).lineHeight(18).fontColor($r('app.color.muted')).layoutWeight(1)
            }.width('100%')
            Text('如何确认 · ' + item.proof).fontSize(12).lineHeight(19).fontColor($r('app.color.ink')).width('100%')
            Text('点击哪里 · ' + item.target).fontSize(12).lineHeight(19).fontColor($r('app.color.muted')).width('100%')
            Text('何时放弃 · ' + item.reject).fontSize(12).lineHeight(19).fontColor($r('app.color.muted')).width('100%')
            if (this.strategyRuleKey) {
              Text('本条规则 · ' + targetName(this.strategySampleProfile(item.id).targetMode) +
                (this.strategySampleProfile(item.id).evidence.length ? '；依据：' + this.strategySampleProfile(item.id).evidence.map((e: string) => evidenceName(e)).join('、') : '；旧规则将在再次匹配时补充样式记录'))
                .fontSize(11).lineHeight(18).fontColor($r('app.color.accent')).width('100%')
              if (this.strategySampleProfile(item.id).layers.length) {
                Text('组成 · ' + this.strategySampleProfile(item.id).layers.map((layer: ProfileLayer) => layerName(layer.role) + ' ' + layer.type).join(' · '))
                  .fontSize(10).lineHeight(17).fontColor($r('app.color.muted')).width('100%')
              }
            }
          }.id('quietstart-strategy-' + item.id).padding(16).borderRadius(18).backgroundColor($r('app.color.surface')).width('100%')
        }, (item: RecognitionStrategy) => item.id)
        Button(this.strategyWordsOpen ? '收起按钮用词' : '按钮用词 · 自定义').width('100%').height(40)
          .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.strategyWordsOpen = !this.strategyWordsOpen; })
        if (this.strategyWordsOpen) {
        Row() {
          Text(this.strategyRules.length + ' 项文字条件').fontSize(17).fontColor($r('app.color.ink')).layoutWeight(1)
          Button('新增').height(32).enabled(this.strategyRules.length < 128).backgroundColor($r('app.color.soft'))
            .fontColor($r('app.color.accent')).onClick(() => { this.editStrategy(this.strategyRules.length); })
        }.width('100%')
        ForEach(this.strategyRules, (rule: RecognitionRule, index: number) => {
          Column({ space: 8 }) {
            Text((rule.field === 'text' ? '按钮文字' : '无障碍描述') + (rule.match === 'contains' ? '包含' : '等于') + '「' + rule.value + '」')
              .fontSize(16).fontColor($r('app.color.ink')).width('100%')
            Text('识别为' + (rule.action === 'skip' ? '跳过' : '关闭') + ' · 最长 ' + rule.maxLength + ' 字')
              .fontSize(12).fontColor($r('app.color.muted')).width('100%')
            if (rule.exclude.length) { Text('排除：' + rule.exclude.join('、')).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
            if (rule.bundles.length) { Text('仅用于：' + rule.bundles.join('、')).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
            Row({ space: 10 }) {
              Button('编辑').id('quietstart-strategy-edit-' + index).height(32).layoutWeight(1).backgroundColor($r('app.color.soft'))
                .fontColor($r('app.color.accent')).onClick(() => { this.editStrategy(index); })
              Button('移除').height(32).backgroundColor($r('app.color.soft')).fontColor($r('app.color.muted'))
                .onClick(() => { this.removeStrategy(index); })
            }.width('100%')
          }.padding(16).borderRadius(18).backgroundColor($r('app.color.surface')).width('100%')
        }, (rule: RecognitionRule) => JSON.stringify(rule))
        if (this.strategyCustom) {
          Button('恢复内置条件').width('100%').backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent'))
            .onClick(() => { this.rulePacks?.resetLocalRules(); this.refreshRulePack(); this.rulePackMessage = '已恢复内置条件'; })
        }
      }
      }
      if (this.rulePackMessage) { Text(this.rulePackMessage).id('quietstart-strategy-status').fontSize(13).fontColor($r('app.color.accent')).width('100%') }
    }.padding({ top: 8, bottom: 12 }).width('100%')
  }

  @Builder
  settingsPage() {
    Scroll() {
      Column({ space: 14 }) {
        this.titleBlock('设置', '')
        this.sectionLabel('自动识别')
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text('规则自动启用').fontSize(16).fontColor($r('app.color.ink'))
            Text('仅作用于以后自动识别的新规则；手动识别直接启用').fontSize(12).fontColor($r('app.color.muted'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.autoEnableRules }).id('quietstart-auto-enable-rules')
            .selectedColor($r('app.color.accent')).onChange((value: boolean) => { this.setAutoEnable(value); })
        }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.surface'))
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text('新规则通知').fontSize(16).fontColor($r('app.color.ink'))
            Text('保存成功后提醒，点击直达规则页').fontSize(12).fontColor($r('app.color.muted'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.newRuleReminders }).id('quietstart-new-rule-reminder')
            .selectedColor($r('app.color.accent')).onChange((value: boolean) => { this.setNewRuleReminder(value); })
        }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.surface'))
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text('学习新规则').fontSize(16).fontColor($r('app.color.ink'))
            Text('已有规则保留，继续发现新样式').fontSize(12).fontColor($r('app.color.muted'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.learningEnabled }).id('quietstart-learning-toggle')
            .selectedColor($r('app.color.accent')).onChange((value: boolean) => { this.setLearning(value); })
        }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.surface'))
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text('自动发现应用').fontSize(16).fontColor($r('app.color.ink'))
            Text('记录新打开的应用').fontSize(12).fontColor($r('app.color.muted'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.discoverApps }).id('quietstart-discovery-toggle')
            .selectedColor($r('app.color.accent')).onChange((value: boolean) => { this.setDiscovery(value); })
        }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.surface'))
        Column({ space: 12 }) {
          Row({ space: 12 }) {
            Column({ space: 5 }) {
              Text('未见广告时自动暂停').fontSize(16).fontColor($r('app.color.ink'))
              Text('观察满 ' + this.adFreeMinDays + ' 天且完成 ' + this.adFreeCleanChecks + ' 次检查后暂停；每 ' + this.adFreeRecheckDays + ' 天复查')
                .id('quietstart-adfree-summary').fontSize(12).lineHeight(19).fontColor($r('app.color.muted'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.autoAdFree }).id('quietstart-auto-adfree')
              .selectedColor($r('app.color.accent')).onChange((value: boolean) => { this.setAutoAdFree(value); })
          }.width('100%')
          if (this.autoAdFree) {
            Button(this.pauseOptionsOpen ? '收起暂停与复查设置' : '调整暂停与复查').id('quietstart-pause-options').width('100%').height(40)
              .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.pauseOptionsOpen = !this.pauseOptionsOpen; })
          }
          if (this.autoAdFree && this.pauseOptionsOpen) {
            Divider().color($r('app.color.line'))
            this.adFreeControl('观察跨度', 'days', 1, 7, '天')
            this.adFreeControl('完整检查', 'checks', 2, 20, '次')
            this.adFreeControl('复查间隔', 'recheck', 1, 30, '天')
            Text('两项条件需同时满足，检查至少间隔 30 分钟；手动暂停不自动复查。')
              .fontSize(12).lineHeight(19).fontColor($r('app.color.muted')).width('100%')
          }
        }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.surface'))
        this.sectionLabel('跳过提醒')
        Column({ space: 12 }) {
          Row({ space: 12 }) {
            Column({ space: 5 }) {
              Text('开启跳过通知').fontSize(16).fontColor($r('app.color.ink'))
              Text('静音提醒，累计更新同一条通知').fontSize(12).fontColor($r('app.color.muted'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.remindersEnabled }).id('quietstart-reminder-toggle')
              .selectedColor($r('app.color.accent')).onChange((value: boolean) => { this.setReminders(value); })
          }.width('100%')
          if (this.remindersEnabled) {
            Divider().color($r('app.color.line'))
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('自动收起').fontSize(14).fontColor($r('app.color.ink'))
                Text(this.reminderAutoDismiss ? '每次更新后 ' + this.reminderSeconds + ' 秒' : '不自动收起，可手动清除')
                  .id('quietstart-reminder-duration-label').fontSize(12).fontColor($r('app.color.muted'))
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.reminderAutoDismiss }).id('quietstart-reminder-auto-dismiss')
                .selectedColor($r('app.color.accent')).onChange((value: boolean) => { this.setReminderDuration(value ? this.reminderSeconds : 0); })
            }.width('100%')
            if (this.reminderAutoDismiss) {
              Column({ space: 2 }) {
                Slider({ value: this.reminderSeconds, min: 1, max: 60, step: 1 })
                  .id('quietstart-reminder-duration').width('100%').selectedColor($r('app.color.accent'))
                  .onChange((value: number, mode: SliderChangeMode) => {
                    this.reminderSeconds = Math.round(value);
                    this.reminderSliding = mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving;
                    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.setReminderDuration(this.reminderSeconds); }
                  })
                Row() {
                  Text('1 秒').fontSize(11).fontColor($r('app.color.muted'))
                  Blank()
                  Text('60 秒').fontSize(11).fontColor($r('app.color.muted'))
                }.width('100%')
              }.width('100%')
            }
            Text('收起时间仅适用于通知中心；横幅由系统控制。')
              .fontSize(12).lineHeight(19).fontColor($r('app.color.muted')).width('100%')
          }
          if (this.remindersEnabled) {
          Text(this.remindersEnabled ? (this.reminderState.mode === 'notification' && !this.reminderState.message.includes('横幅已关闭') ?
            '点击通知可查看记录。' : this.reminderState.message) : '').id('quietstart-reminder-status').fontSize(12).lineHeight(19).fontColor($r('app.color.muted')).width('100%')
          }
          Row({ space: 8 }) {
            Button('预览通知').id('quietstart-reminder-preview').height(36).layoutWeight(1).enabled(this.remindersEnabled)
              .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.previewReminder(); })
            Button('通知设置').id('quietstart-reminder-permission').height(36).layoutWeight(1)
              .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.openNotificationSettings(); })
          }.width('100%')
        }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.surface'))
        this.sectionLabel('识别策略')
        Column({ space: 12 }) {
          Row() {
            Text('广告识别方式').fontSize(16).fontColor($r('app.color.ink')).layoutWeight(1)
          }.width('100%')
          Text('S01–S08 · 示例、识别依据与点击位置').fontSize(12).fontColor($r('app.color.muted')).width('100%')
          Button('查看识别策略').id('quietstart-pack-manage').height(38).width('100%')
            .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.openStrategy(); })
          if (this.rulePackMessage) {
            Text(this.rulePackMessage).id('quietstart-pack-status').fontSize(12).lineHeight(19).fontColor($r('app.color.muted')).width('100%')
          }
        }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.surface'))
        this.sectionLabel('主题外观')
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            this.themeOption('light', '白色')
            this.themeOption('dark', '黑色')
            this.themeOption('system', '跟随系统')
          }.width('100%')
        }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.surface'))
        Text('轻启' + (this.appVersion ? ' ' + this.appVersion : '') + ' · 数据仅保存在本机').fontSize(11).fontColor($r('app.color.muted')).width('100%').textAlign(TextAlign.Center)
        Button('运行诊断与退出记录').id('quietstart-exit-records').height(40).width('100%')
          .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.detail = 'health'; })
      }.padding({ left: 20, right: 20, top: 12, bottom: this.tabContentBottomSpace }).width('100%').constraintSize({ maxWidth: 620 })
    }.align(Alignment.Top).width('100%').height('100%')
  }

  @Builder
  sessionDetails() {
    Column({ space: 10 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Text('会话详情').fontSize(14).fontColor($r('app.color.accent')).layoutWeight(1)
          SymbolGlyph(this.advanced ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .fontSize(12).fontColor([$r('app.color.accent')]).width(16).height(20)
        }.width('100%').height(42).alignItems(VerticalAlign.Center).padding({ left: 14, right: 14 })
      }.id('quietstart-session-details').width('100%').borderRadius(14).backgroundColor($r('app.color.soft'))
        .onClick(() => { this.advanced = !this.advanced; })
      if (this.advanced) {
        Text('最近心跳：' + this.timeLabel(this.debugStatus.heartbeatAt)).id('quietstart-session-heartbeat')
          .fontSize(12).fontColor($r('app.color.muted')).width('100%')
        Text('最近接口响应：' + this.timeLabel(this.debugStatus.rpcAt)).id('quietstart-session-rpc')
          .fontSize(12).fontColor($r('app.color.muted')).width('100%')
        Text(this.debugStatus.supervisorToken ? '已尝试恢复 ' + this.debugStatus.recoveryAttempt + ' 次 · 连续失败最多 4 次' : '当前连接未配置自动恢复')
          .id('quietstart-supervision-summary').fontSize(12).fontColor($r('app.color.muted')).width('100%')
        if (this.supervisionNotice) { Text(this.supervisionNotice).fontSize(12).lineHeight(20).fontColor($r('app.color.warning')).width('100%') }
        Button('查看退出记录').height(32).width('100%').fontSize(12).backgroundColor($r('app.color.soft'))
          .fontColor($r('app.color.accent')).onClick(() => { this.detail = 'health'; })
        Text('结束连接将同时停止自动恢复；临时暂停可用总开关。')
          .fontSize(12).lineHeight(20).fontColor($r('app.color.muted')).width('100%')
        Button('结束本次连接').id('quietstart-end-session').height(40).width('100%')
          .backgroundColor($r('app.color.soft')).fontColor($r('app.color.warning')).onClick(() => { this.endSession(); })
      }
    }.width('100%')
  }

  @Builder
  activationPage() {
    Column({ space: 14 }) {
      Text(this.online ? '已连接' : '本机连接')
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).width('100%')
      if (this.online) {
        Text('连接正常，可以继续使用应用。').fontSize(14).fontColor($r('app.color.ink')).width('100%')
        this.sessionDetails()
        Button(this.connectionStepsOpen ? '收起连接步骤' : '查看重新连接步骤').id('quietstart-connection-steps').height(40).width('100%')
          .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.connectionStepsOpen = !this.connectionStepsOpen; })
      }
      if (!this.online || this.connectionStepsOpen) {
      Text('已开启的步骤可跳过。')
        .fontSize(13).lineHeight(21).fontColor($r('app.color.muted')).width('100%')
      this.actionRow('1  开启开发者模式', '直达关于本机 → 连续点击软件版本 7 次 → 确认并按提示重启；重启后返回轻启', () => { this.openDeveloperSetup(); })
      this.actionRow('2  打开无线调试', '直达系统页面 → 开启无线调试 → 记下端口', () => { this.openSystemSettings(); })
      Column({ space: 12 }) {
        Text('3  填写端口并连接').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).width('100%')
        TextInput({ text: this.debugPort, placeholder: '例如 37419' }).id('quietstart-debug-port')
          .height(46).type(InputType.Number).fontColor($r('app.color.ink')).placeholderColor($r('app.color.muted'))
          .backgroundColor($r('app.color.soft')).borderRadius(12).enabled(!this.activating)
          .onChange((value: string) => { this.debugPort = value; })
        Text('系统询问时允许连接。轻启会自动准备工作模块，完成后重新打开。').fontSize(12).lineHeight(19).fontColor($r('app.color.muted')).width('100%')
        Button(this.online ? '已连接' : (this.activating ? '正在连接…' : '连接轻启')).id('quietstart-activate-local')
          .width('100%').height(44).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
          .enabled(!this.online && !this.activating).onClick(() => { this.activateLocally(); })
        if (this.activation.message) {
          Text(this.activation.success && !this.online ? '上次连接已结束，请重新连接。' : this.activation.message)
            .id('quietstart-activation-status').fontSize(12).lineHeight(19).fontColor($r('app.color.muted')).width('100%')
        }
      }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.surface'))
      }
    }.width('100%')
  }

  @Builder
  timelineRail(continued: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (continued) { Rect().width(1).height('100%').fill($r('app.color.line')).position({ x: 3, y: 6 }) }
      Circle().width(7).height(7).fill($r('app.color.accent')).position({ x: 0, y: 4 })
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
  }

  @Builder
  recordsPage() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        StatMetric({ value: this.debugStatus.observedDismissedCount.toString(), label: '确认消失' })
        StatMetric({ value: this.debugStatus.clickCount.toString(), label: '尝试点击' })
        StatMetric({ value: this.debugStatus.unverifiedCount.toString(), label: '未能确认' })
      }.padding(16).width('100%').backgroundColor($r('app.color.surface')).borderRadius(18)
      Text('连续两次未再看到广告控件，计入确认消失；未确认不代表失败。')
        .fontSize(12).lineHeight(20).fontColor($r('app.color.muted')).width('100%')
      this.sectionLabel('最近运行过程')
      if (!this.debugStatus.history.length) {
        Text('暂无记录，连接后打开应用即可开始。').fontSize(13).lineHeight(21).fontColor($r('app.color.muted')).width('100%')
      }
      ForEach(groupDebugRecords(this.debugStatus.history), (process: DebugProcess) => {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text(this.appName(process.bundle)).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
              Text(this.timeLabel(process.startedAt) + ' · ' + (process.result === 'decision' ? '检查记录' : this.resultLabel(process.result)))
                .fontSize(12).fontColor($r('app.color.muted'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.eye')).fontSize(19).fontColor([$r('app.color.accent')])
            }.width(40).height(40).backgroundColor($r('app.color.soft'))
              .id('quietstart-process-eye-' + process.id)
              .accessibilityText(this.expandedProcess === process.id ? '收起过程详情' : '查看过程时间线')
              .onClick(() => { this.expandedProcess = this.expandedProcess === process.id ? '' : process.id; })
          }.width('100%')
          if (process.timing) { Text(process.timing).fontSize(12).fontColor($r('app.color.muted')).width('100%') }
          if (this.expandedProcess === process.id) {
            Divider().color($r('app.color.line'))
            Column() {
              ForEach(process.records, (record: DebugRecord, index: number) => {
                Column({ space: 5 }) {
                  Row({ space: 8 }) {
                    Text('+' + (Math.max(0, record.at - process.startedAt) / 1000).toFixed(3) + ' 秒')
                      .fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.accent'))
                    Text(this.resultLabel(record.result)).fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
                  }.width('100%')
                  Text(this.timeLabel(record.at) + '.' + String(record.at % 1000).padStart(3, '0'))
                    .fontSize(11).fontColor($r('app.color.muted'))
                  Text(record.message).fontSize(12).lineHeight(19).fontColor($r('app.color.muted')).width('100%')
                }.width('100%').alignItems(HorizontalAlign.Start)
                  .padding({ left: 20, bottom: index < process.records.length - 1 ? 18 : 0 })
                  .background(this.timelineRail(index < process.records.length - 1))
              }, (record: DebugRecord, index: number) => record.at + ':' + index)
            }.width('100%')
          }
        }.padding(16).width('100%').backgroundColor($r('app.color.surface')).borderRadius(16).alignItems(HorizontalAlign.Start)
      }, (process: DebugProcess) => process.id)
    }.width('100%')
  }

  @Builder
  appDetailPage() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        this.appIcon(this.editingBundle, 48)
        Text(this.appName(this.editingBundle)).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink')).layoutWeight(1)
      }.width('100%')
      Text(this.appStatus(this.editingBundle)).fontSize(13).fontColor($r('app.color.accent')).width('100%')
      Text(this.editingBundle).fontSize(12).fontColor($r('app.color.muted')).width('100%')
      if (this.isQuietApp(this.editingBundle)) {
        Text('多次完整检查未见广告线索，已暂时停止扫描。按当前设置每 ' + this.adFreeRecheckDays + ' 天复查，到期后下次打开时检查；可随时手动恢复。').fontSize(13).lineHeight(20).fontColor($r('app.color.muted')).width('100%')
        Button('恢复广告检测').id('quietstart-restore-detection').width('100%').height(40)
          .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
          .onClick(() => { this.releaseQuietApp(this.editingBundle); })
      }
      Column({ space: 10 }) {
        Text('强化学习').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).width('100%')
        Text('自动打开应用；系统询问时请选择“打开”。手动关闭广告后，将返回并显示结果。').fontSize(13).lineHeight(20).fontColor($r('app.color.muted')).width('100%')
        Text('等待最多 60 秒；新规则直接启用，原有规则保留。').fontSize(12).lineHeight(18).fontColor($r('app.color.muted')).width('100%')
        Button(this.manualActive ? '取消本次学习' : '开始强化学习').id('quietstart-manual-learn').enabled(!this.learningPreparing).width('100%').height(44)
          .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
          .onClick(() => { if (this.manualActive) { this.learningStore?.cancelManualLearning(); this.notice = '已取消本次学习。'; this.refresh(); } else { this.startManualLearning(); } })
        if (this.manualMessage) { Text(this.manualMessage).fontSize(12).lineHeight(18).fontColor($r('app.color.accent')).width('100%') }
      }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.surface'))
      Button('查看规则').id('quietstart-app-rules').width('100%').height(40).fontColor($r('app.color.accent'))
        .backgroundColor($r('app.color.soft')).onClick(() => { this.ruleQuery = this.appName(this.editingBundle); this.showAllRules = true; this.go(2); })
      Button('移出应用列表').id('quietstart-remove-app').height(40).width('100%')
        .backgroundColor($r('app.color.soft')).fontColor($r('app.color.muted')).onClick(() => { this.removeManagedApp(); })
      Button(this.renameOpen ? '收起备注名编辑' : '修改备注名').id('quietstart-edit-app-name').height(40).width('100%')
        .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.renameOpen = !this.renameOpen; })
      if (this.renameOpen) {
      Text('可修改应用备注名。').fontSize(13).fontColor($r('app.color.muted')).width('100%')
      TextInput({ text: this.editingName, placeholder: '应用名称' }).id('quietstart-app-name').maxLength(40)
        .fontColor($r('app.color.ink')).backgroundColor($r('app.color.surface')).onChange((value: string) => { this.editingName = value; })
      Button('保存名称').id('quietstart-save-app-name').width('100%').height(40).fontColor($r('app.color.on_accent'))
        .backgroundColor($r('app.color.accent')).onClick(() => { this.renameApp(); })
      }
      if (this.learnedRules.some((rule: LearnedRule) => rule.bundle === this.editingBundle)) {
        Button('删除规则并重新学习').id('quietstart-reset-app-rules').width('100%').height(40)
          .fontColor($r('app.color.warning')).backgroundColor($r('app.color.soft'))
          .onClick(() => { this.resetRules(this.editingBundle); })
      }
      if (!this.allowedPackages.includes(this.editingBundle) && !this.ignoredPackages.includes(this.editingBundle) &&
        this.learnedRules.some((rule: LearnedRule) => rule.bundle === this.editingBundle && ruleState(rule, this.decisions) === 'approved')) {
        Button('开启自动跳过').id('quietstart-enable-app').width('100%').height(40)
          .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
          .onClick(() => { this.selectApp(this.editingBundle, true); })
      }
      Button(this.ignoredPackages.includes(this.editingBundle) ? '恢复此应用' : '手动暂停此应用')
        .id('quietstart-pause-app').width('100%').height(40).fontColor($r('app.color.warning')).backgroundColor($r('app.color.soft'))
        .onClick(() => { this.selectApp(this.editingBundle, this.ignoredPackages.includes(this.editingBundle)); })
    }.width('100%')
  }

  @Builder
  helpPage() {
    Column({ space: 12 }) {
      Button('重新查看连接向导').id('quietstart-replay-onboarding').width('100%').height(44)
        .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).onClick(() => { this.startWizard(); })
      this.actionRow('① 开启开发者模式', '点击直达关于本机，连续快速点击“软件版本”7 次。确认开启并按提示重启，然后返回轻启。已开启可跳过此步。', () => { this.openDeveloperSetup(); })
      this.actionRow('② 连接轻启', '连接 Wi-Fi，开启无线调试，填写端口并允许连接', () => { this.detail = 'activation'; })
      Column({ space: 4 }) {
        Text('③ 正常使用应用').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
        Text('打开应用，自动记录并学习开屏广告。').fontSize(12).lineHeight(20).fontColor($r('app.color.muted'))
      }.padding(16).width('100%').borderRadius(18).backgroundColor($r('app.color.surface')).alignItems(HorizontalAlign.Start)
      this.actionRow('④ 确认规则', '确认你认识的跳过样式，下次自动执行', () => { this.go(2); })
      Text('没有自动跳过？').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink')).width('100%').margin({ top: 8 })
      Text('检查连接和总开关，确认应用未暂停、规则已启用。')
        .fontSize(13).lineHeight(22).fontColor($r('app.color.muted')).width('100%')
      this.actionRow('查看具体原因', '查看最近检查结果与原因', () => { this.detail = 'records'; })
      Text('图片中没有可读文字、描述或控件标识时，暂时无法学习。新样式需要确认；跳过通知的横幅展示由系统通知设置决定。')
        .fontSize(12).lineHeight(20).fontColor($r('app.color.muted')).width('100%')
      Text('开发者工具').fontSize(12).fontColor($r('app.color.muted')).width('100%').margin({ top: 12 })
      Button('测试轻启自己的按钮').id('quietstart-start-probe').height(38).width('100%')
        .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.startProbe(); })
    }.width('100%')
  }

  @Builder
  onboardingPage() {
    Scroll() {
      Column({ space: 22 }) {
        Row() {
          Text('轻启 · 初次连接').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).layoutWeight(1)
          if (!this.activating) { Button('稍后设置').id('quietstart-onboarding-later').fontSize(12).height(32)
            .fontColor($r('app.color.muted')).backgroundColor(Color.Transparent).onClick(() => { this.deferWizard(); }) }
        }.width('100%')
        Image($r('app.media.quiet_icon')).width(80).height(80).borderRadius(22).margin({ top: 12, bottom: 2 })
        Row({ space: 7 }) {
          ForEach([0, 1, 2, 3], (step: number) => { Rect().width(24).height(4).radius(2)
            .fill(step <= this.wizardStep ? $r('app.color.accent') : $r('app.color.line')) })
        }
        Text(this.wizardStep === 0 ? '先开启开发者模式' : (this.wizardStep === 1 ? '开启手机无线调试' :
          (this.wizardStep === 2 ? '连接这台手机' : '连接完成，准备就绪')))
          .id('quietstart-onboarding-title').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink')).width('100%')
        if (this.wizardStep === 0) {
          Text('① 点击下方按钮，直达“关于本机”。\n② 连续快速点击“软件版本”7 次。\n③ 确认开启，按提示输入锁屏密码并重启。\n④ 重启后重新打开轻启，继续下一步。')
            .fontSize(15).lineHeight(28).fontColor($r('app.color.ink')).width('100%')
          Text('如果“设置 → 系统”中已有“开发者选项”，可直接继续。向导会保留当前步骤。')
            .fontSize(13).lineHeight(22).fontColor($r('app.color.muted')).width('100%')
          Button('打开关于本机').id('quietstart-onboarding-developer').width('100%').height(46)
            .fontColor($r('app.color.on_accent')).backgroundColor($r('app.color.accent')).onClick(() => { this.onboarding?.save(0); this.openDeveloperSetup(); })
          Button('已开启，继续无线调试').id('quietstart-onboarding-start').width('100%').height(44)
            .fontColor($r('app.color.accent')).backgroundColor($r('app.color.soft')).onClick(() => { this.wizardMove(1); })
        } else if (this.wizardStep === 1) {
          Text('① 连接 Wi-Fi。\n② 在开发者选项中开启“无线调试”。\n③ 记下页面显示的端口，再返回轻启。')
            .fontSize(15).lineHeight(28).fontColor($r('app.color.ink')).width('100%')
          Button('打开无线调试设置').id('quietstart-onboarding-settings').width('100%').height(46)
            .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).onClick(() => { this.openSystemSettings(); })
          Button('已开启，填写端口').id('quietstart-onboarding-port').width('100%').height(44)
            .backgroundColor($r('app.color.soft')).fontColor($r('app.color.accent')).onClick(() => { this.wizardMove(2); })
        } else if (this.wizardStep === 2) {
          Text('填写无线调试页显示的端口，允许“轻启本机激活”连接。首次连接会自动安装工作模块，请保持轻启在前台。')
            .fontSize(15).lineHeight(25).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.debugPort, placeholder: '无线调试端口' }).id('quietstart-debug-port').type(InputType.Number).height(50)
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink')).enabled(!this.activating)
            .onChange((value: string) => { this.debugPort = value; })
          Button(this.activating ? '正在连接…' : '连接轻启').id('quietstart-activate-local').width('100%').height(48)
            .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).enabled(!this.activating)
            .onClick(() => { this.onboarding?.save(2); this.activateLocally(); })
          Text(this.activation.success && !this.online ? '填写当前端口，开始本次连接。' : this.activation.message).id('quietstart-activation-status').fontSize(13).lineHeight(22).fontColor($r('app.color.muted')).width('100%')
        } else {
          Text('现在可以正常打开应用。遇到开屏广告后，回来确认新规则；同一种样式只需确认一次。')
            .fontSize(15).lineHeight(25).fontColor($r('app.color.muted')).width('100%')
          Text('重启或会话结束后，可从“概览 → 开始本机连接”重新连接。').fontSize(13).lineHeight(22).fontColor($r('app.color.muted')).width('100%')
          Button('完成，进入轻启').id('quietstart-onboarding-finish').width('100%').height(48)
            .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent')).onClick(() => { this.finishWizard(); })
        }
        if (this.notice) { Text(this.notice).fontSize(13).lineHeight(22).fontColor($r('app.color.warning')).width('100%') }
        if (this.wizardStep > 0 && !this.activating) { Button('上一步').id('quietstart-onboarding-back').height(36)
          .backgroundColor(Color.Transparent).fontColor($r('app.color.muted')).onClick(() => { this.wizardMove(this.wizardStep - 1); }) }
      }.padding({ left: 28, right: 28, top: 16, bottom: 36 }).width('100%').constraintSize({ maxWidth: 560 })
    }.width('100%').height('100%')
  }

  build() {
    Column() {
      if (this.wizardOpen) { this.onboardingPage(); } else if (this.testing) {
        Column({ space: 20 }) {
          Text('本应用点击测试').fontSize(25).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
          Text(this.testResult || '等待测试程序点击下方按钮').fontSize(14).fontColor($r('app.color.muted'))
            .id(this.testResult === '测试按钮已收到点击' ? 'quietstart-probe-success' : 'quietstart-test-result')
          if (!this.testResult) {
            Button('跳过').id('quietstart-probe-skip').onClick(() => { this.testResult = '测试按钮已收到点击'; clearTimeout(this.testTimer); })
          }
          Button('返回').onClick(() => { this.testing = false; clearTimeout(this.testTimer); })
        }.padding(24).width('100%').height('100%').justifyContent(FlexAlign.Center)
      } else if (this.detail) {
        Row({ space: 12 }) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(14).fontColor([$r('app.color.accent')]).width(16).height(20)
              Text('返回').fontSize(14).fontColor($r('app.color.accent')).height(20)
            }.height(36).alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center).padding({ left: 8, right: 8 })
          }.id('quietstart-detail-back').height(36).backgroundColor(Color.Transparent).borderRadius(18)
            .onClick(() => { if (this.detail === 'strategy' && this.strategyEdit >= 0) { this.strategyEdit = -1; } else { this.detail = ''; } })
          Text(this.detail === 'health' ? '运行诊断' : this.detail === 'strategy' ? (this.strategyEdit >= 0 ? '编辑识别条件' : '识别策略') : this.detail === 'activation' ? '本机连接' : (this.detail === 'records' ? '运行记录' : (this.detail === 'app' ? '应用管理' : '使用指南')))
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink')).layoutWeight(1)
        }.padding({ left: 12, right: 20, top: 8, bottom: 8 }).width('100%')
        if (this.notice) { Text(this.notice).fontSize(12).fontColor($r('app.color.accent')).padding({ left: 20, right: 20, bottom: 8 }).width('100%') }
        Scroll(this.detailScroller) {
          Column() {
            if (this.detail === 'activation') { this.activationPage(); }
            else if (this.detail === 'records') { this.recordsPage(); }
            else if (this.detail === 'app') { this.appDetailPage(); }
            else if (this.detail === 'strategy') { this.strategyPage(); }
            else if (this.detail === 'health') { this.healthPage(); }
            else { this.helpPage(); }
          }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 32 }).constraintSize({ maxWidth: 620 })
        }.align(Alignment.Top).width('100%').layoutWeight(1)
        if (this.detail === 'strategy' && this.strategyEdit >= 0) {
          Column({ space: 6 }) {
            if (strategyProblem(this.strategyDraft())) { Text(strategyProblem(this.strategyDraft())).fontSize(12).fontColor($r('app.color.warning')).width('100%') }
        Row({ space: 10 }) {
          Button('取消').height(44).layoutWeight(1).backgroundColor($r('app.color.soft')).fontColor($r('app.color.muted'))
            .onClick(() => { this.strategyEdit = -1; this.rulePackMessage = ''; })
          Button('保存条件').id('quietstart-strategy-save').height(44).layoutWeight(1)
            .enabled(!strategyProblem(this.strategyDraft())).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
            .onClick(() => { this.saveStrategy(); })
        }.width('100%')
          }.padding({ left: 20, right: 20, top: 10, bottom: 12 }).width('100%').backgroundColor($r('app.color.surface'))
        }
      } else {
        if (this.notice) {
          Text(this.notice).fontSize(12).fontColor($r('app.color.accent')).maxLines(2)
            .padding({ left: 20, right: 20, top: 8 }).width('100%')
        }
        HdsTabs({ barPosition: BarPosition.End, index: this.page, controller: this.tabsController }) {
          TabContent() { this.homePage(); }.tabBar(BottomTabBarStyle.of({ normal: new SymbolGlyphModifier($r('sys.symbol.house')),
            selected: new SymbolGlyphModifier($r('sys.symbol.house_fill')) }, '概览').id('quietstart-tab-home'))
          TabContent() { this.appsPage(); }.tabBar(BottomTabBarStyle.of({ normal: new SymbolGlyphModifier($r('sys.symbol.square_grid_2x2')) }, '应用').id('quietstart-tab-apps'))
          TabContent() { this.learningPage(); }.tabBar(BottomTabBarStyle.of({ normal: new SymbolGlyphModifier($r('sys.symbol.book')),
            selected: new SymbolGlyphModifier($r('sys.symbol.book_open_fill')) }, '规则').id('quietstart-tab-learning'))
          TabContent() { this.settingsPage(); }.tabBar(BottomTabBarStyle.of({ normal: new SymbolGlyphModifier($r('sys.symbol.gearshape')) }, '设置').id('quietstart-tab-settings'))
        }.id('quietstart-bottom-navigation').vertical(false).barMode(BarMode.Fixed).barOverlap(true)
          .barFloatingStyle({ systemMaterialEffect: { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE } })
          .onChange((index: number) => { this.page = index; this.notice = ''; this.searchController.stopEditing(); this.searchEditing = false; if (index === 1) { this.syncAppCatalog(); } })
          .width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').backgroundColor($r('app.color.page_bg'))
  }
}
