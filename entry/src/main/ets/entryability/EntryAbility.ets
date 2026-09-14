import { AbilityConstant, Configuration, UIAbility, Want, bundleManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { LocalStore } from '../core/LocalStore';
import { themeColorMode, themeIsDark } from '../core/Theme';
import { SystemExitStore, ExitEnvironment, userRequestedExit } from '../core/SystemExitStore';
import { SupervisionStore } from '../core/SupervisionStore';
import { DebugStore, exhaustedRecovery } from '../core/DebugStore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;
  private cancelledRecovery: boolean = false;
  private backgroundAfterRecovery: boolean = false;

  private recoverySignal(want: Want): string {
    const s = new SupervisionStore(this.context.getApplicationContext().filesDir);
    const token = want.parameters?.['quietstartRecoveryToken'];
    if (typeof token !== 'string' || s.read().token !== token) { return ''; }
    if (want.parameters?.['quietstartSupervisorState'] === 'exhausted') {
      s.stop(); s.setNotice('自动恢复已达 3 次上限，请重新连接。退出记录已保留。');
    }
    const reason = want.parameters?.['quietstartRecoveryReason'];
    return typeof reason === 'string' ? reason : '';
  }

  private captureExit(want: Want, launch: AbilityConstant.LaunchParam): void {
    try {
      const directory = this.context.getApplicationContext().filesDir;
      const environment = new ExitEnvironment();
      environment.osVersion = deviceInfo.osFullName; environment.apiVersion = deviceInfo.sdkApiVersion;
      environment.model = deviceInfo.productModel;
      try { environment.appVersion = bundleManager.getBundleInfoForSelfSync(0).versionName; } catch (_) {}
      try {
        const manifest = JSON.parse(new util.TextDecoder('utf-8').decodeToString(
          this.context.resourceManager.getRawFileContentSync('quietstart-worker.json'))) as Record<string, string | number>;
        environment.workerVersion = Number(manifest['versionCode']) || 0;
      } catch (_) {}
      const recovery = this.recoverySignal(want);
      const supervision = new SupervisionStore(directory);
      const control = supervision.read();
      if (typeof want.parameters?.['quietstartRecoveryToken'] !== 'string' && control.active &&
        exhaustedRecovery(new DebugStore(directory).readStatus(), control.token)) {
        supervision.stop(); supervision.setNotice('上次连接已中断，3 次自动恢复已用完，请重新连接。退出记录已保留。');
      }
      const row = new SystemExitStore(directory).capture(launch, environment, recovery,
        Number(want.parameters?.['quietstartRecoveryAttempt'] ?? 0));
      const userStopped = userRequestedExit(row.reason, row.message);
      if ((row.reason === 8 || userStopped) && !['activation', 'module-install'].includes(row.expectedAction)) {
        const s = new SupervisionStore(directory); s.stop();
        s.setNotice(userStopped ? '最近任务已结束，自动恢复同步停止。需要时可重新连接。' : '应用已升级，请重新连接以启动对应工作模块。');
        this.cancelledRecovery = typeof want.parameters?.['quietstartRecoveryToken'] === 'string';
      }
      if (recovery && !this.cancelledRecovery) { new SystemExitStore(directory).markExpected('worker-restart'); }
    } catch (error) { hilog.warn(DOMAIN, 'QuietStartExit', 'Exit metadata unavailable: %{public}s', String(error)); }
  }

  private resumeInstallation(want: Want): void {
    const token = want.parameters?.['quietstartInstallResume'];
    if (typeof token === 'string' && /^[0-9]{13,16}$/.test(token)) {
      AppStorage.setOrCreate<string>('quietstartInstallResume', token);
    }
  }

  private updateBars(dark: boolean): void {
    this.mainWindow?.setWindowSystemBarProperties({ statusBarColor: dark ? '#101713' : '#F3F6F2',
      statusBarContentColor: dark ? '#E5EEE7' : '#20372F', navigationBarColor: dark ? '#101713' : '#F3F6F2',
      navigationBarContentColor: dark ? '#E5EEE7' : '#20372F' }).catch(() => {});
  }

  onConfigurationUpdate(config: Configuration): void {
    hilog.info(DOMAIN, 'QuietStartTheme', 'config mode=%{public}d preference=%{public}s', config.colorMode ?? -1, new LocalStore(this.context.getApplicationContext().filesDir).readSettings().themeMode);
    if (config.colorMode !== undefined) {
      this.updateBars(themeIsDark(new LocalStore(this.context.getApplicationContext().filesDir).readSettings().themeMode, config.colorMode));
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.captureExit(want, launchParam);
    const recoveryToken = want.parameters?.['quietstartRecoveryToken'];
    this.backgroundAfterRecovery = !this.cancelledRecovery && typeof recoveryToken === 'string' &&
      typeof want.parameters?.['quietstartRecoveryReason'] === 'string' &&
      new SupervisionStore(this.context.getApplicationContext().filesDir).allows(recoveryToken);
    this.resumeInstallation(want);
    AppStorage.setOrCreate<boolean>('quietstartForeground', true);
    AppStorage.setOrCreate<boolean>('quietstartOpenRules', want.parameters?.['quietstartOpenRules'] === true);
    AppStorage.setOrCreate<boolean>('quietstartOpenRecords', want.parameters?.['quietstartOpenRecords'] === true);
    AppStorage.setOrCreate<boolean>('quietstartProbe', want.parameters?.['quietstartProbe'] === true);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.recoverySignal(want);
    this.resumeInstallation(want);
    if (want.parameters?.['quietstartOpenRules'] === true) { AppStorage.setOrCreate<boolean>('quietstartOpenRules', true); }
    if (want.parameters?.['quietstartOpenRecords'] === true) { AppStorage.setOrCreate<boolean>('quietstartOpenRecords', true); }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    if (this.cancelledRecovery) { this.context.terminateSelf().catch(() => {}); return; }
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      this.context.getApplicationContext().setColorMode(themeColorMode(new LocalStore(this.context.getApplicationContext().filesDir).readSettings().themeMode));
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    try {
      windowStage.getMainWindow().then((mainWindow: window.Window) => {
        this.mainWindow = mainWindow;
        this.updateBars(themeIsDark(new LocalStore(this.context.getApplicationContext().filesDir).readSettings().themeMode, this.context.config.colorMode));
      }).catch(() => {});
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    AppStorage.setOrCreate<boolean>('quietstartForeground', true);
    if (this.backgroundAfterRecovery) {
      this.backgroundAfterRecovery = false;
      this.context.moveAbilityToBackground().catch((error: Error) => {
        hilog.warn(DOMAIN, 'QuietStartExit', 'Recovery background transition failed: %{public}s', String(error));
      });
    }
    this.updateBars(themeIsDark(new LocalStore(this.context.getApplicationContext().filesDir).readSettings().themeMode, this.context.config.colorMode));
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    AppStorage.setOrCreate<boolean>('quietstartForeground', false);
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
