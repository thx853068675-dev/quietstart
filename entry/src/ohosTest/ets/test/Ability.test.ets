import { Driver, ON, abilityDelegatorRegistry } from '@kit.TestKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, it, expect } from '@ohos/hypium';
import process from '@ohos.process';

const OWN_BUNDLE: string = 'com.tonghongxiang.quietstart';
const TAG: string = 'QuietStartProbe';
const MAX_WAIT_MS: number = 30000;

// This explicitly launched device test only targets QuietStart's dedicated
// probe controls. It never clicks another application or coordinates.
export default function abilityTest() {
  describe('QuietStartUiTestProbe', () => {
    it('clickOwnVisibleProbeAndVerifyResult', 0, async () => {
      try {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator();
        await delegator.startAbility({ bundleName: OWN_BUNDLE, abilityName: 'EntryAbility', moduleName: 'entry',
          parameters: { quietstartProbe: true } });
        await new Promise<void>((resolve) => { setTimeout(resolve, 1200); });
        const context = delegator.getAppContext();
        const token: string = `${context.applicationInfo.name}@${process.pid}@${process.uid}@${context.area}`;
        delegator.printSync('QuietStartProbe: official connection token ' + token + '\n');
        delegator.printSync('QuietStartProbe: initializing Driver after asynchronous setup\n');
        hilog.info(0x0000, TAG, '%{public}s', 'init: creating official UiTest Driver');
        const driver: Driver = Driver.create();
        if (!driver) { throw new Error('Official UiTest Driver initialization returned null'); }
        delegator.printSync('QuietStartProbe: Driver connected\n');
        const deadline: number = Date.now() + MAX_WAIT_MS;
        let lastFocused: string = '';
        let clicked: boolean = false;
        let passed: boolean = false;

        while (Date.now() < deadline) {
          const focusedWindow = await driver.findWindow({ focused: true });
          const bundle: string = focusedWindow ? await focusedWindow.getBundleName() : '';
          if (bundle !== lastFocused) {
            hilog.info(0x0000, TAG, 'windows: focused=%{public}s', bundle);
            lastFocused = bundle;
          }

          if (bundle === OWN_BUNDLE) {
            const success = await driver.findComponent(ON.id('quietstart-probe-success').inWindow(OWN_BUNDLE));
            if (success) {
              if (!clicked) {
                throw new Error('Probe was already completed before UiTest clicked; reset the probe and retry.');
              }
              passed = true;
              break;
            }

            if (!clicked) {
              const skip = await driver.findComponent(ON.id('quietstart-probe-skip').inWindow(OWN_BUNDLE));
              if (skip && await skip.isClickable() && await skip.isEnabled()) {
                const bounds = await skip.getBounds();
                const windowBounds = await focusedWindow.getBounds();
                const insideWindow: boolean = bounds.right > bounds.left && bounds.bottom > bounds.top &&
                  bounds.left >= windowBounds.left && bounds.top >= windowBounds.top &&
                  bounds.right <= windowBounds.right && bounds.bottom <= windowBounds.bottom;
                const beforeClickWindow = await driver.findWindow({ focused: true });
                if (insideWindow && beforeClickWindow &&
                  await beforeClickWindow.getBundleName() === OWN_BUNDLE && Date.now() < deadline) {
                  hilog.info(0x0000, TAG, '%{public}s', 'click: own visible quietstart-probe-skip');
                  await skip.click();
                  clicked = true;
                }
              }
            }
          }

          const remaining: number = deadline - Date.now();
          if (remaining > 0) {
            await driver.delayMs(Math.min(250, remaining));
          }
        }

        expect(clicked).message('UiTest did not click the own-app probe within 30 seconds.').assertTrue();
        expect(passed).message('The own-app success marker did not appear after UiTest click.').assertTrue();
        hilog.info(0x0000, TAG, '%{public}s', 'pass: click completed and quietstart-probe-success observed');
        delegator.printSync('QuietStartProbe: PASS - automatically clicked and observed success marker\n');
      } catch (error) {
        const failure = error as BusinessError;
        hilog.error(0x0000, TAG, 'errors: code=%{public}s message=%{public}s',
          `${failure.code}`, failure.message);
        throw new Error(failure.message);
      }
    });
  });
}
