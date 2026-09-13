import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { LocalStore } from '../core/LocalStore';
import { themeColorMode, themeIsDark } from '../core/Theme';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow?: window.Window;

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
    AppStorage.setOrCreate<boolean>('quietstartForeground', true);
    AppStorage.setOrCreate<boolean>('quietstartOpenRecords', want.parameters?.['quietstartOpenRecords'] === true);
    AppStorage.setOrCreate<boolean>('quietstartProbe', want.parameters?.['quietstartProbe'] === true);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want.parameters?.['quietstartOpenRecords'] === true) { AppStorage.setOrCreate<boolean>('quietstartOpenRecords', true); }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
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
