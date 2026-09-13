import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Hypium } from '@ohos/hypium';
import { util } from '@kit.ArkTS';
import { CatalogPart, LearningStore } from '../../../main/ets/core/LearningStore';

// Official stage-model runner; load UiTest modules after delegator initialization.
export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {
    hilog.info(0x0000, 'QuietStartProbe', '%{public}s', 'init: OpenHarmonyTestRunner onPrepare');
  }

  async onRun(): Promise<void> {
    hilog.info(0x0000, 'QuietStartProbe', '%{public}s', 'init: OpenHarmonyTestRunner onRun');
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const args = abilityDelegatorRegistry.getArguments();
    if ((args.parameters['-s mode'] || args.parameters['mode']) === 'catalogProbe') {
      const result = await delegator.executeShellCommand('bm dump -n com.ygkj.chelaile.standard.har -l', 5);
      delegator.printSync('CatalogProbe: exit=' + result.exitCode + ', output=' + result.stdResult.slice(0, 600) + '\n');
      await delegator.finishTest('Read-only catalog probe finished', 0);
      return;
    }
    if ((args.parameters['-s mode'] || args.parameters['mode']) === 'audit') {
      const store = new LearningStore(delegator.getAppContext().filesDir);
      delegator.printSync('QuietStartAuditRules: ' + JSON.stringify(store.readRules()) + '\n');
      delegator.printSync('QuietStartAuditDecisions: ' + JSON.stringify(store.readDecisions()) + '\n');
      delegator.printSync('QuietStartAuditDiagnostics: ' + JSON.stringify(store.readDiagnostics()) + '\n');
      await delegator.finishTest('QuietStart read-only audit complete', 0);
      return;
    }
    if ((args.parameters['-s mode'] || args.parameters['mode']) === 'catalogImport') {
      try {
        const encoded = args.parameters['-s catalog'] || args.parameters['catalog'];
        if (typeof encoded !== 'string' || encoded.length > 12000) { throw new Error('Invalid catalog input'); }
        const text = new util.TextDecoder('utf-8').decodeToString(new util.Base64Helper().decodeSync(encoded));
        const part = JSON.parse(text) as CatalogPart;
        const count = new LearningStore(delegator.getAppContext().filesDir).importCatalog(part);
        await delegator.finishTest('QuietStartCatalog: imported part ' + part.index + ', apps=' + count, 0);
      } catch (_) { await delegator.finishTest('QuietStartCatalog: import failed', 1); }
      return;
    }
    if ((args.parameters['-s mode'] || args.parameters['mode']) === 'skip') {
      await delegator.startAbility({ bundleName: 'com.tonghongxiang.quietstart', abilityName: 'EntryAbility', moduleName: 'entry' });
      const worker = await import('../worker/SkipWorker');
      await new Promise<void>((resolve) => { setTimeout(resolve, 1000); });
      const seconds: number = Number(args.parameters['-s seconds'] || args.parameters['seconds'] || '300');
      delegator.printSync('QuietStartWorker: device session started\n');
      const result = await worker.run(delegator, seconds);
      delegator.printSync('QuietStartWorker: ' + JSON.stringify(result) + '\n');
      await delegator.finishTest('QuietStart device session ended', result.state === 'error' ? 1 : 0);
      return;
    }
    const testsuite = await import('../test/List.test');
    Hypium.hypiumTest(delegator, args, testsuite.default);
  }
}
