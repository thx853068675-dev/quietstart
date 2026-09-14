const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const sdkApp = process.env.DEVECO_APP || '/Applications/DevEco-Studio.app';
const ts = require(path.join(sdkApp, 'Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript'));

const HUYA = 'com.duowan.hyhos';
const YOUKU = 'com.youku.next';
const HOME = 'com.huawei.hmos.launcher';
const DIRECTORY = '/mock/app/files';
const WINDOW = { left: 0, top: 0, right: 1320, bottom: 2100 };
const BUTTON = { left: 1100, top: 90, right: 1220, bottom: 170 };

// Execute the shipped ETS source. The doubles below model platform primitives,
// never the worker's rules, session lifecycle or decision to click.
function load(relative, mocks, globals = {}) {
  const filename = path.join(__dirname, '..', relative);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const exports = {};
  vm.runInNewContext(code, {
    exports,
    require(name) {
      assert.ok(Object.hasOwn(mocks, name), `Unexpected source dependency: ${name}`);
      return mocks[name];
    },
    Date, ...globals
  }, { filename });
  return exports;
}

class Selector {
  constructor(attributes = {}) { this.attributes = attributes; }
  id(id, pattern) { return new Selector({ ...this.attributes, id, ...(pattern ? { pattern } : {}) }); }
  text(text, pattern) { return new Selector({ ...this.attributes, text, ...(pattern ? { pattern } : {}) }); }
  description(description, pattern) { return new Selector({ ...this.attributes, description, ...(pattern ? { pattern } : {}) }); }
  clickable(clickable = true) { return new Selector({ ...this.attributes, clickable }); }
  withinComponent(component) { return new Selector({ ...this.attributes, ancestor: component.__node }); }
  inWindow(bundle) { return new Selector({ ...this.attributes, bundle }); }
}

function adNodes(bundle) {
  const node = (attributes) => ({ bundle, enabled: true, clickable: false,
    bounds: { ...BUTTON }, ...attributes });
  if (bundle === HUYA) {
    return [node({ id: 'huyaSkipButton', text: '跳过', clickable: true }),
      node({ id: 'topAdText', text: '广告' })];
  }
  const target = node({ id: 'oneadbiz_ad_countdown', text: '', clickable: true });
  return [target, node({ id: 'countdown_label', text: '跳过广告', parent: target }),
    node({ id: 'oneadbiz_splash_logo', text: '' })];
}

function homeNode(bundle) {
  return { bundle, id: 'homepage', text: '首页', enabled: true, clickable: false,
    bounds: { ...WINDOW } };
}

function baseFixture(options = {}) {
  const state = {
    now: 1000,
    foreground: options.bundle || HUYA,
    nodes: adNodes(options.bundle || HUYA),
    reminderCalls: [],
    clickCalls: [],
    apiCalls: [],
    snapshots: [],
    activeApiCalls: 0,
    peakApiCalls: 0,
    files: new Map(),
    timers: new Map(),
    nextTimer: 1,
    nextFd: 1,
    descriptors: new Map(),
    get elapsed() { return this.now - 1000; },
    setSettings(settings) { this.files.set(DIRECTORY + '/settings.json', JSON.stringify(settings)); },
    getSettings() { return JSON.parse(this.files.get(DIRECTORY + '/settings.json')); },
    advance(milliseconds) {
      this.now += milliseconds;
      options.onTime?.(this);
      for (const timer of this.timers.values()) {
        while (this.now >= timer.next) {
          timer.next += timer.interval;
          timer.callback();
        }
      }
    }
  };
  state.setSettings({ enabled: true, packages: [HUYA, YOUKU], testUntil: 0, discoverApps: true, ignoredPackages: [], remindersEnabled: false, newRuleRemindersEnabled: true, autoEnableRules: false, learningEnabled: true, stopRequested: false, catalogRequestAt: 0 });
  options.configure?.(state);

  const fileIo = {
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    listFileSync(directory) { return [...state.files.keys()].filter(p=>p.startsWith(directory+'/')&&!p.slice(directory.length+1).includes('/')).map(p=>p.slice(directory.length+1)); },
    unlinkSync(filename) { state.files.delete(filename); },
    statSync(filename) { if (!state.files.has(filename)) throw new Error('File missing'); return { size: Buffer.byteLength(state.files.get(filename)) }; },
    readTextSync(filename) {
      options.onRead?.(filename, state);
      if (!state.files.has(filename)) throw Object.assign(new Error('File missing'), { code: 13900002 });
      return state.files.get(filename);
    },
    openSync(filename) {
      if (options.storageFailure) throw Object.assign(new Error('Disk write failed'), { code: 13900012 });
      const fd = state.nextFd++;
      state.descriptors.set(fd, filename);
      state.files.set(filename, '');
      return { fd };
    },
    writeSync(fd, value) {
      assert.ok(state.descriptors.has(fd));
      state.files.set(state.descriptors.get(fd), value);
    },
    closeSync(file) { assert.ok(state.descriptors.delete(typeof file === 'number' ? file : file.fd)); },
    renameSync(source, destination) {
      assert.ok(state.files.has(source));
      const data = state.files.get(source);
      state.files.set(destination, data);
      state.files.delete(source);
      if (destination.endsWith('/debug-status.json')) state.snapshots.push(JSON.parse(data));
    }
  };

  async function invoke(name, result) {
    assert.equal(state.activeApiCalls, 0, `Concurrent UiTest API call: ${name}`);
    state.activeApiCalls += 1;
    state.peakApiCalls = Math.max(state.peakApiCalls, state.activeApiCalls);
    state.apiCalls.push(name);
    try {
      await Promise.resolve();
      state.advance(1);
      options.onApi?.(name, state);
      if (options.apiFailure === name) throw Object.assign(new Error('UiTest unavailable'), { code: 17000001 });
      return result();
    } finally {
      state.activeApiCalls -= 1;
    }
  }

  function component(node) {
    return {
      __node: node,
      isEnabled: () => invoke('component.isEnabled', () => node.enabled),
      isClickable: () => invoke('component.isClickable', () => node.clickable),
      getId: () => invoke('component.getId', () => node.id || ''),
      getParent: () => invoke('component.getParent', () => node.parent ? component(node.parent) : null),
      getText: () => invoke('component.getText', () => node.text),
      getDescription: () => invoke('component.getDescription', () => node.description || ''),
      getBounds: () => invoke('component.getBounds', () => ({ ...node.bounds })),
      click: () => invoke('component.click', () => {
        // Record attempts before checking visibility, so the test cannot mask an
        // unsafe worker call by having the fake platform reject it afterwards.
        state.clickCalls.push({ at: state.now, bundle: node.bundle, id: node.id });
        assert.equal(state.foreground, node.bundle, 'Worker tried clicking a background app');
        assert.ok(state.nodes.includes(node), 'Worker tried clicking a stale component');
        if (options.onClick) options.onClick(node, state);
        else state.nodes = state.nodes.filter(item => item.bundle !== node.bundle).concat(homeNode(node.bundle));
      })
    };
  }

  const driver = {
    click: (x, y) => invoke('driver.click', () => {
      const candidates = state.nodes.filter(node => node.bundle === state.foreground && node.enabled && node.clickable &&
        x >= node.bounds.left && x <= node.bounds.right && y >= node.bounds.top && y <= node.bounds.bottom);
      assert.equal(candidates.length, 1, 'Live point must hit exactly one enabled clickable target');
      const node = candidates[0];
      state.clickCalls.push({ at: state.now, bundle: node.bundle, id: node.id, x, y });
      if (options.onClick) options.onClick(node, state);
      else state.nodes = state.nodes.filter(item => item.bundle !== node.bundle).concat(homeNode(node.bundle));
    }),
    screenCapture: (path, bounds) => invoke('driver.screenCapture', () => options.onScreenCapture?.(path, bounds, state) ?? false),
    dumpLayout: (savePath) => invoke('driver.dumpLayout', () => {
      if (options.nullDiscoveryTree || (options.nullWholeTree && savePath.endsWith('/dismissal-snapshot.json'))) return false;
      const attrs = node => ({ type: node.type || '', bundleName: node.bundle, id: node.id || '', enabled: String(node.enabled), clickable: String(node.clickable), bounds: `[${node.bounds.left},${node.bounds.top}][${node.bounds.right},${node.bounds.bottom}]`,
        text: node.text || '', description: node.description || '', visible: node.visible === false ? 'false' : 'true', opacity: '1', hostWindowId: '1' });
      const layout = { attributes: { type: 'root', bundleName: state.foreground, focused: 'true', visible: 'true', opacity: '1',
        bounds: `[0,0][${WINDOW.right},${WINDOW.bottom}]`, hostWindowId: '1' },
        children: state.nodes.filter(node => node.bundle === state.foreground && !node.parent).map(function tree(node) {
          return { attributes: attrs(node), children: state.nodes.filter(child => child.parent === node).map(tree) };
        }) };
      options.onLayout?.(layout, state, savePath);
      state.files.set(savePath, JSON.stringify(layout));
      return true;
    }),
    findWindow: (filter) => invoke('driver.findWindow', () => {
      state.windowFilters = [...(state.windowFilters || []), filter];
      const bundle = options.windowBundle ? options.windowBundle(filter, state) : state.foreground;
      return bundle ? {
        getBundleName: () => invoke('window.getBundleName', () => bundle),
        getBounds: () => invoke('window.getBounds', () => ({ ...WINDOW }))
      } : undefined;
    }),
    findComponents: (selector) => invoke('driver.findComponents', () => {
      const wanted = selector.attributes;
      if (options.nullWholeTree && Object.keys(wanted).length === 1 && wanted.bundle) return null;
      const matches = state.nodes.filter(node => node.bundle === state.foreground &&
        Object.entries(wanted).every(([key, value]) => {
          if (key === 'pattern') return true;
          if (key === 'ancestor') {
            for (let parent = node.parent; parent; parent = parent.parent) if (parent === value) return true;
            return false;
          }
          if (['text', 'description', 'id'].includes(key)) {
            if (wanted.pattern === 'regexInsensitive') return new RegExp('^(?:' + value + ')$', 'i').test(node[key] || '');
            return wanted.pattern === 'contains' ? (node[key] || '').includes(value) : (node[key] || '') === value;
          }
          return node[key] === value;
        })).map(component);
      // Official UiTest returns null when a selector matches no components.
      // Keep an optional empty-array mode for compatibility coverage as well.
      return matches.length > 0 || options.emptyMatchesAsArray ? matches : null;
    }),
    delayMs: (milliseconds) => invoke('driver.delayMs', () => { state.advance(milliseconds); })
  };
  const fakeClock = class extends Date { static now() { return state.now; } };
  const globals = {
    Date: fakeClock,
    setInterval(callback, interval) {
      const id = state.nextTimer++;
      state.timers.set(id, { callback, interval, next: state.now + interval });
      return id;
    },
    clearInterval(id) { state.timers.delete(id); },
    setTimeout(callback, ms) { state.advance(ms); callback(); return 1; }
  };
  const localStore = load('entry/src/main/ets/core/LocalStore.ets', { '@kit.CoreFileKit': { fileIo } }, globals);
  const profile = load('entry/src/main/ets/core/RecognitionProfile.ets', {}, globals);
  const learningStore = load('entry/src/main/ets/core/LearningStore.ets', { './RecognitionProfile': profile, '@kit.CoreFileKit': { fileIo } }, globals);
  const rules = load('entry/src/ohosTest/ets/worker/Rules.ets', { '../../../main/ets/core/LearningStore': learningStore }, globals);
  if (options.approvedInitialRules) {
    // Existing-user fixtures start with explicit saved approvals. Production
    // never seeds these records; unapproved-app tests use baseFixture directly.
    for (const bundle of [HUYA, YOUKU]) {
      const rule = new learningStore.LearnedRule();
      rule.bundle = bundle;
      rule.targetId = bundle === HUYA ? 'huyaSkipButton' : 'oneadbiz_ad_countdown';
      rule.label = bundle === HUYA ? '跳过' : '跳过广告';
      rule.marker = bundle === HUYA ? '广告' : 'label';
      rule.left = BUTTON.left / WINDOW.right; rule.right = BUTTON.right / WINDOW.right;
      rule.top = BUTTON.top / WINDOW.bottom; rule.bottom = BUTTON.bottom / WINDOW.bottom;
      rule.aspect = WINDOW.right / WINDOW.bottom;
      rule.firstSeen = state.now; rule.lastSeen = state.now;
      rule.key = learningStore.ruleKey(rule);
      const records = JSON.parse(state.files.get(DIRECTORY + '/learned-rules.json') || '[]');
      records.push(rule); state.files.set(DIRECTORY + '/learned-rules.json', JSON.stringify(records));
      const decisions = JSON.parse(state.files.get(DIRECTORY + '/rule-decisions.json') || '[]');
      decisions.push({ key: rule.key, state: 'approved', at: state.now, templateAt: state.now });
      state.files.set(DIRECTORY + '/rule-decisions.json', JSON.stringify(decisions));
    }
  }
  driver.createUIEventObserver = () => ({ once(type, kind, options, callback) { state.manualCallback = callback; state.manualTimeout = options.timeout; } });
  const kit = { ComponentEventType: { COMPONENT_CLICKED: 1 }, ON: new Selector(), MatchPattern: { CONTAINS: 'contains', EQUALS: 'equals', REG_EXP_ICASE: 'regexInsensitive' },
    Driver: { create: () => options.nullDriver ? null : driver } };
  const rulePack = load('entry/src/main/ets/core/RulePack.ets', {}, globals);
  const builtinPack = load('entry/src/main/ets/core/BuiltinRulePack.ets', { './RulePack': rulePack }, globals);
  const packStore = load('entry/src/main/ets/core/RulePackStore.ets', {
    '@kit.CoreFileKit': { fileIo }, './RulePack': rulePack, './BuiltinRulePack': builtinPack
  }, globals);
  const snapshot = load('entry/src/ohosTest/ets/worker/SnapshotLayout.ets', {'@kit.TestKit': kit, '../../../main/ets/core/LearningStore': learningStore}, globals);
  const structural = load('entry/src/ohosTest/ets/worker/StructuralExperience.ets', { '@kit.TestKit': kit, '../../../main/ets/core/LearningStore': learningStore, './Rules': rules }, globals);
  const capture = load('entry/src/ohosTest/ets/worker/ProfileCapture.ets', { './StructuralExperience': structural, '../../../main/ets/core/RecognitionProfile': profile, '../../../main/ets/core/LearningStore': learningStore }, globals);
  const learningWorker = load('entry/src/ohosTest/ets/worker/LearningWorker.ets', {
    './ProfileCapture': capture,
    './SnapshotLayout': snapshot, './StructuralExperience': structural,
    '@kit.TestKit': kit, '../../../main/ets/core/LearningStore': learningStore, './Rules': rules,
    '../../../main/ets/core/RulePack': rulePack
  }, globals);
  const adFree = load('entry/src/main/ets/core/AdFreeStore.ets', { '@kit.CoreFileKit': { fileIo }, './LearningStore': learningStore, './LocalStore': localStore }, globals);
  const visual = load('entry/src/ohosTest/ets/worker/VisualRecognition.ets', {
    '@kit.CoreFileKit': { fileIo }, '@kit.TestKit': kit,
    '../../../main/ets/core/RulePack': rulePack, '../../../main/ets/core/LearningStore': learningStore,
    './LearningWorker': learningWorker,
    './ImageAdEvidence': { readImageAd: async (_driver, _directory, bounds) => options.onImageAd ? options.onImageAd(state, bounds) : false }
  }, globals);
  const manual = load('entry/src/ohosTest/ets/worker/ManualLearningWorker.ets', { '@kit.TestKit': kit, '@kit.CoreFileKit': { fileIo }, '../../../main/ets/core/LearningStore': learningStore, './LearningWorker': learningWorker }, globals);
  const worker = load('entry/src/ohosTest/ets/worker/SkipWorker.ets', {
    '@kit.ArkTS': { process: { pid: 1234 } },
    './WorkerHealth': load('entry/src/ohosTest/ets/worker/WorkerHealth.ets', { '@kit.CoreFileKit': { fileIo } }, globals),
    '../../../main/ets/core/SupervisionStore': load('entry/src/main/ets/core/SupervisionStore.ets', { '@kit.CoreFileKit': { fileIo } }, globals),
    './ManualLearningWorker': manual,
    '../../../main/ets/core/DesktopAppNames': load('entry/src/main/ets/core/DesktopAppNames.ets', {}, globals),
    './VisualRecognition': visual,
    '../../../main/ets/core/RulePackStore': packStore,
    '../../../main/ets/core/AdFreeStore': adFree,
    '@kit.TestKit': kit,
    '@kit.CoreFileKit': { fileIo },
    '@kit.BasicServicesKit': { deviceInfo: { sdkApiVersion: options.apiVersion || 24 }, power: { isActive: () => options.screenActive ? options.screenActive(state) : true } },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, error() {} } },
    '../../../main/ets/core/AppNameResolver': { AppNameResolver: class { tick() {} close() {} requestSoon() {} } },
    '../../../main/ets/core/SkipReminder': { SkipReminder: class { async showLearned(name, approved) { state.newRuleNotifications = [...(state.newRuleNotifications || []), {name,approved}]; } async show(name) { state.reminderCalls.push(name); } } },
    '../../../main/ets/core/LocalStore': localStore,
    './Rules': rules,
    '../../../main/ets/core/LearningStore': learningStore,
    './LearningWorker': learningWorker
  }, globals);

  return {
    state,
    learningStore: new learningStore.LearningStore(DIRECTORY),
    models: learningStore,
    adFree: new adFree.AdFreeStore(DIRECTORY),
    energy: rules,
    driver,
    learningWorker,
    manualWorker: new manual.ManualLearningWorker(DIRECTORY, options.manualDelegator),
    rulePack, builtinPack, packs: new packStore.RulePackStore(DIRECTORY),
    async run(seconds = 4) {
      const status = await worker.run({ getAppContext: () => ({ filesDir: DIRECTORY }),
        executeShellCommand: async (command) => {
          assert.equal(command, 'bm dump -a -l');
          state.catalogReads = (state.catalogReads || 0) + 1;
          return { exitCode: 0, stdResult: JSON.stringify([{ bundleName: HUYA, label: '虎牙直播' },
            { bundleName: YOUKU, label: '优酷视频' }]) };
        }
      }, seconds, options.supervisorToken || '', options.recoveryAttempt || 0);
      assert.equal(status.running, false);
      assert.equal(state.timers.size, 0, 'Worker left a heartbeat timer running');
      assert.equal(state.activeApiCalls, 0);
      assert.equal(state.files.has(DIRECTORY + '/dismissal-snapshot.json'), false, 'Temporary UI snapshot must be deleted');
      assert.equal(state.files.has(DIRECTORY + '/discovery-snapshot.json'), false, 'Discovery snapshot must be deleted');
      if (!options.storageFailure && !options.rejectedSession) {
        const saved = JSON.parse(state.files.get(DIRECTORY + '/debug-status.json'));
        assert.equal(saved.running, false, 'Final persisted status must be offline');
        assert.equal(saved.clickCount, status.clickCount);
      }
      return status;
    }
  };
}

function fixture(options = {}) { return baseFixture({ ...options, approvedInitialRules: true }); }

for (const bundle of [HUYA, YOUKU]) {
  test(`clicks the explicitly approved learned rule for ${bundle}, then independently observes dismissal`, async () => {
    const f = fixture({ bundle });
    const status = await f.run();
    assert.equal(f.state.clickCalls.length, 1);
    assert.equal(f.state.clickCalls[0].bundle, bundle);
    assert.equal(status.attemptCount, 1);
    assert.equal(status.clickCount, 1);
    assert.equal(status.observedDismissedCount, 1);
    assert.ok(status.history.some(item => item.result === 'observedDismissed'));
    assert.equal(f.state.reminderCalls.length, 1, 'Reminder dispatch follows verified dismissal');
    assert.equal(f.state.peakApiCalls, 1);
  });
}

test('null matches for ad selectors are valid disappearance evidence when the same app has a live homepage', async () => {
  for (const bundle of [HUYA, YOUKU]) {
    const f = fixture({ bundle });
    const status = await f.run();
    assert.ok(f.state.nodes.some(node => node.bundle === bundle && node.id === 'homepage'));
    assert.equal(status.clickCount, 1);
    assert.equal(status.observedDismissedCount, 1);
    assert.equal(status.state, 'finished');
  }
});

test('also accepts empty-array matches when the same app has a live homepage', async () => {
  for (const bundle of [HUYA, YOUKU]) {
    const f = fixture({ bundle, emptyMatchesAsArray: true });
    const status = await f.run();
    assert.equal(status.clickCount, 1);
    assert.equal(status.observedDismissedCount, 1);
  }
});

test('never confirms dismissal if the full app tree query returns null', async () => {
  for (const bundle of [HUYA, YOUKU]) {
    const f = fixture({ bundle, nullWholeTree: true });
    const status = await f.run();
    // The page is modeled as present, but its tree query failed. Missing ad
    // selectors alone must not turn this failed query into a success report.
    assert.ok(f.state.nodes.some(node => node.id === 'homepage'));
    assert.equal(status.clickCount, 1);
    assert.equal(status.observedDismissedCount, 0);
    assert.ok(status.history.some(item => item.result === 'unverified'));
    assert.equal(f.state.reminderCalls.length, 0, 'Unverified clicks must not notify success');
    assert.equal(status.state, 'finished');
  }
});

test('empty or unavailable pages do not imply dismissal and missing candidates remain harmless', async () => {
  for (const bundle of [HUYA, YOUKU]) {
    const missingCandidate = fixture({ bundle, configure(state) { state.nodes = [homeNode(bundle)]; } });
    const initialStatus = await missingCandidate.run();
    assert.equal(initialStatus.clickCount, 0);
    assert.equal(initialStatus.state, 'finished');
    const gonePage = fixture({ bundle, onClick(_, state) { state.nodes = []; } });
    const status = await gonePage.run();
    assert.equal(status.clickCount, 1);
    assert.equal(status.observedDismissedCount, 0);
    assert.equal(status.state, 'finished');
  }
});

test('does not click when settings are disabled, absent, malformed or not whitelisted', async () => {
  const changes = [
    state => state.setSettings({ enabled: false, packages: [HUYA] }),
    state => state.setSettings({ enabled: true, packages: [] }),
    state => state.setSettings({ enabled: true, packages: 'invalid' }),
    state => state.files.delete(DIRECTORY + '/settings.json'),
    state => state.files.set(DIRECTORY + '/settings.json', '{broken')
  ];
  for (const configure of changes) {
    const f = fixture({ configure });
    const status = await f.run();
    assert.equal(f.state.clickCalls.length, 0);
    assert.equal(status.observedDismissedCount, 0);
  }
});

test('never transfers another app’s approval to an unapproved foreground app', async () => {
  const bundle = 'com.example.unrelated';
  const f = fixture({ bundle, configure(state) {
    state.setSettings({ enabled: true, packages: [bundle] });
    state.nodes = adNodes(HUYA).map(node => ({ ...node, bundle }));
  } });
  await f.run();
  assert.equal(f.state.clickCalls.length, 0);
});

test('rechecks foreground immediately before clicking', async () => {
  const f = fixture({ onApi(name, state) { if (name === 'window.getBounds') state.foreground = HOME; } });
  await f.run();
  assert.equal(f.state.clickCalls.length, 0);
});

test('rechecks the switch and whitelist after locating a candidate', async () => {
  for (const revoke of [settings => { settings.enabled = false; }, settings => { settings.packages = []; }]) {
    const f = fixture({ onApi(name, state) {
      if (name === 'window.getBounds') {
        const settings = state.getSettings();
        revoke(settings);
        state.setSettings(settings);
      }
    } });
    await f.run();
    assert.equal(f.state.clickCalls.length, 0);
  }
});

test('requires unique, enabled targets with valid bounds matching the approved template', async () => {
  const variations = [
    nodes => { nodes[0].bounds.left = 10; },
    nodes => { nodes[0].bounds.top = 1800; nodes[0].bounds.bottom = 1900; },
    nodes => { nodes[0].bounds.right = nodes[0].bounds.left; },
    nodes => { nodes[0].bounds.right = WINDOW.right + 1; },
    nodes => { nodes[0].enabled = false; },
    nodes => { nodes[0].clickable = false; },
    nodes => { nodes.push({ ...nodes[0], id: 'anotherSkip' }); }
  ];
  for (const change of variations) {
    const f = fixture({ configure(state) { change(state.nodes); } });
    await f.run();
    assert.equal(f.state.clickCalls.length, 0);
  }
});

test('requires the learned ad evidence and skip label, so an onboarding skip is ignored', async () => {
  for (const options of [
    { configure(state) { state.nodes.find(node => node.id === 'topAdText').text = '欢迎使用'; } },
    { configure(state) { state.nodes = state.nodes.filter(node => node.id !== 'topAdText'); } },
    { bundle: YOUKU, configure(state) { state.nodes.find(node => node.text === '跳过广告').text = '跳过登录'; } }
  ]) {
    const f = fixture(options);
    await f.run();
    assert.equal(f.state.clickCalls.length, 0);
  }
});

test('does not equate a successful click with dismissal, and does not retry the same session', async () => {
  for (const onClick of [() => {}, (_, state) => {
    state.nodes = state.nodes.filter(node => node.id === 'topAdText');
  }]) {
    const f = fixture({ onClick });
    const status = await f.run(12);
    assert.equal(f.state.clickCalls.length, 1);
    assert.equal(status.clickCount, 1);
    assert.equal(status.observedDismissedCount, 0);
    assert.equal(status.retainedCount + status.unverifiedCount, 1);
  }
});

test('does not report dismissal merely because the foreground app changed after clicking', async () => {
  const f = fixture({ onClick(_, state) { state.nodes = []; state.foreground = HOME; } });
  const status = await f.run();
  assert.equal(status.clickCount, 1);
  assert.equal(status.observedDismissedCount, 0);
  assert.ok(status.history.some(item => item.result === 'unverified'));
});

test('can handle a new foreground entry, with at most one click per entry', async () => {
  let reentered = false;
  const f = fixture({ onTime(state) {
    if (state.elapsed >= 2000 && state.elapsed < 2500) state.foreground = HOME;
    if (state.elapsed >= 2500 && !reentered) {
      reentered = true;
      state.foreground = HUYA;
      state.nodes = adNodes(HUYA);
    }
  } });
  const status = await f.run(6);
  assert.equal(f.state.clickCalls.length, 2);
  assert.equal(status.observedDismissedCount, 2);
});

test('does not click an ad appearing after the twenty-second foreground window', async () => {
  let appeared = false;
  const f = fixture({
    configure(state) { state.nodes = []; },
    onTime(state) {
      if (state.elapsed >= 21000 && !appeared) { appeared = true; state.nodes = adNodes(HUYA); }
    }
  });
  await f.run(24);
  assert.equal(appeared, true);
  assert.equal(f.state.clickCalls.length, 0);
});

test('rechecks the twenty-second deadline after a slow component query', async () => {
  let delayed = false;
  const f = fixture({ onApi(name, state) {
    if (name === 'component.getBounds' && !delayed) { delayed = true; state.advance(21000); }
  } });
  await f.run(24);
  assert.equal(delayed, true);
  assert.equal(f.state.clickCalls.length, 0);
});

test('fails closed when UiTest initialization or an interface call fails', async () => {
  const nullDriver = fixture({ nullDriver: true });
  const nullStatus = await nullDriver.run();
  assert.equal(nullDriver.state.clickCalls.length, 0);
  assert.equal(nullStatus.state, 'error');
  const failed = fixture({ apiFailure: 'driver.findWindow' });
  const failedStatus = await failed.run();
  assert.equal(failed.state.clickCalls.length, 0);
  assert.equal(failedStatus.errorCode, '17000001');
  assert.equal(failedStatus.state, 'error');
});

test('recovers from a transient missing window before matching an ad', async () => {
  let invalidated = false;
  const f = fixture({ onApi(name) {
    if (name === 'driver.findWindow' && !invalidated) {
      invalidated = true;
      throw Object.assign(new Error('Display Window is gone'), { code: 17000004 });
    }
  } });
  const status = await f.run();
  assert.equal(invalidated, true);
  assert.equal(f.state.clickCalls.length, 1);
  assert.equal(status.observedDismissedCount, 1);
  assert.equal(status.state, 'finished');
  assert.equal(status.errorCode, '');
});

test('window invalidation during verification retries fresh observations without retrying the click', async () => {
  let invalidated = false;
  const f = fixture({ onApi(name, state) {
    if (name === 'driver.findWindow' && state.clickCalls.length === 1 && !invalidated) {
      invalidated = true;
      throw Object.assign(new Error('Display Window is gone'), { code: 17000004 });
    }
  } });
  const status = await f.run();
  assert.equal(invalidated, true);
  assert.equal(f.state.clickCalls.length, 1);
  assert.equal(status.observedDismissedCount, 1);
  assert.equal(status.unverifiedCount, 0);
  assert.equal(status.state, 'finished');
});

test('a stale target at click time consumes this session attempt and never falls back to coordinates', async () => {
  const f = fixture({ onApi(name) {
    if (name === 'component.click') {
      throw Object.assign(new Error('Component is gone'), { code: 17000004 });
    }
  } });
  const status = await f.run(12);
  assert.equal(f.state.apiCalls.filter(name => name === 'component.click').length, 1);
  assert.equal(status.attemptCount, 1);
  assert.equal(status.clickCount, 0);
  assert.equal(status.observedDismissedCount, 0);
  assert.equal(status.state, 'finished');
});

test('does not start clicking when the status file cannot be written', async () => {
  const f = fixture({ storageFailure: true });
  const status = await f.run();
  assert.equal(f.state.clickCalls.length, 0);
  assert.equal(status.state, 'error');
  assert.equal(status.errorCode, '13900012');
});

test('persists live heartbeats while waiting with the switch off, then an offline final status', async () => {
  const f = fixture({ configure(state) { state.setSettings({ enabled: false, packages: [HUYA] }); } });
  await f.run(4);
  const live = f.state.snapshots.filter(status => status.running);
  assert.ok(live.length >= 2);
  for (let i = 1; i < live.length; i++) {
    assert.ok(live[i].heartbeatAt >= live[i - 1].heartbeatAt);
    assert.ok(live[i].heartbeatAt - live[i - 1].heartbeatAt <= 2250);
  }
  assert.equal(f.state.snapshots.at(-1).running, false);
  assert.equal(f.state.clickCalls.length, 0);
});

test('rejects unsupported or invalid run durations before contacting UiTest', async () => {
  for (const duration of [-1, 0.5, 43201, Infinity, NaN]) {
    const f = fixture();
    await assert.rejects(() => f.run(duration), /at most 43200/);
    assert.equal(f.state.apiCalls.length, 0);
    assert.equal(f.state.clickCalls.length, 0);
  }
});

test('zero-duration mode keeps running without a deadline until the user requests a stop', async () => {
  let requestedAt = 0;
  const f = fixture({ onTime(state) {
    if (state.elapsed >= 3500 && !requestedAt) {
      requestedAt = state.now;
      const settings = state.getSettings();
      settings.stopRequested = true;
      state.setSettings(settings);
    }
  } });
  const status = await f.run(0);
  assert.equal(status.expiresAt, 0);
  assert.equal(status.state, 'finished');
  assert.match(status.message, /用户已结束/);
  assert.equal(status.clickCount, 1);
  assert.equal(status.observedDismissedCount, 1);
  assert.ok(f.state.now >= requestedAt && f.state.now - requestedAt < 500);
  assert.ok(f.state.snapshots.filter(snapshot => snapshot.running).length >= 2);
  assert.ok(f.state.snapshots.every(snapshot => snapshot.expiresAt === 0));
});

test('a new activation clears only an old stop request and preserves user settings', async () => {
  let clearedDuringRun = false;
  const original = { enabled: false, packages: [YOUKU, 'com.example.saved'], testUntil: 123,
    stopRequested: true, remindersEnabled: true, newRuleRemindersEnabled: true, autoEnableRules: false, themeMode: 'dark', discoverApps: true, ignoredPackages: [], extraSetting: 'keep me', learningEnabled: true, catalogRequestAt: 0, autoAdFree: true, reminderDismissSeconds: 5, adFreeMinDays: 1, adFreeCleanChecks: 5, adFreeRecheckDays: 7 };
  const f = fixture({
    configure(state) { state.setSettings(original); },
    onTime(state) {
      if (state.elapsed < 1500) {
        const settings = state.getSettings();
        assert.equal(settings.stopRequested, false);
        assert.deepEqual(settings, { ...original, stopRequested: false });
        clearedDuringRun = true;
      } else {
        state.setSettings({ ...state.getSettings(), stopRequested: true });
      }
    }
  });
  const status = await f.run(0);
  assert.equal(clearedDuringRun, true);
  assert.equal(status.clickCount, 0);
  assert.equal(status.state, 'finished');
  assert.match(status.message, /用户已结束/);
  assert.deepEqual(f.state.getSettings(), original);
});

test('a stop request received during matching prevents the next click', async () => {
  const f = fixture({ onApi(name, state) {
    if (name === 'window.getBounds') {
      state.setSettings({ ...state.getSettings(), stopRequested: true });
    }
  } });
  const status = await f.run(0);
  assert.equal(f.state.clickCalls.length, 0);
  assert.equal(status.state, 'finished');
  assert.match(status.message, /用户已结束/);
});

test('a stop request during dismissal verification remains unverified and exits cleanly', async () => {
  const f = fixture({ onClick(_, state) {
    state.nodes = [homeNode(HUYA)];
    state.setSettings({ ...state.getSettings(), stopRequested: true });
  } });
  const status = await f.run(0);
  assert.equal(status.clickCount, 1);
  assert.equal(status.observedDismissedCount, 0);
  assert.equal(status.state, 'finished');
  assert.match(status.message, /用户已结束/);
  assert.ok(status.history.some(item => item.result === 'unverified'));
});

test('positive-duration sessions still expire at the requested deadline without a stop request', async () => {
  const f = fixture({ configure(state) { state.setSettings({ enabled: false, packages: [HUYA] }); } });
  const status = await f.run(3);
  assert.equal(status.expiresAt, status.startedAt + 3000);
  assert.equal(status.state, 'finished');
  assert.match(status.message, /限时/);
  assert.ok(f.state.now >= status.expiresAt && f.state.now - status.expiresAt < 10);
  assert.equal(f.state.getSettings().stopRequested, false);
});

test('keeps only the most recent twenty local processes with bounded detail across many app entries', async () => {
  let previousCycle = -1;
  const f = fixture({ onTime(state) {
    const cycle = Math.floor(state.elapsed / 2000);
    if (cycle !== previousCycle) {
      previousCycle = cycle;
      state.nodes = adNodes(HUYA);
    }
    state.foreground = state.elapsed % 2000 < 1500 ? HUYA : HOME;
  } });
  const status = await f.run(62);
  assert.ok(status.clickCount >= 8);
  assert.equal(new Set(status.history.map(r=>r.processId+':'+r.bundle)).size,20);
  assert.ok(status.history.length<=200);
  for(const id of new Set(status.history.map(r=>r.processId)))assert.ok(status.history.filter(r=>r.processId===id).length<=40);
  for (let i = 1; i < status.history.length; i++) {
    assert.ok(status.history[i].at <= status.history[i - 1].at);
  }
  assert.ok(f.state.snapshots.every(snapshot => snapshot.history.length <= 200));
});

const READER = 'com.example.reader';
function learningFixture(options = {}) {
  return baseFixture({ ...options, bundle: READER, configure(state) {
    state.setSettings({ enabled: true, packages: [READER], learningEnabled: true });
    state.nodes = [{ bundle: READER, id: 'custom_skip', text: '跳过广告 5s', enabled: true,
      clickable: true, bounds: { ...BUTTON } }];
    options.configure?.(state);
  } });
}

async function observeAndApprove(f) {
  const first = await f.run(2);
  assert.equal(first.clickCount, 0, 'An unapproved new rule must never click');
  const rules = f.learningStore.readRules();
  assert.equal(rules.length, 1);
  assert.equal(rules[0].observations, 1, 'Repeated scans count as one observation per foreground entry');
  f.learningStore.decide(rules[0].key, 'approved');
  return rules[0];
}

test('legacy name catalogs stay separate from discovered apps and never trigger a shell read', async () => {
  const f = learningFixture();
  f.learningStore.saveCatalog({ source: 'computer', updatedAt: 1, requestAt: 0, error: 'old refresh failure',
    apps: [{ bundleName: HUYA, label: '虎牙直播' }, { bundleName: READER, label: '阅读器' }] });
  await f.run(1);
  assert.equal(f.state.catalogReads || 0, 0);
  const managed = f.learningStore.managedApps([READER]);
  assert.equal(managed.length, 1, 'Unvisited entries from an old full catalog must not appear');
  assert.equal(managed[0].label, '阅读器');
  assert.equal(f.learningStore.readSeenApps()[0].bundleName, READER);
  assert.equal(f.learningStore.parseApps(JSON.stringify([{ bundleName: READER, label: 'A' },
    { bundleName: READER, label: 'B' }, { bundleName: 'bad;command', label: 'bad' }])).length, 1);
});

test('new app is learned without clicking, then its approved rule works after a fresh activation', async () => {
  const f = learningFixture();
  const rule = await observeAndApprove(f);
  const status = await f.run(4);
  assert.equal(status.clickCount, 1);
  assert.equal(status.observedDismissedCount, 1);
  const stored = f.learningStore.readRules()[0];
  assert.equal(stored.key, rule.key);
  assert.equal(stored.observations, 2);
  assert.equal(stored.attempts, 1);
  assert.equal(stored.successes, 1);
  assert.equal(f.models.ruleState(stored, f.learningStore.readDecisions()), 'approved');
});

test('learning paused, discovery disabled for unselected apps, or explicit exclusion prevents capture', async () => {
  for (const config of [{ ignoredPackages: [READER] }, { packages: [], discoverApps: false }, { learningEnabled: false }]) {
    const f = learningFixture({ configure(state) { state.setSettings({ ...state.getSettings(), ...config }); } });
    await f.run(2);
    assert.equal(f.learningStore.readRules().length, 0);
    assert.equal(f.state.clickCalls.length, 0);
  }
  const f = learningFixture();
  await observeAndApprove(f);
  f.state.setSettings({ ...f.state.getSettings(), learningEnabled: false });
  assert.equal((await f.run(4)).observedDismissedCount, 1);
});

test('plain onboarding skip, ambiguous controls, content skip and oversized controls are not learned', async () => {
  for (const variant of ['onboarding', 'duplicate', 'content', 'oversized', 'disabled']) {
    const f = learningFixture({ configure(state) {
      const node = state.nodes[0];
      if (variant === 'onboarding') node.text = '跳过';
      if (variant === 'duplicate') state.nodes.push({ ...node, id: 'secondSkip' });
      if (variant === 'content') node.text = '跳过片头';
      if (variant === 'oversized') node.bounds = { left: 50, top: 100, right: 1250, bottom: 700 };
      if (variant === 'disabled') node.enabled = false;
    } });
    await f.run(2);
    assert.equal(f.learningStore.readRules().length, 0, variant);
    assert.equal(f.state.clickCalls.length, 0, variant);
  }
});

test('a plain skip can be learned only with an explicit independent ad marker', async () => {
  const f = learningFixture({ configure(state) {
    state.nodes[0].text = '跳过';
    state.nodes.push({ bundle: READER, id: 'ad-marker', text: '广告', enabled: true,
      clickable: false, bounds: { left: 20, right: 80, top: 100, bottom: 140 } });
  } });
  const rule = await observeAndApprove(f);
  assert.equal(rule.label, '跳过');
  assert.equal(rule.marker, '广告');
  assert.equal((await f.run(4)).observedDismissedCount, 1);
});

test('nonclickable skip label requires a unique small clickable ancestor from the actual UI tree', async () => {
  const f = learningFixture({ configure(state) {
    const label = state.nodes[0]; label.clickable = false;
    const parent = { ...label, id: 'skip_container', text: '', clickable: true };
    label.parent = parent;
    state.nodes.push(parent);
  } });
  const rule = await observeAndApprove(f);
  assert.equal(rule.targetId, 'skip_container');
  assert.equal((await f.run(4)).clickCount, 1);
  assert.equal(f.state.clickCalls[0].id, 'skip_container');
});

test('identical overlapping coordinates without ancestry are not a learned click target', async () => {
  const f = learningFixture({ configure(state) {
    state.nodes[0].clickable = false;
    state.nodes.push({ ...state.nodes[0], id: 'overlay', text: '', clickable: true });
  } });
  await f.run(2);
  assert.equal(f.learningStore.readRules().length, 0);
});

test('rejecting a rule or removing its app blocks it while retaining learned data', async () => {
  for (const action of ['reject', 'remove']) {
    const f = learningFixture();
    const rule = await observeAndApprove(f);
    if (action === 'reject') f.learningStore.decide(rule.key, 'rejected');
    else f.state.setSettings({ ...f.state.getSettings(), packages: [] });
    assert.equal((await f.run(4)).clickCount, 0);
    assert.equal(f.learningStore.readRules().length, 1);
  }
});

test('approval is checked again after asynchronous component queries', async () => {
  let revoke = false;
  const f = learningFixture({ onApi(name, state) {
    if (revoke && name === 'component.isClickable') {
      const rules = JSON.parse(state.files.get(DIRECTORY + '/learned-rules.json'));
      state.files.set(DIRECTORY + '/rule-decisions.json', JSON.stringify([
        { key: rules[0].key, state: 'rejected', at: state.now }
      ]));
    }
  } });
  await observeAndApprove(f);
  revoke = true;
  assert.equal((await f.run(4)).clickCount, 0);
});

test('three confirmed retained targets suspend a learned rule until the user reapproves', async () => {
  const f = learningFixture({ onClick() {} });
  const rule = await observeAndApprove(f);
  for (let i = 0; i < 3; i++) assert.equal((await f.run(4)).clickCount, 1);
  let saved = f.learningStore.readRules()[0];
  assert.equal(saved.failures, 3);
  assert.equal(f.models.ruleState(saved, f.learningStore.readDecisions()), 'suspended');
  assert.equal((await f.run(4)).clickCount, 0);
  f.learningStore.decide(rule.key, 'approved');
  assert.equal((await f.run(4)).clickCount, 1);
});

test('corrupt rule geometry or approval never authorizes clicks', async () => {
  for (const corrupt of ['geometry', 'approval']) {
    const f = learningFixture();
    await observeAndApprove(f);
    if (corrupt === 'geometry') {
      const rule = f.learningStore.readRules()[0]; rule.left = -1;
      f.learningStore.saveRules([rule]);
    } else {
      f.state.files.set(DIRECTORY + '/rule-decisions.json', '{broken');
    }
    assert.equal((await f.run(4)).clickCount, 0);
  }
});

test('countdown normalization only accepts explicit whole skip labels', () => {
  const f = learningFixture();
  for (const text of ['跳过', '跳过广告 5s', '5s跳过', 'Skip ad (3s)', 'SKIP 4',
    '跳过 | 3 s', '跳过（5秒）', '3秒｜跳过', 'Skip Ads (3 seconds)', '跳过广告，按钮'])
    assert.ok(f.models.skipLabel(text), text);
  for (const text of ['跳过片头', '跳过登录', '跳过支付', '点击跳过广告领取奖励', 'Skip tutorial', '', '广告'])
    assert.equal(f.models.skipLabel(text), '', text);
});

test('the observed Luckin label without a control id or ad marker is learned before any click', async () => {
  const f = learningFixture({ configure(state) {
    state.nodes[0].id = '';
    state.nodes[0].text = '跳过 | 3 s';
    state.nodes[0].bounds = { left: 1007, top: 129, right: 1272, bottom: 221 };
  } });
  const rule = await observeAndApprove(f);
  assert.equal(rule.marker, 'countdown');
  assert.equal(rule.targetId, '');
  f.state.nodes[0].text = '跳过 | 2 s';
  assert.equal((await f.run(4)).observedDismissedCount, 1);
});

test('description-only labels can be learned and are reread before clicking', async () => {
  const f = learningFixture({ configure(state) {
    state.nodes[0].text = '';
    state.nodes[0].description = '跳过（3秒），按钮';
  } });
  const rule = await observeAndApprove(f);
  assert.equal(rule.labelSource, 'description');
  assert.equal(rule.marker, 'countdown');
  assert.equal((await f.run(4)).observedDismissedCount, 1);
  assert.ok(f.state.apiCalls.includes('component.getDescription'));
});

test('a changing accessibility description cannot redirect an approved skip click', async () => {
  let changed = false;
  let armed = false;
  let reads = 0;
  const f = learningFixture({ configure(state) {
    state.nodes[0].text = ''; state.nodes[0].description = '跳过广告';
  }, onApi(name, state) {
    if (armed && name === 'component.getDescription' && ++reads === 1) {
      state.nodes[0].description = '立即购买'; changed = true;
    }
  } });
  await observeAndApprove(f);
  armed = true;
  assert.equal((await f.run(4)).clickCount, 0);
  assert.equal(changed, true);
});

test('the same no-id control in text and description is not counted as two targets', async () => {
  const f = learningFixture({ configure(state) {
    state.nodes[0].id = ''; state.nodes[0].description = state.nodes[0].text;
  } });
  await observeAndApprove(f);
  assert.equal((await f.run(4)).clickCount, 1);
});

test('a separate countdown is evidence only when adjacent to the skip control', async () => {
  for (const nearby of [true, false]) {
    const f = learningFixture({ configure(state) {
      state.nodes[0].text = '跳过';
      state.nodes.push({ bundle: READER, id: 'timer', text: '3秒', enabled: true, clickable: false,
        bounds: nearby ? { left: 1010, top: 90, right: 1080, bottom: 170 } :
          { left: 10, top: 90, right: 80, bottom: 170 } });
    } });
    await f.run(2);
    assert.equal(f.learningStore.readRules().length, nearby ? 1 : 0);
    assert.equal(f.state.clickCalls.length, 0);
    if (nearby) {
      const rule = f.learningStore.readRules()[0];
      assert.equal(rule.marker, 'countdown');
      f.learningStore.decide(rule.key, 'approved');
      assert.equal((await f.run(4)).observedDismissedCount, 1);
    }
  }
});

test('top-left and bottom-edge controls require their own learned approvals', async () => {
  for (const bounds of [{ left: 30, right: 170, top: 90, bottom: 170 },
    { left: 540, right: 800, top: 1800, bottom: 1890 }]) {
    const f = learningFixture({ configure(state) { state.nodes[0].bounds = bounds; } });
    await observeAndApprove(f);
    assert.equal((await f.run(4)).observedDismissedCount, 1);
  }
});

test('nested clickable ancestors resolve to the smallest unambiguous real container', async () => {
  const f = learningFixture({ configure(state) {
    const label = state.nodes[0]; label.clickable = false;
    const outer = { ...label, id: 'outer', text: '', clickable: true,
      bounds: { left: 1050, right: 1250, top: 70, bottom: 190 } };
    const inner = { ...label, id: 'inner', text: '', clickable: true, parent: outer };
    label.parent = inner; state.nodes.push(outer, inner);
  } });
  assert.equal((await observeAndApprove(f)).targetId, 'inner');
  assert.equal((await f.run(4)).clickCount, 1);
  assert.equal(f.state.clickCalls[0].id, 'inner');
});

test('delayed splash content at ten seconds can now be captured', async () => {
  let saved;
  let appeared = false;
  const f = learningFixture({ configure(state) { saved = state.nodes; state.nodes = []; },
    onTime(state) {
      if (!appeared && state.elapsed >= 10000) { appeared = true; state.nodes = saved; }
    } });
  await f.run(13);
  assert.equal(appeared, true);
  assert.equal(f.learningStore.readRules().length, 1);
  assert.equal(f.state.clickCalls.length, 0);
});

test('version 0.3 text rules without labelSource retain their key and approval', async () => {
  const f = learningFixture();
  const rule = await observeAndApprove(f);
  delete rule.labelSource;
  f.learningStore.saveRules([rule]);
  assert.equal(f.models.ruleKey(rule), rule.key);
  assert.equal((await f.run(4)).observedDismissedCount, 1);
});

test('existing plain-skip rules keep their independent ad evidence when a timer is present', async () => {
  const f = learningFixture({ configure(state) {
    state.nodes[0].text = '跳过 5s';
    state.nodes.push({ ...homeNode(READER), id: 'ad', text: '广告' });
  } });
  const rule = await observeAndApprove(f);
  assert.equal(rule.marker, '广告');
  delete rule.labelSource;
  f.learningStore.saveRules([rule]);
  assert.equal((await f.run(4)).observedDismissedCount, 1);
});

test('failed learning explains the missing evidence without storing unrelated page content', async () => {
  const f = learningFixture({ configure(state) {
    state.nodes[0].text = '跳过';
    state.nodes.push({ ...homeNode(READER), text: 'private unrelated page content' });
  } });
  await f.run(2);
  const diagnostics = f.learningStore.readDiagnostics();
  assert.equal(diagnostics.length, 1);
  assert.equal(diagnostics[0].bundle, READER);
  assert.match(diagnostics[0].reason, /缺少广告或倒计时/);
  assert.ok(!JSON.stringify(diagnostics).includes('private'));
  assert.equal(f.learningStore.readRules().length, 0);
});

test('natural splash expiry does not erase the successful learning diagnostic', async () => {
  const f = learningFixture({ onTime(state) {
    if (state.elapsed > 1500) state.nodes = [homeNode(READER)];
  } });
  await f.run(4);
  assert.equal(f.learningStore.readRules().length, 1);
  assert.match(f.learningStore.readDiagnostics()[0].reason, /确认启用/);
  assert.equal(f.state.clickCalls.length, 0);
});

test('common approved rules reach click without repeating language-specific tree searches', async () => {
  for (const bundle of [HUYA, YOUKU]) {
    const f = fixture({ bundle });
    assert.equal((await f.run(4)).observedDismissedCount, 1);
    const beforeClick = f.state.apiCalls.slice(0, f.state.apiCalls.indexOf('component.click'));
    assert.ok(beforeClick.filter(name => name === 'driver.findComponents').length <= 5);
    assert.equal(f.state.peakApiCalls, 1);
  }
});

test('combined queries retain mixed-case and multiline text/description recognition', async () => {
  for (const source of ['text', 'description']) {
    const f = learningFixture({ configure(state) {
      state.nodes[0].text = '';
      state.nodes[0][source] = '\n sKiP\nAd (3 s)\n';
    } });
    const rule = await observeAndApprove(f);
    assert.equal(rule.label, 'skipad');
    assert.equal(rule.labelSource, source);
    assert.equal((await f.run(4)).observedDismissedCount, 1);
  }
});

test('a second description-only target blocks an otherwise approved text target', async () => {
  const f = fixture({ configure(state) {
    state.nodes.push({ ...state.nodes[0], id: 'other', text: '', description: 'sKiP aD (3s)' });
  } });
  assert.equal((await f.run(4)).clickCount, 0);
});

test('ad labels that appear between polling scans are still found with the shorter active interval', async () => {
  let nodes;
  let appeared = false;
  const f = fixture({ configure(state) { nodes = state.nodes; state.nodes = []; },
    onTime(state) {
      if (!appeared && state.elapsed >= 310) { appeared = true; state.nodes = nodes; }
    } });
  assert.equal((await f.run(4)).observedDismissedCount, 1);
  assert.ok(f.state.clickCalls[0].at - 1000 < 600);
});

test('catalog imports commit only complete ordered batches and preserve settings and learned approvals', async () => {
  const { createParts } = require('../scripts/sync-apps.cjs');
  const f = learningFixture();
  f.learningStore.saveCatalog({ source: 'computer', updatedAt: 1, requestAt: 0, error: '', apps: [{ bundleName: HUYA, label: '虎牙直播' }, { bundleName: YOUKU, label: '优酷视频' }] });
  await observeAndApprove(f);
  const beforeSettings = f.state.files.get(DIRECTORY + '/settings.json');
  const beforeDecisions = f.state.files.get(DIRECTORY + '/rule-decisions.json');
  const raw = Array.from({ length: 100 }, (_, i) => ({ bundleName: 'com.example.app' + i, label: '应用' + i }));
  const parts = createParts(raw, 'batch-test').map(value => JSON.parse(Buffer.from(value, 'base64').toString('utf8')));
  assert.ok(parts.length > 1);
  f.learningStore.importCatalog(parts[0]);
  assert.equal(f.learningStore.readCatalog().apps.length, 2, 'A partial list does not replace the previous list');
  assert.throws(() => f.learningStore.importCatalog({ ...parts[1], batch: 'wrong-batch' }));
  for (const part of parts.slice(1)) f.learningStore.importCatalog(part);
  assert.equal(f.learningStore.readCatalog().apps.length, 100);
  assert.equal(f.learningStore.readCatalog().source, 'computer');
  assert.equal(f.state.files.get(DIRECTORY + '/settings.json'), beforeSettings);
  assert.equal(f.state.files.get(DIRECTORY + '/rule-decisions.json'), beforeDecisions);
});

for (const bundle of [HUYA, YOUKU]) {
  test(`former built-in app ${bundle} requires learning and explicit approval`, async () => {
    const f = baseFixture({ bundle });
    assert.equal(f.learningStore.readRules().length, 0);
    assert.equal((await f.run(2)).clickCount, 0);
    const rules = f.learningStore.readRules();
    assert.equal(rules.length, 1);
    assert.equal(f.models.ruleState(rules[0], f.learningStore.readDecisions()), 'pending');
    f.learningStore.decide(rules[0].key, 'approved');
    assert.equal((await f.run(4)).observedDismissedCount, 1);
  });
}

test('varied ad dismissal phrases normalize while delayed or unrelated actions are rejected', () => {
  const { skipLabel } = learningFixture().models;
  for (const label of ['略过广告', '跳过此广告', '關閉廣告', '关闭广告 | ３ s', 'Skip this advertisement', 'Close ad (3s)', 'Dismiss ads', '✕']) {
    assert.ok(skipLabel(label), label);
  }
  for (const label of ['5秒后跳过', '关闭账户', '关闭自动续费', '继续观看', '立即领取', '跳过广告并领奖', 'close account', '5秒后关闭广告']) {
    assert.equal(skipLabel(label), '', label);
  }
});

test('central and unusual-position ad buttons are learned and require their own approval', async () => {
  for (const bounds of [
    { left: 500, top: 1000, right: 820, bottom: 1080 },
    { left: 30, top: 1350, right: 300, bottom: 1470 },
    { left: 470, top: 700, right: 850, bottom: 850 }
  ]) {
    const f = learningFixture({ configure(state) {
      state.nodes[0].bounds = bounds;
      state.nodes[0].text = '关闭此广告';
    } });
    const rule = await observeAndApprove(f);
    assert.equal(rule.label, '关闭广告');
    assert.equal(rule.example, '关闭此广告');
    assert.equal((await f.run(4)).observedDismissedCount, 1);
  }
});

test('close text and cross icons require independent advertisement evidence', async () => {
  for (const label of ['关闭', 'Close', '×', 'X', '✕']) {
    for (const withAd of [false, true]) {
      const f = learningFixture({ configure(state) {
        Object.assign(state.nodes[0], { id: 'dialog_close', text: label,
          bounds: { left: 600, top: 1400, right: 670, bottom: 1470 } });
        if (withAd) state.nodes.push({ bundle: READER, text: '广告', enabled: true,
          clickable: false, bounds: { left: 30, top: 600, right: 100, bottom: 640 } });
      } });
      if (withAd) {
        await observeAndApprove(f);
        assert.equal((await f.run(4)).observedDismissedCount, 1, label);
      } else {
        await f.run(2);
        assert.equal(f.learningStore.readRules().length, 0, label);
        assert.equal(f.state.clickCalls.length, 0);
      }
    }
  }
});

test('image-only advertising close IDs are learned without coordinates and reread before execution', async () => {
  for (const id of ['splashCloseButton', 'ad_close_icon', 'advert_skip_button']) {
    const f = learningFixture({ configure(state) { Object.assign(state.nodes[0], { id, text: '' }); } });
    const rule = await observeAndApprove(f);
    assert.equal(rule.labelSource, 'id');
    assert.equal(rule.marker, 'control-id');
    assert.ok(rule.key.endsWith('|id'));
    assert.equal((await f.run(4)).observedDismissedCount, 1);
    assert.equal(f.state.peakApiCalls, 1);
  }
});

test('generic close IDs need an ad marker and never accept unrelated visible text', async () => {
  for (const variant of ['generic', 'no-marker', 'unrelated', 'substring']) {
    const f = learningFixture({ configure(state) {
      Object.assign(state.nodes[0], { id: variant === 'substring' ? 'download_close_button' : 'dialog_close',
        text: variant === 'unrelated' ? '关闭账户' : '' });
      if (variant === 'generic' || variant === 'unrelated') state.nodes.push({ bundle: READER, text: '广告',
        enabled: true, clickable: false, bounds: { left: 30, top: 600, right: 100, bottom: 640 } });
    } });
    if (variant === 'generic') {
      await observeAndApprove(f);
      assert.equal((await f.run(4)).observedDismissedCount, 1);
    } else {
      await f.run(2);
      assert.equal(f.learningStore.readRules().length, 0, variant);
    }
  }
});

test('an image ID changing after discovery cannot receive an approved click', async () => {
  let reads = 0;
  const f = learningFixture({ configure(state) { Object.assign(state.nodes[0], { id: 'ad_close_icon', text: '' }); },
    onApi(name, state) {
      if (state.getSettings().armed && name === 'component.getId' && ++reads >= 1) state.nodes[0].id = 'buy_button';
    } });
  await observeAndApprove(f);
  f.state.setSettings({ ...f.state.getSettings(), armed: true });
  assert.equal((await f.run(2)).clickCount, 0);
});

test('a malformed image rule or oversized geometry cannot inherit approval', async () => {
  const f = learningFixture({ configure(state) { Object.assign(state.nodes[0], { id: 'ad_close_icon', text: '' }); } });
  const rule = await observeAndApprove(f);
  for (const change of [{ targetId: 'close' }, { labelSource: 'text' }, { right: 1, bottom: 1 }, { marker: 'countdown' }]) {
    const altered = { ...rule, ...change };
    altered.key = f.models.ruleKey(altered);
    assert.equal(f.models.validRule(altered), false);
  }
});

test('an unrelated close on the destination page does not make a dismissed skip advertisement fail', async () => {
  const f = learningFixture({ onClick(node, state) {
    state.nodes = [homeNode(READER), { bundle: READER, text: '关闭', id: 'page_close',
      clickable: true, enabled: true, bounds: { ...BUTTON } }];
  } });
  await observeAndApprove(f);
  assert.equal((await f.run(4)).observedDismissedCount, 1);
});

test('full-width countdown digits provide evidence for a text-only skip', async () => {
  const f = learningFixture({ configure(state) { Object.assign(state.nodes[0], { id: '', text: '略过｜３秒' }); } });
  const rule = await observeAndApprove(f);
  assert.equal(rule.marker, 'countdown');
  assert.equal((await f.run(4)).observedDismissedCount, 1);
});


test('groups multiple templates of one app without merging their identities or approvals', () => {
  const f = fixture();
  const first = f.learningStore.readRules().find(rule => rule.bundle === HUYA);
  const second = { ...first, key: 'second-template', targetId: 'another-skip' };
  const other = f.learningStore.readRules().find(rule => rule.bundle === YOUKU);
  const groups = f.models.groupLearnedRules([first, other, second]);
  assert.equal(groups.length, 2);
  assert.equal(groups[0].bundle, HUYA);
  assert.deepEqual(Array.from(groups[0].rules, rule => rule.key), [first.key, second.key]);
  assert.equal(groups[1].rules.length, 1);
  assert.equal(f.models.ruleState(first, f.learningStore.readDecisions()), 'approved');
  assert.equal(f.models.ruleState(second, f.learningStore.readDecisions()), 'pending');
});

test('destination feed ads in a different region no longer suppress splash dismissal', async () => {
  const f = fixture({ apiVersion: 26, onClick(_, state) {
    state.nodes = [homeNode(HUYA), { ...adNodes(HUYA)[1], id: 'feed-ad', text: '广告',
      bounds: { left: 40, top: 900, right: 120, bottom: 950 } }];
  } });
  const status = await f.run(7);
  assert.equal(status.observedDismissedCount, 1);
  assert.equal(status.unverifiedCount, 0);
});

test('unrelated skip text in another region does not suppress dismissal', async () => {
  const f = fixture({ apiVersion: 26, onClick(_, state) {
    state.nodes = [homeNode(HUYA), { ...adNodes(HUYA)[0], id: 'tutorial-skip',
      bounds: { left: 200, top: 1400, right: 340, bottom: 1460 } }];
  } });
  assert.equal((await f.run(7)).observedDismissedCount, 1);
});

test('a remaining original ad marker stays inconclusive, including decorated ad labels', async () => {
  for (const text of ['广告', ' 广告 · 推广 ']) {
    const f = fixture({ apiVersion: 26, configure(state) { state.nodes[1].text = text; }, onClick(_, state) {
      state.nodes = state.nodes.filter(node => node.id === 'topAdText');
    } });
    const status = await f.run(7);
    assert.equal(status.observedDismissedCount, 0);
    assert.equal(status.unverifiedCount, 1);
    assert.equal(status.retainedCount, 0);
    const rule = f.learningStore.readRules().find(rule => rule.bundle === HUYA);
    assert.equal(rule.failures, 0);
    assert.equal(rule.unverified, 1);
  }
});

test('slow sequential UI reads still get two fresh disappearance observations', async () => {
  const f = fixture({ apiVersion: 26, onApi(name, state) {
    if (state.clickCalls.length && name !== 'driver.delayMs') state.advance(150);
  } });
  const status = await f.run(9);
  assert.equal(status.clickCount, 1);
  assert.equal(status.observedDismissedCount, 1);
  assert.equal(f.state.peakApiCalls, 1);
});

test('persistent window invalidation terminates as inconclusive without suspending a rule', async () => {
  const f = fixture({ apiVersion: 26, onApi(name, state) {
    if (state.clickCalls.length && name === 'driver.findWindow') {
      throw Object.assign(new Error('Window replaced'), { code: 17000004 });
    }
  } });
  const status = await f.run(8);
  assert.equal(status.clickCount, 1);
  assert.equal(status.observedDismissedCount, 0);
  assert.equal(status.unverifiedCount, 1);
  const rule = f.learningStore.readRules().find(rule => rule.bundle === HUYA);
  assert.equal(rule.failures, 0);
  assert.equal(rule.suspendedAt, 0);
});

test('empty focused window during an animation does not consume verification or allow another click', async () => {
  let empty = false;
  const f = fixture({ apiVersion: 26, onApi(name, state) {
    if (state.clickCalls.length && name === 'driver.findWindow' && !empty) {
      empty = true; state.foreground = '';
    } else if (empty && name === 'driver.findWindow') state.foreground = HUYA;
  } });
  const status = await f.run(7);
  assert.equal(status.clickCount, 1);
  assert.equal(status.observedDismissedCount, 1);
});

test('three unreadable-page results remain inconclusive and preserve explicit approval', async () => {
  const f = learningFixture({ apiVersion: 26, nullWholeTree: true });
  const rule = await observeAndApprove(f);
  for (let i = 0; i < 3; i++) {
    f.state.nodes = adNodes(READER);
    // Restore the learned fixture target, not a different app-specific template.
    Object.assign(f.state.nodes[0], { id: rule.targetId, text: rule.example || rule.label });
    const status = await f.run(7);
    assert.equal(status.clickCount, 1);
    assert.equal(status.unverifiedCount, 1);
  }
  const saved = f.learningStore.readRules()[0];
  assert.equal(saved.failures, 0);
  assert.equal(saved.unverified, 3);
  assert.equal(f.models.ruleState(saved, f.learningStore.readDecisions()), 'approved');
});

test('legacy timeout totals survive migration without contaminating a new failure streak', () => {
  const f = fixture({ apiVersion: 26 });
  const rules = f.learningStore.readRules();
  const rule = rules[0];
  rule.failures = 2; rule.consecutiveFailures = 2;
  delete rule.verificationVersion; delete rule.retained; delete rule.unverified;
  f.learningStore.saveRules(rules);
  const saved = f.learningStore.readRules()[0];
  assert.equal(saved.failures, 2);
  assert.equal(saved.retained, 0);
  assert.equal(saved.unverified, 0);
  assert.equal(saved.consecutiveFailures, 0);
  assert.equal(saved.key, rule.key);
  assert.equal(f.models.ruleState(saved, f.learningStore.readDecisions()), 'approved');
});


test('an original identified target moving elsewhere is not mistaken for dismissal', async () => {
  const f = fixture({ apiVersion: 26, onClick(node) {
    node.bounds = { left: 200, top: 1200, right: 340, bottom: 1260 };
  } });
  const status = await f.run(7);
  assert.equal(status.clickCount, 1);
  assert.equal(status.observedDismissedCount, 0);
  assert.equal(status.retainedCount, 1);
});

test('a label-only target moving elsewhere remains inconclusive', async () => {
  const f = learningFixture({ apiVersion: 26, configure(state) { state.nodes[0].id = ''; }, onClick(node) {
    node.bounds = { left: 200, top: 1200, right: 340, bottom: 1260 };
  } });
  await observeAndApprove(f);
  const status = await f.run(7);
  assert.equal(status.observedDismissedCount, 0);
  assert.equal(status.unverifiedCount, 1);
});


test('API 26 uses coherent snapshots and retains no private tree files', async () => {
  const f = fixture({ apiVersion: 26 });
  const status = await f.run();
  assert.equal(status.observedDismissedCount, 1);
  assert.ok(f.state.apiCalls.filter(name => name === 'driver.dumpLayout').length >= 2);
});

test('pre-26 devices retain the guarded serial verification fallback', async () => {
  const f = fixture({ apiVersion: 24 });
  assert.equal((await f.run()).observedDismissedCount, 1);
  assert.equal(f.state.apiCalls.includes('driver.dumpLayout'), false);
});

test('snapshot parser rejects missing, foreign, ambiguous and malformed application trees', () => {
  const f = fixture({ apiVersion: 26 });
  const rule = f.learningStore.readRules().find(rule => rule.bundle === YOUKU);
  const a = { type: 'root', bundleName: YOUKU, visible: 'true', focused: 'true', bounds: '[0,0][1320,2100]', hostWindowId: '1' };
  const root = { attributes: a, children: [{ attributes: { visible: 'true', bounds: '[0,0][1320,2100]', text: '首页', hostWindowId: '1' } }] };
  assert.equal(f.learningWorker.snapshotTargetState(JSON.stringify(root), rule), 'absent');
  for (const input of ['{broken', '{}', JSON.stringify({ ...root, children: [] }),
    JSON.stringify({ ...root, attributes: { ...a, bundleName: HOME } }),
    JSON.stringify({ ...root, attributes: { ...a, focused: 'false', hostWindowId: '' } }),
    JSON.stringify([root, root]), JSON.stringify({ ...root, children: 'invalid' })]) {
    assert.equal(f.learningWorker.snapshotTargetState(input, rule), 'unknown');
  }
});

test('snapshot parser ignores hidden descendants while still detecting a visible target', () => {
  const f = fixture({ apiVersion: 26 });
  const rule = f.learningStore.readRules().find(rule => rule.bundle === YOUKU);
  const target = { attributes: { visible: 'true', bounds: '[1100,90][1220,170]', id: rule.targetId, text: rule.label } };
  const home = { attributes: { visible: 'true', bounds: '[0,0][1320,2100]', text: '首页' } };
  const root = { attributes: { type: 'root', bundleName: YOUKU, visible: 'true', focused: 'true', bounds: '[0,0][1320,2100]' }, children: [home, target] };
  assert.equal(f.learningWorker.snapshotTargetState(JSON.stringify(root), rule), 'present');
  root.children = [home, { attributes: { visible: 'false', bounds: '[0,0][1320,2100]' }, children: [target] }];
  assert.equal(f.learningWorker.snapshotTargetState(JSON.stringify(root), rule), 'absent');
});


test('snapshot geometry uses the full original window rather than status-bar-clipped content bounds', async () => {
  const f = learningFixture({ apiVersion: 26, configure(state) { state.nodes[0].id = ''; } });
  const rule = await observeAndApprove(f);
  const root = { attributes: { type: 'root', bundleName: READER, visible: 'true', focused: 'true',
    bounds: '[0,117][1320,2100]', origBounds: '[0,0][1320,2100]' }, children: [
    { attributes: { visible: 'true', bounds: '[1100,90][1220,170]', text: rule.label } }
  ] };
  assert.equal(f.learningWorker.snapshotTargetState(JSON.stringify(root), rule), 'present');
});


// API 26 discovery must remain fast without inheriting ordinary finder idle waits.
for (const bundle of [HUYA, YOUKU]) {
  test(`double-snapshot path clicks approved ${bundle} without idle-waiting component queries`, async () => {
    const f = fixture({ apiVersion: 26, bundle, onApi(name, state) {
      if (name === 'driver.findComponents') state.advance(1000);
      else if (name !== 'driver.delayMs') state.advance(15);
    } });
    const status = await f.run(5);
    assert.equal(status.clickCount, 1);
    assert.equal(status.observedDismissedCount, 1);
    const calls = f.state.apiCalls.slice(0, f.state.apiCalls.indexOf('driver.click'));
    assert.equal(calls.filter(name => name === 'driver.dumpLayout').length, 2);
    assert.equal(calls.includes('driver.findComponents'), false);
    assert.ok(f.state.clickCalls[0].at - 1000 < 500);
    assert.equal(f.state.peakApiCalls, 1);
  });
}

test('fast discovery learns first and requires approval, including anonymous clickable parents', async () => {
  const f = learningFixture({ apiVersion: 26, configure(state) {
    const parent = state.nodes[0]; parent.id = ''; parent.text = '';
    state.nodes.push({ ...parent, id: 'inner_label', text: '跳过广告', clickable: false, parent });
  } });
  await observeAndApprove(f);
  assert.equal((await f.run(4)).clickCount, 1);
  assert.equal(f.state.clickCalls[0].id, '');
});

for (const mutation of ['gone', 'disabled', 'label', 'id', 'moved', 'duplicate', 'foreground', 'settings', 'approval']) {
  test(`second snapshot/preflight rejects ${mutation} after approved discovery`, async () => {
    let dumps = 0;
    let changed = false;
    const f = fixture({ apiVersion: 26, onApi(name, state) {
      if (name !== 'driver.dumpLayout' || ++dumps !== 2) return;
      changed = true;
      if (mutation === 'gone') state.nodes = [homeNode(HUYA)];
      if (mutation === 'disabled') state.nodes[0].enabled = false;
      if (mutation === 'label') state.nodes[0].text = '立即购买';
      if (mutation === 'id') state.nodes[0].id = 'buy_button';
      if (mutation === 'moved') { state.nodes[0].bounds.left += 60; state.nodes[0].bounds.right += 60; }
      if (mutation === 'duplicate') state.nodes.push({ ...state.nodes[0], id: 'other' });
      if (mutation === 'evidence') state.nodes = state.nodes.slice(0, 1);
      if (mutation === 'foreground') state.foreground = HOME;
      if (mutation === 'settings') state.setSettings({ ...state.getSettings(), enabled: false });
      if (mutation === 'approval') state.files.set(DIRECTORY + '/rule-decisions.json', '[]');
    } });
    assert.equal((await f.run(4)).clickCount, 0);
    assert.equal(changed, true);
    assert.equal(f.state.apiCalls.includes('driver.click'), false);
  });
}

test('fast path checks foreground after the fresh tree and rejects expired snapshots', async () => {
  for (const variant of ['foreground', 'age']) {
    let dumps = 0;
    const f = fixture({ apiVersion: 26, onApi(name, state) {
      if (name === 'driver.dumpLayout') dumps++;
      if (dumps >= 2 && name === 'driver.findWindow') {
        if (variant === 'foreground') state.foreground = HOME;
        else state.advance(350);
      }
    } });
    assert.equal((await f.run(4)).clickCount, 0);
  }
});

test('fast input failures consume the attempt without a second input or legacy fallback', async () => {
  const f = fixture({ apiVersion: 26, onApi(name) {
    if (name === 'driver.click') throw Object.assign(new Error('Input lost during transition'), { code: 17000004 });
  } });
  const status = await f.run(7);
  assert.equal(status.attemptCount, 1);
  assert.equal(status.clickCount, 0);
  assert.equal(f.state.apiCalls.filter(name => name === 'driver.click').length, 1);
  assert.equal(f.state.apiCalls.includes('component.click'), false);
});

test('current target bounds drive fast input; a saved template point is never reused', async () => {
  const f = fixture({ apiVersion: 26, configure(state) {
    state.nodes[0].bounds.left += 4; state.nodes[0].bounds.right += 4;
  } });
  assert.equal((await f.run(4)).clickCount, 1);
  assert.equal(f.state.clickCalls[0].x, (BUTTON.left + BUTTON.right) / 2 + 4);
});

test('unreadable discovery, hidden ancestors and unrelated overlapping hit targets do not click', async () => {
  for (const variant of ['unreadable', 'hidden', 'disabledParent', 'overlap', 'foreign', 'duplicateRoot', 'otherFocusedRoot', 'display']) {
    const f = fixture({ apiVersion: 26, nullDiscoveryTree: variant === 'unreadable', configure(state) {
      if (variant === 'hidden' || variant === 'disabledParent') {
        const parent = { bundle: HUYA, id: 'hidden', enabled: variant !== 'disabledParent', clickable: false, visible: variant !== 'hidden', bounds: { ...WINDOW } };
        state.nodes[0].parent = parent; state.nodes.push(parent);
      }
      if (variant === 'overlap') state.nodes.push({ ...state.nodes[0], id: 'purchase', text: '立即购买' });
    }, onLayout(layout) {
      if (variant === 'foreign') layout.attributes.bundleName = HOME;
      if (variant === 'display') layout.attributes.displayId = '999';
      if (variant === 'duplicateRoot' || variant === 'otherFocusedRoot') {
        const root = { attributes: { ...layout.attributes }, children: layout.children };
        const other = variant === 'duplicateRoot' ? root : { attributes: { ...root.attributes, bundleName: HOME }, children: [] };
        layout.attributes = {}; layout.children = [root, other];
      }
    } });
    assert.equal((await f.run(4)).clickCount, 0, variant);
  }
});

test('countdown text changes between fresh frames preserve the same approved action', async () => {
  let armed = false;
  const f = learningFixture({ apiVersion: 26, onApi(name, state) {
    if (armed && name === 'driver.dumpLayout' && !state.clickCalls.length) state.nodes[0].text = '跳过广告 4s';
  } });
  await observeAndApprove(f); armed = true;
  assert.equal((await f.run(4)).clickCount, 1);
});

function capturedSplash(name) {
  return JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', `${name}-splash-065.json`), 'utf8'));
}
function allTreeNodes(tree) {
  const nodes = [];
  function visit(n) { nodes.push(n); for (const c of n.children || []) visit(c); }
  for (const root of Array.isArray(tree) ? tree : [tree]) visit(root);
  return nodes;
}
for (const [name, bundle, key] of [
  ['qq', 'com.tencent.hm.qqmusic', 'com.tencent.hm.qqmusic||跳过|广告|9|0|10|1|3'],
  ['luckin', 'com.lucky.luckincoffee', 'com.lucky.luckincoffee||跳过|countdown|8|1|10|1|3']
]) {
  test(`real ${name} splash: clickable background behind button does not suppress the saved rule`, () => {
    const f = fixture(); const report = new f.learningWorker.ScanReport();
    const match = f.learningWorker.discoverSnapshot(JSON.stringify(capturedSplash(name)), bundle, report);
    assert.ok(match, report.reason); assert.equal(match.rule.key, key);
  });
  test(`real ${name} splash: raising the background above the target still blocks input`, () => {
    const f = fixture(); const tree = capturedSplash(name);
    const background = allTreeNodes(tree).find(n => n.attributes.type === 'Image' && n.attributes.clickable === 'true');
    background.attributes.zIndex = '999';
    const report = new f.learningWorker.ScanReport();
    assert.equal(f.learningWorker.discoverSnapshot(JSON.stringify(tree), bundle, report), undefined);
    assert.match(report.reason, /重叠/);
  });
}
test('occlusion follows the divergent ancestor z-order, not the leaf label z-order', () => {
  const f = fixture(); const tree = capturedSplash('qq'); const nodes = allTreeNodes(tree);
  nodes.find(n => n.attributes.id === 'skipButton').attributes.zIndex = '-1';
  nodes.find(n => n.attributes.text === '跳过').attributes.zIndex = '999';
  const report = new f.learningWorker.ScanReport();
  assert.equal(f.learningWorker.discoverSnapshot(JSON.stringify(tree), 'com.tencent.hm.qqmusic', report), undefined);
  assert.match(report.reason, /重叠/);
});
test('same-z-order sibling paint order and missing z metadata remain conservative', () => {
  for (const variant of ['reverse', 'unknown']) {
    const f = fixture(); const tree = capturedSplash('luckin'); const nodes = allTreeNodes(tree);
    const bg = nodes.find(n => n.attributes.type === 'Image' && n.attributes.clickable === 'true');
    if (variant === 'reverse') nodes.find(n => n.children.includes(bg)).children.reverse();
    else delete bg.attributes.zIndex;
    const report = new f.learningWorker.ScanReport();
    assert.equal(f.learningWorker.discoverSnapshot(JSON.stringify(tree), 'com.lucky.luckincoffee', report), undefined);
    assert.match(report.reason, /重叠/);
  }
});
test('multiple saved templates do not conflict when only one current target matches', async () => {
  const f = fixture({ apiVersion: 26 });
  const existing = f.learningStore.readRules().find(rule => rule.bundle === HUYA);
  const rules = JSON.parse(f.state.files.get(DIRECTORY + '/learned-rules.json'));
  const other = { ...existing, targetId: 'alternateFoldSkip' };
  other.key = f.models.ruleKey(other); rules.unshift(other);
  f.state.files.set(DIRECTORY + '/learned-rules.json', JSON.stringify(rules));
  const decisions = JSON.parse(f.state.files.get(DIRECTORY + '/rule-decisions.json'));
  decisions.push({ key: other.key, state: 'approved', at: f.state.now, templateAt: other.firstSeen });
  f.state.files.set(DIRECTORY + '/rule-decisions.json', JSON.stringify(decisions));
  const status = await f.run(4);
  assert.equal(status.clickCount, 1);
  assert.equal(f.state.clickCalls[0].id, existing.targetId);
});
test('failed second-frame recognition and snapshot expiry leave explicit chain reasons', async () => {
  for (const variant of ['gone', 'slow']) {
    let reads = 0;
    const f = fixture({ apiVersion: 26, onApi(name, state) {
      if (name === 'driver.dumpLayout' && ++reads === 2) {
        if (variant === 'gone') state.nodes = [homeNode(HUYA)];
        else state.advance(850);
      }
    } });
    const status = await f.run(4);
    assert.ok(status.history.some(item => item.result === 'decision' &&
      (variant === 'gone' ? item.message.includes('点击复核未通过') : item.message.includes('界面读取超过 700 ms'))));
  }
});


test('stale refresh requests cannot issue shell commands or block discovery', async () => {
  const f = fixture({ configure(state) {
    state.setSettings({ ...state.getSettings(), catalogRequestAt: 100, remindersEnabled: false, learningEnabled: true, stopRequested: false });
    state.files.set(DIRECTORY + '/app-catalog.json', JSON.stringify({
      source: 'computer', apps: [{ bundleName: HUYA, label: '旧名称' }], updatedAt: 1, requestAt: 0, error: ''
    }));
  } });
  const settings = f.state.getSettings();
  const decisions = JSON.stringify(f.learningStore.readDecisions());
  await f.run(1);
  assert.equal(f.state.catalogReads || 0, 0);
  assert.equal(f.learningStore.readCatalog().source, 'computer');
  assert.equal(f.learningStore.readSeenApps()[0].bundleName, HUYA);
  assert.deepEqual(f.state.getSettings(), { ...settings, themeMode: settings.themeMode || 'system', autoAdFree: settings.autoAdFree !== false, reminderDismissSeconds: settings.reminderDismissSeconds ?? 5, adFreeMinDays: settings.adFreeMinDays ?? 1, adFreeCleanChecks: settings.adFreeCleanChecks ?? 3, adFreeRecheckDays: settings.adFreeRecheckDays ?? 7 });
  assert.equal(JSON.stringify(f.learningStore.readDecisions()), decisions);
});

for (const apiVersion of [24, 26]) {
  test(`API ${apiVersion}: unseen app is recorded and learns without a catalog, selection or approval`, async () => {
    const f = learningFixture({ apiVersion, configure(state) { state.setSettings({ enabled: true, packages: [], learningEnabled: true }); } });
    await f.run(2);
    assert.equal(f.state.catalogReads || 0, 0);
    assert.equal(f.learningStore.readSeenApps().length, 1);
    assert.equal(f.learningStore.readSeenApps()[0].bundleName, READER);
    assert.equal(f.learningStore.readRules().length, 1);
    assert.equal(f.models.ruleState(f.learningStore.readRules()[0], f.learningStore.readDecisions()), 'pending');
    assert.equal(f.state.clickCalls.length, 0);
    assert.equal(f.state.getSettings().packages.length, 0);
  });
}
test('opening an app without an advertisement records the app but invents no rule', async () => {
  const f = learningFixture({ apiVersion: 26, configure(state) {
    state.setSettings({ enabled: true, packages: [] }); state.nodes = [homeNode(READER)];
  } });
  await f.run(1);
  assert.equal(f.learningStore.readSeenApps().length, 1);
  assert.equal(f.learningStore.readRules().length, 0);
  assert.equal(f.state.clickCalls.length, 0);
});
test('an explicitly paused app is neither rediscovered nor clicked even with old approval', async () => {
  const f = fixture({ configure(state) { state.setSettings({ ...state.getSettings(), ignoredPackages: [HUYA] }); } });
  await f.run();
  assert.equal(f.learningStore.readSeenApps().length, 0);
  assert.equal(f.state.clickCalls.length, 0);
});
test('system surfaces and invalid bundle IDs are never added to discovered apps', async () => {
  for (const bundle of [HOME, 'com.huawei.hmos.settings', 'com.huawei.hmos.systemui', 'ohos.system', 'bad;command', 'com.tonghongxiang.quietstart']) {
    const f = fixture({ bundle, configure(state) { state.setSettings({ enabled: true, packages: [] }); } });
    await f.run(1); assert.equal(f.learningStore.readSeenApps().length, 0); assert.equal(f.state.clickCalls.length, 0);
  }
});
test('discovered names, first-seen time and rule decisions survive another session', async () => {
  const f = learningFixture(); await f.run(1);
  const first = f.learningStore.readSeenApps()[0].firstSeen;
  f.learningStore.renameSeenApp(READER, '我的阅读器');
  const decisions = JSON.stringify(f.learningStore.readDecisions());
  f.state.advance(1000); await f.run(1);
  const seen = f.learningStore.readSeenApps();
  assert.equal(seen.length, 1); assert.equal(seen[0].firstSeen, first); assert.equal(seen[0].label, '我的阅读器');
  assert.equal(JSON.stringify(f.learningStore.readDecisions()), decisions);
});
test('pausing automatic clicks still permits observation but never input', async () => {
  const f = learningFixture({ configure(state) { state.setSettings({ ...state.getSettings(), enabled: false, packages: [] }); } });
  await f.run(1); assert.equal(f.learningStore.readRules().length, 1); assert.equal(f.state.clickCalls.length, 0);
});

test('automatic display names update existing discovered apps without overwriting user aliases or rule identities', async()=>{
 const f=learningFixture();await f.run(1);
 const rules=JSON.stringify(f.learningStore.readRules());
 f.learningStore.saveAppName(READER,'系统中文名');
 assert.equal(f.learningStore.managedApps([])[0].label,'系统中文名');
 f.learningStore.renameSeenApp(READER,'我的备注');
 f.learningStore.saveAppName(READER,'更新后的系统名');
 assert.equal(f.learningStore.managedApps([])[0].label,'我的备注');
 assert.equal(JSON.stringify(f.learningStore.readRules()),rules);
});

test('paused catalog-only apps remain listed with their display name and can be restored without duplication', () => {
  const f = learningFixture();
  f.learningStore.saveCatalog({ apps: [{ bundleName: READER, label: '阅读器' }], updatedAt: 1, requestAt: 0, source: 'device' });
  const rulesBefore = JSON.stringify(f.learningStore.readRules());
  const paused = f.learningStore.managedApps([], [READER]);
  assert.equal(paused.length, 1); assert.equal(paused[0].label, '阅读器');
  f.learningStore.recordSeenApp(READER);
  assert.equal(f.learningStore.managedApps([READER], [READER]).length, 1);
  assert.equal(JSON.stringify(f.learningStore.readRules()), rulesBefore);
  assert.equal(f.state.clickCalls.length, 0);
});

function iqiyiSplash() {
  return JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/iqiyi-splash-086.json'), 'utf8'));
}
test('real image-only iQiyi splash uses its own guide marker and preserves the approved rule identity', () => {
  const f = fixture(); const report = new f.learningWorker.ScanReport();
  const match = f.learningWorker.discoverSnapshot(JSON.stringify(iqiyiSplash()), 'com.qiyi.video.hmy', report);
  assert.ok(match, report.reason);
  assert.equal(match.rule.key, 'com.qiyi.video.hmy||关闭|广告|8|0|10|1|3');
  assert.equal(match.adMarker.source, 'splash-id');
  assert.equal(f.models.validRule(match.rule), true);
});
test('splash evidence rejects generic guides, hidden markers and markers outside the target overlay', () => {
  const f = fixture();
  for (const variant of ['generic', 'hidden', 'foreign', 'disabled']) {
    const tree = iqiyiSplash(); const nodes = allTreeNodes(tree);
    const marker = nodes.find(n => n.attributes.id === 'SplashAdGuide_12345');
    if (variant === 'generic') marker.attributes.id = 'TutorialGuide_12345';
    if (variant === 'hidden') marker.attributes.visible = 'false';
    if (variant === 'disabled') nodes.find(n => n.attributes.text === '关闭').attributes.enabled = 'false';
    if (variant === 'foreign') {
      const parent = nodes.find(n => n.children.includes(marker));
      parent.children = parent.children.filter(n => n !== marker);
      nodes.find(n => n.attributes.type === 'root').children.unshift(marker);
    }
    const report = new f.learningWorker.ScanReport();
    assert.equal(f.learningWorker.discoverSnapshot(JSON.stringify(tree), 'com.qiyi.video.hmy', report), undefined, variant);
  }
});
test('splash disappearance tracks the live guide rather than an unrelated homepage advertisement', () => {
  const f = fixture(); const tree = iqiyiSplash();
  const root = allTreeNodes(tree).find(n => n.attributes.type === 'root');
  const homepageAd = { attributes: { text: '广告', type: 'Text', bounds: '[1188,387][1254,426]', visible: 'true', enabled: 'true', clickable: 'false', hostWindowId: root.attributes.hostWindowId }, children: [] };
  root.children.unshift(homepageAd);
  const report = new f.learningWorker.ScanReport();
  const match = f.learningWorker.discoverSnapshot(JSON.stringify(tree), 'com.qiyi.video.hmy', report);
  assert.ok(match, report.reason); assert.equal(match.adMarker.source, 'splash-id');
  const nodes = allTreeNodes(tree); const close = nodes.find(n => n.attributes.text === '关闭');
  nodes.find(n => n.children.includes(close)).children = [];
  assert.equal(f.learningWorker.snapshotTargetState(JSON.stringify(tree), match.rule, match.adMarker), 'blocked');
  const guide = nodes.find(n => n.attributes.id === 'SplashAdGuide_12345');
  guide.attributes.id = 'SplashAdGuide_67890';
  assert.equal(f.learningWorker.snapshotTargetState(JSON.stringify(tree), match.rule, match.adMarker), 'blocked');
  guide.attributes.visible = 'false';
  assert.equal(f.learningWorker.snapshotTargetState(JSON.stringify(tree), match.rule, match.adMarker), 'absent');
});

function ximalayaSplash() {
  return JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/ximalaya-splash-087.json'), 'utf8'));
}
const XIMALAYA = 'com.ximalaya.ting.xmharmony';
test('real Ximalaya non-focusable splash is discoverable for the verified foreground app', () => {
  const f = fixture(); const report = new f.learningWorker.ScanReport();
  const tree = ximalayaSplash();
  const match = f.learningWorker.discoverSnapshot(JSON.stringify(tree), XIMALAYA, report);
  assert.ok(match, report.reason);
  assert.equal(match.rule.label, '跳过广告'); assert.equal(match.rule.marker, 'label');
  assert.deepEqual(JSON.parse(JSON.stringify(match.bounds)), { left: 1044, top: 144, right: 1272, bottom: 231 });
  assert.equal(f.learningWorker.snapshotTargetState(JSON.stringify(tree), match.rule, match.adMarker), 'present');
  allTreeNodes(tree).find(n => n.attributes.text === '跳过广告').attributes.visible = 'false';
  assert.equal(f.learningWorker.snapshotTargetState(JSON.stringify(tree), match.rule, match.adMarker), 'absent');
});
test('non-focusable splash fallback rejects foreign, ambiguous, hidden and unidentified windows', () => {
  const f = fixture(); const report = new f.learningWorker.ScanReport();
  const good = f.learningWorker.discoverSnapshot(JSON.stringify(ximalayaSplash()), XIMALAYA, report);
  for (const variant of ['foreign', 'duplicate', 'other-visible', 'foreign-focused', 'hidden', 'unknown-focus', 'no-window-id', 'other-display']) {
    const tree = ximalayaSplash();
    const root = allTreeNodes(tree).find(n => n.attributes.type === 'root');
    let input = tree;
    if (variant === 'foreign') root.attributes.bundleName = HOME;
    if (variant === 'hidden') root.attributes.visible = 'false';
    if (variant === 'unknown-focus') delete root.attributes.focused;
    if (variant === 'no-window-id') delete root.attributes.hostWindowId;
    if (variant === 'other-display') root.attributes.displayId = '1';
    if (['duplicate', 'other-visible', 'foreign-focused'].includes(variant)) {
      const other = JSON.parse(JSON.stringify(root));
      if (variant !== 'duplicate') other.attributes.bundleName = HOME;
      if (variant === 'foreign-focused') other.attributes.focused = 'true';
      input = [tree, other];
    }
    assert.equal(f.learningWorker.discoverSnapshot(JSON.stringify(input), XIMALAYA, report), undefined, variant);
    assert.equal(f.learningWorker.snapshotTargetState(JSON.stringify(input), good.rule, good.adMarker), 'unknown', variant);
  }
});
test('non-focusable foreground splash follows approval, double snapshots and dismissal verification', async () => {
  const f = learningFixture({ apiVersion: 26, onLayout(layout) {
    allTreeNodes(layout).find(n => n.attributes.type === 'root').attributes.focused = 'false';
  } });
  await observeAndApprove(f);
  const status = await f.run(4);
  assert.equal(status.clickCount, 1); assert.equal(status.observedDismissedCount, 1);
});

test('active foreground window supports non-focusable splash discovery and verification', async () => {
  const f = learningFixture({ apiVersion: 26,
    windowBundle: (filter, state) => filter.focused ? '' : state.foreground,
    onLayout(layout) { allTreeNodes(layout).find(n => n.attributes.type === 'root').attributes.focused = 'false'; }
  });
  await observeAndApprove(f);
  const status = await f.run(4);
  assert.equal(status.clickCount, 1); assert.equal(status.observedDismissedCount, 1);
  assert.ok(f.state.windowFilters.some(filter => filter.active === true));
});
test('active-window fallback cannot override a focused foreign app or invent missing foreground', async () => {
  for (const variant of ['foreign-focused', 'missing-both', 'foreign-active']) {
    const f = fixture({ apiVersion: 26, windowBundle(filter) {
      if (variant === 'foreign-focused') return filter.focused ? HOME : HUYA;
      if (variant === 'missing-both') return '';
      return filter.focused ? '' : HOME;
    }, onLayout(layout) { allTreeNodes(layout).find(n => n.attributes.type === 'root').attributes.focused = 'false'; } });
    assert.equal((await f.run(2)).clickCount, 0, variant);
    if (variant === 'foreign-focused') assert.equal(f.state.windowFilters.some(filter => filter.active), false);
  }
});
test('active window changing after the second snapshot cancels the pending input', async () => {
  let dumps = 0;
  const f = fixture({ apiVersion: 26,
    windowBundle: (filter, state) => filter.focused ? '' : (dumps >= 2 ? HOME : state.foreground),
    onLayout(layout) { dumps++; allTreeNodes(layout).find(n => n.attributes.type === 'root').attributes.focused = 'false'; }
  });
  assert.equal((await f.run(2)).clickCount, 0);
});

test('sole visible app fallback identifies the real Ximalaya window and rejects ambiguous ownership', () => {
  const f = fixture();
  assert.equal(f.learningWorker.soleVisibleAppBundle(JSON.stringify(ximalayaSplash())), XIMALAYA);
  for (const variant of ['foreign-system', 'duplicate', 'no-id', 'unknown-focus', 'display', 'hidden', 'small-visible']) {
    const tree = ximalayaSplash();
    const root = allTreeNodes(tree).find(n => n.attributes.type === 'root');
    if (variant === 'foreign-system') root.attributes.bundleName = HOME;
    if (variant === 'no-id') delete root.attributes.hostWindowId;
    if (variant === 'unknown-focus') delete root.attributes.focused;
    if (variant === 'display') root.attributes.displayId = '1';
    if (variant === 'hidden') root.attributes.visible = 'false';
    if (variant === 'small-visible') root.attributes.bounds = '[0,117][300,400]';
    assert.equal(f.learningWorker.soleVisibleAppBundle(JSON.stringify(variant === 'duplicate' ? [tree, tree] : tree)), '', variant);
  }
  for (const text of ['', '{}', '{broken', 'null']) assert.equal(f.learningWorker.soleVisibleAppBundle(text), '');
});
test('no focused or active window: live display ownership still requires approval and a fresh bundle lookup', async () => {
  const f = learningFixture({ apiVersion: 26,
    windowBundle: (filter, state) => filter.bundleName === state.foreground ? state.foreground : '',
    onLayout(layout) { allTreeNodes(layout).find(n => n.attributes.type === 'root').attributes.focused = 'false'; }
  });
  await observeAndApprove(f);
  assert.equal(f.state.clickCalls.length, 0);
  const status = await f.run(4);
  assert.equal(status.clickCount, 1); assert.equal(status.observedDismissedCount, 1);
  assert.ok(f.state.windowFilters.some(filter => filter.bundleName === READER));
  assert.equal([...f.state.files.keys()].some(name => name.endsWith('-snapshot.json')), false);
});
test('visible-window ownership changing during final foreground check cancels input', async () => {
  let discoveryReads = 0;
  const f = fixture({ apiVersion: 26,
    windowBundle: (filter, state) => filter.bundleName === state.foreground ? state.foreground : '',
    onLayout(layout, state, savePath) {
      allTreeNodes(layout).find(n => n.attributes.type === 'root').attributes.focused = 'false';
      if (savePath.endsWith('/discovery-snapshot.json')) discoveryReads++;
      if (savePath.endsWith('/foreground-snapshot.json') && discoveryReads >= 2) {
        allTreeNodes(layout).find(n => n.attributes.type === 'root').attributes.bundleName = HOME;
      }
    }
  });
  assert.equal((await f.run(3)).clickCount, 0);
});

test('reset deletes all templates and approvals for just one application, preserving preferences and names', async () => {
  const f = fixture();
  const before = f.learningStore.readRules();
  const other = JSON.stringify(before.filter(r => r.bundle === YOUKU));
  f.learningStore.recordSeenApp(HUYA); f.learningStore.renameSeenApp(HUYA, '我的虎牙');
  const settings = JSON.stringify(f.state.getSettings());
  const alternative = { ...before.find(r => r.bundle === HUYA), targetId: 'secondTemplate' };
  alternative.key = f.models.ruleKey(alternative);
  f.learningStore.saveRules([...before, alternative]); f.learningStore.decide(alternative.key, 'approved');
  f.learningStore.resetAppRules(HUYA);
  assert.equal(f.learningStore.readRules().some(r => r.bundle === HUYA), false);
  assert.equal(f.learningStore.readDecisions().some(d => d.key.startsWith(HUYA + '|')), false);
  assert.equal(JSON.stringify(f.learningStore.readRules()), other);
  assert.equal(JSON.stringify(f.state.getSettings()), settings);
  assert.equal(f.learningStore.managedApps([HUYA])[0].label, '我的虎牙');
});
test('in-flight old worker saves cannot resurrect reset rules or approvals', () => {
  const f = fixture();
  const oldRules = f.learningStore.readRules();
  const oldDecisions = f.learningStore.readDecisions();
  f.learningStore.resetAppRules(HUYA);
  f.learningStore.saveRules(oldRules);
  f.state.files.set(DIRECTORY + '/rule-decisions.json', JSON.stringify(oldDecisions));
  assert.equal(f.learningStore.readRules().some(r => r.bundle === HUYA), false);
  assert.equal(f.learningStore.readDecisions().some(d => d.key.startsWith(HUYA + '|')), false);
});
test('relearning the same target starts fresh and requires new approval even in the same millisecond', async () => {
  const f = learningFixture({ apiVersion: 26 });
  const old = await observeAndApprove(f);
  f.learningStore.resetAppRules(READER);
  const fresh = f.learningStore.observe({ ...old, firstSeen: 0, observations: 0, attempts: 0, successes: 0 });
  assert.ok(fresh.firstSeen > old.firstSeen);
  assert.equal(f.models.ruleState(fresh, f.learningStore.readDecisions()), 'pending');
  f.learningStore.outcome(fresh.key, 'success', old.firstSeen);
  assert.equal(f.learningStore.readRules()[0].successes, 0);
  assert.equal((await f.run(2)).clickCount, 0);
});
test('reset between discovery and final recheck cancels an approved click', async () => {
  let f, reset = false;
  f = fixture({ apiVersion: 26, onLayout(layout, state, filename) {
    if (!reset && state.apiCalls.filter(name => name === 'driver.dumpLayout').length === 2) {
      reset = true; f.learningStore.resetAppRules(HUYA);
    }
  } });
  assert.equal((await f.run(2)).clickCount, 0);
});
test('reset during dismissal verification cancels the old outcome instead of crediting a new rule', async () => {
  let f;
  f = fixture({ apiVersion: 26, onClick() { f.learningStore.resetAppRules(HUYA); } });
  const status = await f.run(3);
  assert.equal(status.clickCount, 1); assert.equal(status.observedDismissedCount, 0);
  assert.ok(status.history.some(r => r.result === 'cancelled'));
  assert.equal(f.learningStore.readRules().some(r => r.bundle === HUYA), false);
});
test('readable no-match records report inspected controls and timing without claiming there was no advertisement', async () => {
  const f = learningFixture({ apiVersion: 26, configure(state) { state.nodes = [homeNode(READER)]; } });
  const status = await f.run(1);
  const record = status.history.find(r => r.result === 'decision');
  assert.match(record.message, /已读取 1 个可见控件/);
  assert.match(record.message, /不能据此判定没有广告/);
  assert.match(record.message, /本轮检查 \d+ ms/);
});
test('matched pending and approved records show the target and measured duration', async () => {
  const f = learningFixture({ apiVersion: 26 });
  const pending = await f.run(1);
  assert.ok(pending.history.some(r => /等待你确认启用；识别 \d+ ms，目标/.test(r.message)));
  f.learningStore.decide(f.learningStore.readRules()[0].key, 'approved');
  const approved = await f.run(3);
  assert.ok(approved.history.some(r => /复核通过；识别 \d+ ms，复核 \d+ ms/.test(r.message)));
  assert.ok(approved.history.some(r => r.result === 'observedDismissed' && /点击后核对 \d+ ms/.test(r.message)));
});
test('disabled learning and paused applications retain their specific runtime reason', async () => {
  for (const paused of [true, false]) {
    const f = learningFixture({ apiVersion: 26, configure(state) {
      state.setSettings({ ...state.getSettings(), learningEnabled: false, ignoredPackages: paused ? [READER] : [] });
    } });
    const status = await f.run(1);
    assert.ok(status.history.some(r => r.message.includes(paused ? '此应用已暂停' : '此应用没有已保存规则')));
    assert.equal(status.clickCount, 0);
  }
});

function cleanNodes(bundle) {
  return Array.from({length: 7}, (_, i) => ({ bundle, id: 'item_' + i, text: ['首页', '我的', '搜索', '收藏', '', '', ''][i],
    enabled: true, clickable: false, bounds: { left: 40, top: 300 + i * 100, right: 600, bottom: 360 + i * 100 } }));
}
test('conservative list requires five full separated checks across a day and expires after a week', () => {
  const f = baseFixture();
  for (let i = 0; i < 5; i++) {
    f.state.now = 20000 + i * 6 * 3600000;
    assert.equal(f.adFree.completeCleanLaunch(HUYA, f.state.now - 12000), i === 4);
    assert.equal(f.adFree.read()[0].cleanLaunches, i + 1);
    f.state.now += 13000;
    f.adFree.completeCleanLaunch(HUYA, f.state.now - 12000);
    assert.equal(f.adFree.read()[0].cleanLaunches, i + 1, 'rapid reopen must not count');
  }
  assert.equal(f.adFree.paused(HUYA), true);
  f.state.now += 7 * 86400000;
  assert.equal(f.adFree.paused(HUYA), false);
  assert.equal(f.adFree.completeCleanLaunch(HUYA, f.state.now - 12000), true);
  f.adFree.evidence(HUYA);
  assert.equal(f.adFree.read().length, 0, 'ad evidence resets all clean history');
});
test('short launches, clock rollback and late worker writes cannot add or restore a manual release', () => {
  const f = baseFixture(); f.state.now = 20000;
  f.adFree.completeCleanLaunch(HUYA, f.state.now - 5999);
  assert.equal(f.adFree.read().length, 0);
  f.adFree.completeCleanLaunch(HUYA, f.state.now - 12000);
  const saved = f.state.files.get(DIRECTORY + '/ad-free-observations.json');
  f.state.now -= 1000; f.adFree.completeCleanLaunch(HUYA, f.state.now - 12000);
  assert.equal(f.adFree.read()[0].cleanLaunches, 1);
  f.state.now += 2000; f.adFree.release(HUYA);
  f.state.files.set(DIRECTORY + '/ad-free-observations.json', saved);
  assert.equal(f.adFree.read().length, 0);
  f.state.now += 12000; f.adFree.completeCleanLaunch(HUYA, f.state.now - 13000);
  assert.equal(f.adFree.read().length, 0, 'launch that began before release remains excluded');
});
test('complete readable launch gets one clean observation with sparse late scanning', async () => {
  const samples = [];
  const f = baseFixture({ apiVersion: 26, configure(s) { s.nodes = cleanNodes(HUYA); },
    onApi(name, s) { if (name === 'driver.dumpLayout') samples.push(s.elapsed); } });
  await f.run(14);
  assert.equal(f.adFree.read()[0]?.cleanLaunches, 1);
  assert.ok(samples.filter(t => t < 3000).length > 35);
  assert.ok(samples.filter(t => t >= 6000).length <= 9);
  assert.ok(samples.every(t => t < 12500));
  assert.equal(f.state.clickCalls.length, 0);
});
for (const failure of ['ad', 'image', 'empty', 'interrupted', 'unreadable', 'existingRule']) {
  test('never counts uncertain or known-ad launch as clean: ' + failure, async () => {
    const options = { apiVersion: 26, nullDiscoveryTree: failure === 'unreadable',
      configure(s) { s.nodes = failure === 'empty' ? [] : cleanNodes(HUYA);
        if (failure === 'ad') s.nodes.push({ ...homeNode(HUYA), text: '广告', clickable: false }); },
      onLayout(layout) { if (failure === 'image') layout.children.push({ attributes: { type: 'Image', id: 'hero',
        bounds: '[0,0][1320,1800]', visible: 'true', opacity: '1', enabled: 'true', hostWindowId: '1' }, children: [] }); },
      screenActive: s => failure !== 'interrupted' || s.elapsed < 4000 };
    const f = failure === 'existingRule' ? fixture(options) : baseFixture(options);
    await f.run(14); assert.equal(f.adFree.read().length, 0);
  });
}
test('screen off uses no UiTest calls; waking starts a new safe observation', async () => {
  const off = baseFixture({ screenActive: () => false }); await off.run(4);
  assert.equal(off.state.apiCalls.length, 0);
  const f = fixture({ apiVersion: 26, screenActive: s => s.elapsed >= 2000 });
  await f.run(5); assert.equal(f.state.clickCalls.length, 1);
  assert.ok(f.state.clickCalls[0].at >= 3000);
});
function seedPaused(s) {
  s.now = 100000000;
  s.files.set(DIRECTORY + '/ad-free-observations.json', JSON.stringify([{ bundle: HUYA, cleanLaunches: 5,
    firstCleanAt: 1, lastCleanAt: s.now, updatedAt: s.now, pausedUntil: s.now + 7 * 86400000 }]));
}
test('paused apps avoid layout reads, while disabling automation and expiry restore scanning', async () => {
  for (const mode of ['paused', 'off', 'expired', 'rule']) {
    const options = { apiVersion: 26, configure(s) { seedPaused(s);
      if (mode === 'off') s.setSettings({ ...s.getSettings(), autoAdFree: false });
      if (mode === 'expired') s.now += 8 * 86400000; } };
    const f = mode === 'rule' ? fixture(options) : baseFixture(options);
    await f.run(4);
    assert.equal(f.state.apiCalls.includes('driver.dumpLayout'), mode !== 'paused', mode);
    if (mode === 'rule') assert.equal(f.state.clickCalls.length, 1);
  }
});

test('temporary missing foreground invalidates a clean launch rather than joining two partial checks', async () => {
  const f = baseFixture({ apiVersion: 26, configure(s) { s.nodes = cleanNodes(HUYA); },
    windowBundle: (_, s) => s.elapsed > 4000 && s.elapsed < 4800 ? '' : s.foreground,
    onLayout(layout, s, filename) { if (s.elapsed > 4000 && s.elapsed < 4800) {
      layout.attributes.visible = 'false'; layout.attributes.focused = 'false';
    } } });
  await f.run(9); assert.equal(f.adFree.read().length, 0);
});

function quietPolicy(values = {}) { return { adFreeMinDays: 1, adFreeCleanChecks: 5, adFreeRecheckDays: 7, ...values }; }
test('custom observation span and count must both pass before applying the chosen recheck interval', () => {
  const f = baseFixture(), policy = quietPolicy({adFreeMinDays:2,adFreeCleanChecks:3,adFreeRecheckDays:4});
  for(let i=0;i<3;i++){
    f.state.now=20000+i*86400000;
    assert.equal(f.adFree.completeCleanLaunch(HUYA,f.state.now-12000,policy),i===2);
  }
  assert.equal(f.adFree.read(policy)[0].pausedUntil, f.state.now+4*86400000);
  assert.equal(f.adFree.paused(HUYA,f.state.now+4*86400000,policy),false);
});
test('raising the check threshold resumes previously auto-paused apps and keeps their observations', () => {
  const f=baseFixture(); seedPaused(f.state);
  assert.equal(f.adFree.paused(HUYA,f.state.now,quietPolicy()),true);
  const stricter=quietPolicy({adFreeCleanChecks:8});
  assert.equal(f.adFree.paused(HUYA,f.state.now,stricter),false);
  assert.equal(f.adFree.read(stricter)[0].cleanLaunches,5);
  for(let i=0;i<3;i++){
    f.state.now+=1800000;
    assert.equal(f.adFree.completeCleanLaunch(HUYA,f.state.now-12000,stricter),i===2);
  }
  assert.equal(f.adFree.read(stricter)[0].cleanLaunches,8);
});
test('raising observation span resumes a paused app that no longer meets it', () => {
  const f=baseFixture();seedPaused(f.state);
  assert.equal(f.adFree.paused(HUYA,f.state.now,quietPolicy({adFreeMinDays:7})),false);
});
test('changing recheck days uses the last completed check, never the settings change time', () => {
  const f=baseFixture();seedPaused(f.state);const last=f.state.now;f.state.now+=2*86400000;
  assert.equal(f.adFree.paused(HUYA,f.state.now,quietPolicy({adFreeRecheckDays:1})),false);
  const extended=quietPolicy({adFreeRecheckDays:10});
  assert.equal(f.adFree.read(extended)[0].pausedUntil,last+10*86400000);
  assert.equal(f.adFree.paused(HUYA,f.state.now,extended),true);
});
test('lowering thresholds does not admit an observed app until another complete check', () => {
  const f=baseFixture(), strict=quietPolicy({adFreeCleanChecks:20});
  for(let i=0;i<3;i++) { f.state.now=20000+i*86400000;f.adFree.completeCleanLaunch(HUYA,f.state.now-12000,strict); }
  const loose=quietPolicy({adFreeCleanChecks:2});
  assert.equal(f.adFree.paused(HUYA,f.state.now,loose),false);
  f.state.now+=1800000;assert.equal(f.adFree.completeCleanLaunch(HUYA,f.state.now-12000,loose),true);
});
test('policy changes cannot revive a manually released automatic pause', () => {
  const f=baseFixture();seedPaused(f.state);f.adFree.release(HUYA);
  assert.equal(f.adFree.paused(HUYA,f.state.now,quietPolicy({adFreeCleanChecks:2,adFreeRecheckDays:30})),false);
});

function collidingGeometryFixture() {
  const f = fixture();
  const old = f.learningStore.readRules().find(r => r.bundle === HUYA);
  Object.assign(old, { left: 0.804, right: 0.904, top: 0.01, bottom: 0.04 });
  old.key = f.models.ruleKey(old);
  f.learningStore.saveRules([old]); f.learningStore.decide(old.key, 'approved');
  const incoming = { ...old, firstSeen: 0, observations: 0, left: 0.844, right: 0.944 };
  assert.equal(f.models.ruleKey(incoming), old.key);
  assert.equal(f.models.sameRuleGeometry(old, incoming), false);
  return { f, old, incoming };
}
test('different geometry in the same coarse key appends a pending template without overwriting approval', () => {
  const { f, old, incoming } = collidingGeometryFixture();
  const added = f.learningStore.observe(incoming);
  assert.ok(added && added.key !== old.key);
  assert.equal(f.learningStore.readRules().length, 2);
  assert.equal(f.models.ruleState(added, f.learningStore.readDecisions()), 'pending');
  const preserved = f.learningStore.readRules().find(r => r.key === old.key);
  assert.equal(preserved.left, old.left);
  assert.equal(f.models.ruleState(preserved, f.learningStore.readDecisions()), 'approved');
});
test('geometry variants are reused across frames while the old template remains independently matchable', () => {
  const { f, old, incoming } = collidingGeometryFixture();
  const added = f.learningStore.observe(incoming);
  f.learningStore.decide(added.key, 'approved');
  const fresh = { ...incoming, variant: '', left: incoming.left - 0.001 };
  fresh.key = f.models.ruleKey(fresh);
  f.learningStore.resolveCandidate(fresh);
  assert.equal(fresh.key, added.key);
  assert.ok(f.models.sameRuleGeometry(added, fresh));
  f.learningStore.observe(fresh);
  assert.equal(f.learningStore.readRules().length, 2);
  const original = { ...old }; f.learningStore.resolveCandidate(original);
  assert.equal(original.key, old.key);
});
test('geometry variants cannot bypass per-template approval or relearning reset', () => {
  const { f, incoming } = collidingGeometryFixture();
  const added = f.learningStore.observe(incoming);
  assert.equal(f.models.ruleState(added, f.learningStore.readDecisions()), 'pending');
  f.learningStore.resetAppRules(HUYA);
  assert.equal(f.learningStore.readRules().length, 0);
  const fresh = { ...incoming, firstSeen: 0, variant: '' }; fresh.key = f.models.ruleKey(fresh);
  const relearned = f.learningStore.observe(fresh);
  assert.equal(f.models.ruleState(relearned, f.learningStore.readDecisions()), 'pending');
});
test('worker learns a colliding new style in an approved app and clicks it only after separate approval', async () => {
  const f = fixture({ apiVersion: 26 });
  const old = f.learningStore.readRules().find(r => r.bundle === HUYA);
  old.left = 1061 / WINDOW.right; old.right = 1193 / WINDOW.right;
  old.key = f.models.ruleKey(old);
  f.learningStore.saveRules([old]); f.learningStore.decide(old.key, 'approved');
  const target = f.state.nodes.find(n => n.id === 'huyaSkipButton');
  target.bounds.left = 1114; target.bounds.right = 1246;
  assert.equal((await f.run(2)).clickCount, 0);
  const added = f.learningStore.readRules().find(r => r.key !== old.key);
  assert.ok(added, 'new geometry should be recorded beside the existing approved rule');
  assert.equal(f.models.ruleState(added, f.learningStore.readDecisions()), 'pending');
  f.learningStore.decide(added.key, 'approved');
  assert.equal((await f.run(2)).clickCount, 1);
});

test('rule packs reject unsupported Android selectors and oversized data rather than dropping restrictions', () => {
  const f = fixture();
  const pack = f.builtinPack.builtinRulePack();
  assert.throws(() => f.rulePack.parseRulePack(JSON.stringify({ ...pack, rules: [{ ...pack.rules[0], activityIds: ['MainActivity'] }] })));
  assert.throws(() => f.rulePack.parseRulePack(JSON.stringify({ ...pack, rules: [{ ...pack.rules[0], action: 'shell' }] })));
  assert.throws(() => f.rulePack.parseRulePack(JSON.stringify({ ...pack, rules: [...pack.rules, pack.rules[0]] })));
  assert.throws(() => f.rulePack.parseRulePack(' '.repeat(131073)));
});

test('recognition pack broadens short splash wording but still rejects video, consent and wrong app scopes', () => {
  const f = fixture(); const pack = f.builtinPack.builtinRulePack();
  assert.equal(f.rulePack.packLabel('点击跳过 3s', 'text', HUYA, pack), '跳过');
  for (const text of ['跳过片头', '跳过视频', '跳过登录', '跳过授权', '跳过教程', '广告不可跳过', '不跳过', '不略过']) {
    assert.equal(f.rulePack.packLabel(text, 'text', HUYA, pack), '');
  }
  const scoped = { ...pack, rules: [{ ...pack.rules[0], bundles: [YOUKU] }] };
  assert.equal(f.rulePack.packLabel('点击跳过', 'text', HUYA, scoped), '');
});
test('nearby geometry crossing coarse bucket boundaries reuses the approved template', () => {
  const f = fixture();
  const old = f.learningStore.readRules().find(r => r.bundle === HUYA);
  old.left = 0.849; old.right = 0.949; old.key = f.models.ruleKey(old);
  f.learningStore.saveRules([old]); f.learningStore.decide(old.key, 'approved');
  const candidate = { ...old, left: 0.851, right: 0.951 };candidate.key = f.models.ruleKey(candidate);
  assert.notEqual(candidate.key, old.key);
  f.learningStore.resolveCandidate(candidate);
  assert.equal(candidate.key, old.key);
  f.learningStore.observe(candidate);
  assert.equal(f.learningStore.readRules().length, 1);
  assert.equal(f.models.ruleState(f.learningStore.readRules()[0], f.learningStore.readDecisions()), 'approved');
});
test('generic subscribed wording is learned and verified with two snapshots, without inheriting approval', async () => {
  const f = fixture({ apiVersion: 26 });
  f.learningStore.resetAppRules(HUYA);
  f.state.nodes.find(n => n.id === 'huyaSkipButton').text = '点击跳过';
  assert.equal((await f.run(2)).clickCount, 0);
  const found = f.learningStore.readRules().find(r => r.bundle === HUYA);
  assert.ok(found);assert.equal(found.label, '跳过');
  f.learningStore.decide(found.key, 'approved');
  assert.equal((await f.run(2)).clickCount, 1);
});
test('subscribed skip wording without independent ad evidence is not learned or clicked', async () => {
  const f = fixture({ apiVersion: 26 });
  f.learningStore.resetAppRules(HUYA);
  f.state.nodes = f.state.nodes.filter(n => n.text !== '广告');
  f.state.nodes.find(n => n.id === 'huyaSkipButton').text = '点击跳过';
  assert.equal((await f.run(2)).clickCount, 0);
  assert.equal(f.learningStore.readRules().filter(r => r.bundle === HUYA).length, 0);
});
test('unusable text candidate cannot suppress a valid ad-specific icon candidate in the same snapshot', async () => {
  const f = fixture({ apiVersion: 26 });
  f.learningStore.resetAppRules(HUYA);
  const button = f.state.nodes.find(n => n.id === 'huyaSkipButton');
  button.id = 'splash_ad_skip_btn';button.text = '';
  f.state.nodes.push({ ...button, id: 'unrelatedText', text: '跳过', clickable: false,
    bounds: { left: 0, top: 0, right: 1320, bottom: 1500 } });
  assert.equal((await f.run(2)).clickCount, 0);
  const found = f.learningStore.readRules().find(r => r.bundle === HUYA);
  assert.ok(found);assert.equal(found.targetId, 'splash_ad_skip_btn');
});
test('new local conditions become usable without modifying user approvals', async () => {
  const f = fixture({ apiVersion: 26 });f.learningStore.resetAppRules(HUYA);
  f.state.nodes.find(n => n.id === 'huyaSkipButton').text='点击掠过';
  assert.equal((await f.run(2)).clickCount,0);
  assert.equal(f.learningStore.readRules().filter(r=>r.bundle===HUYA).length,0);
  const updated={...f.builtinPack.builtinRulePack(),version:2};
  updated.rules.push({id:'new-omit',field:'text',value:'掠过',match:'contains',action:'skip',bundles:[],exclude:[],maxLength:10});
  f.packs.setLocalRules(updated.rules);
  assert.equal((await f.run(2)).clickCount,0);
  const found=f.learningStore.readRules().find(r=>r.bundle===HUYA);assert.ok(found);
  assert.equal(f.models.ruleState(found,f.learningStore.readDecisions()),'pending');
  f.learningStore.decide(found.key,'approved');
  assert.equal((await f.run(2)).clickCount,1);
});

function relationalFixture(kind, change) {
  return learningFixture({ apiVersion: 26, configure(state) {
    const target = state.nodes[0]; target.id = 'dismiss_target'; target.text = '';
    if (kind === 'split') {
      for (const [i, text] of ['跳', '过广告'].entries()) state.nodes.push({ ...target, id: 'part' + i,
        text, clickable: false, parent: target,
        bounds: { left: 1100 + i * 55, top: 100, right: 1150 + i * 55, bottom: 160 } });
    } else {
      target.text = '关闭';
      const group = { ...target, id: 'button_group', text: '', clickable: false,
        bounds: { left: 1040, top: 90, right: 1220, bottom: 170 } };
      target.parent = group;
      state.nodes.push(group, { ...target, id: 'timer', text: '５s', clickable: false, parent: group,
        bounds: { left: 1040, top: 100, right: 1090, bottom: 160 } });
    }
    change?.(state, target);
  } });
}

test('split text in one compact button becomes a learned local rule and verifies dismissal', async () => {
  const f = relationalFixture('split');
  const rule = await observeAndApprove(f);
  assert.equal(rule.example, '跳过广告');
  const status = await f.run(4);
  assert.equal(status.clickCount, 1); assert.equal(status.observedDismissedCount, 1);
  assert.equal(f.state.apiCalls.includes('driver.findComponents'), false);
});

test('close and sibling countdown generate a pending rule, require approval and verify disappearance', async () => {
  const f = relationalFixture('countdown');
  const rule = await observeAndApprove(f);
  assert.equal(rule.marker, 'close-countdown');
  assert.equal(rule.recognition, 'close-countdown');
  const status = await f.run(4);
  assert.equal(status.clickCount, 1); assert.equal(status.observedDismissedCount, 1);
});

for (const variant of ['unrelated', 'hidden', 'clickable', 'far', 'login']) {
  test(`close-countdown experience rejects ${variant} context`, async () => {
    const f = relationalFixture('countdown', (state, target) => {
      const timer = state.nodes.find(n => n.id === 'timer');
      if (variant === 'unrelated') timer.parent = undefined;
      if (variant === 'hidden') timer.visible = false;
      if (variant === 'clickable') timer.clickable = true;
      if (variant === 'far') timer.bounds = { left: 500, top: 100, right: 550, bottom: 160 };
      if (variant === 'login') state.nodes.push({ ...timer, id: 'login', text: '登录', parent: target.parent });
    });
    assert.equal((await f.run(3)).clickCount, 0);
    assert.equal(f.learningStore.readRules().length, 0);
  });
}

for (const variant of ['clickable', 'hidden', 'foreign', 'vertical']) {
  test(`split label does not merge ${variant} child controls`, async () => {
    const f = relationalFixture('split', state => {
      const part = state.nodes.find(n => n.id === 'part1');
      if (variant === 'clickable') part.clickable = true;
      if (variant === 'hidden') part.visible = false;
      if (variant === 'foreign') part.bundle = 'com.other.app';
      if (variant === 'vertical') part.bounds = { left: 1155, top: 180, right: 1205, bottom: 200 };
    });
    await f.run(3); assert.equal(f.learningStore.readRules().length, 0);
  });
}

test('new style is appended beside approved rules and rejected style stays rejected', async () => {
  const f = relationalFixture('countdown');
  const original = await observeAndApprove(f);
  f.state.nodes[0].text = '跳过广告';
  await f.run(3);
  let rules = f.learningStore.readRules(); assert.equal(rules.length, 2);
  assert.equal(f.models.ruleState(rules.find(r => r.key === original.key), f.learningStore.readDecisions()), 'approved');
  const added = rules.find(r => r.key !== original.key);
  assert.equal(f.models.ruleState(added, f.learningStore.readDecisions()), 'pending');
  f.learningStore.decide(added.key, 'rejected');
  await f.run(3); rules = f.learningStore.readRules(); assert.equal(rules.length, 2);
  assert.equal(f.models.ruleState(rules.find(r => r.key === added.key), f.learningStore.readDecisions()), 'rejected');
  assert.equal(f.state.clickCalls.length, 0);
});

test('originalText participates in discovery and cannot turn a retained target into a success', async () => {
  const f = learningFixture({ apiVersion: 26, onClick() {}, onLayout(tree) {
    const button = tree.children[0]; button.attributes.originalText = button.attributes.text;
    button.attributes.text = '';
  } });
  await observeAndApprove(f);
  const status = await f.run(5);
  assert.equal(status.clickCount, 1); assert.equal(status.observedDismissedCount, 0);
});

test('one-frame candidate is not persisted as a new local rule', async () => {
  let reads = 0;
  const f = learningFixture({ apiVersion: 26, onLayout(tree, state, path) {
    if (path.endsWith('/discovery-snapshot.json') && ++reads > 1) {
      tree.children = [{ attributes: { id: 'home', text: '首页', visible: 'true', enabled: 'true',
        clickable: 'false', bounds: '[0,0][1320,2100]' } }];
    }
  } });
  await f.run(3);
  assert.equal(f.learningStore.readRules().length, 0); assert.equal(f.state.clickCalls.length, 0);
});

test('close-countdown relations work at the left corner as well', async () => {
  const f = relationalFixture('countdown', state => {
    for (const node of state.nodes) {
      const b = node.bounds; node.bounds = { ...b, left: WINDOW.right - b.right, right: WINDOW.right - b.left };
    }
  });
  await observeAndApprove(f);
  assert.equal((await f.run(4)).clickCount, 1);
});

test('anonymous composed label still present is not reported as disappeared', () => {
  const f = fixture();
  const tree = { attributes: { type: 'root', bundleName: HUYA, focused: 'true', visible: 'true',
    hostWindowId: '1', bounds: '[0,0][1320,2100]' }, children: [{ attributes: {
    id: '', text: '', enabled: 'true', clickable: 'true', visible: 'true', bounds: '[1100,90][1220,170]'
  }, children: ['跳', '过广告'].map((text, i) => ({ attributes: { text, enabled: 'true', clickable: 'false',
    visible: 'true', bounds: `[${1100 + i * 55},100][${1150 + i * 55},160]` } })) }] };
  const candidate = f.learningWorker.discoverSnapshot(JSON.stringify(tree), HUYA, new f.learningWorker.ScanReport());
  assert.ok(candidate);
  assert.equal(f.learningWorker.snapshotTargetState(JSON.stringify(tree), candidate.rule), 'present');
});

test('unrelated repeated IDs do not block learned clicks or falsely imply the ad remained', async () => {
 const f=learningFixture({apiVersion:26,configure(state){
  const target=state.nodes[0];target.id='common_control';
  state.nodes.push({...target,text:'主页',bounds:{left:100,top:800,right:200,bottom:870}});
 },onClick(node,state){state.nodes=state.nodes.filter(n=>n!==node).concat(homeNode(READER));}});
 await observeAndApprove(f);
 const status=await f.run(5);assert.equal(status.clickCount,1);assert.equal(status.observedDismissedCount,1);
});
test('two valid skip targets sharing an ID remain ambiguous', async () => {
 const f=learningFixture({apiVersion:26,configure(state){
  const target=state.nodes[0];target.id='common_control';
  state.nodes.push({...target,bounds:{left:100,top:90,right:220,bottom:170}});
 }});
 assert.equal((await f.run(3)).clickCount,0);assert.equal(f.learningStore.readRules().length,0);
});

test('local recognition editing and reset preserve learned rules',()=>{
 const f=fixture();const personal=JSON.stringify(f.learningStore.readRules());
 const original=f.packs.read();const rules=JSON.parse(JSON.stringify(original.rules));rules[0].value='立即跳过';
 f.packs.setLocalRules(rules);assert.equal(f.packs.read().rules[0].value,'立即跳过');
 f.packs.resetLocalRules();assert.equal(f.packs.preferences().rules,undefined);
 assert.equal(f.packs.read().rules[0].value,original.rules[0].value);
 assert.equal(JSON.stringify(f.learningStore.readRules()),personal);
});
test('invalid local edits never overwrite the active conditions and empty edits remain explicitly empty',()=>{
 const f=fixture();const before=JSON.stringify(f.packs.read());
 assert.throws(()=>f.packs.setLocalRules([{...f.packs.read().rules[0],script:'click()'}]));
 assert.equal(JSON.stringify(f.packs.read()),before);f.packs.setLocalRules([]);assert.equal(f.packs.read().rules.length,0);
 f.packs.resetLocalRules();assert.ok(f.packs.read().rules.length>0);
});


for (const change of [false,true]) test(`image OCR refreshes coordinates after slow recognition; changed page=${change}`, async()=>{
 const f=baseFixture({apiVersion:26,onImageAd(state){state.advance(900); if(change)state.nodes=[homeNode(HUYA)]; return true;},
 onLayout(layout){
  const marker=layout.children.find(n=>n.attributes.text==='广告');
  if(!marker)return;
  marker.attributes.text='';marker.attributes.type='Image';marker.attributes.bounds='[40,90][160,150]';
  layout.children=[{attributes:{...layout.attributes,type:'Column',clickable:'true',enabled:'true'},children:layout.children}];
 }});
 const status=await f.run(8);
 assert.equal(status.clickCount,0);
 assert.equal(f.learningStore.readRules().length,change?0:1);
});
for(const changed of [false,true]) test(`approved buttons skip OCR even when surrounding layout changes; changed=${changed}`,async()=>{
 let reads=0;
 const opts={apiVersion:26,onImageAd(){reads++;return true;},onLayout(layout){
 const marker=layout.children.find(n=>n.attributes.text==='广告');if(!marker)return;
 marker.attributes.text='';marker.attributes.type='Image';marker.attributes.bounds='[40,90][160,150]';
 layout.children=[{attributes:{...layout.attributes,type:'Column',clickable:'true',enabled:'true'},children:layout.children}];
 }};
 const first=fixture(opts);assert.equal((await first.run(8)).clickCount,1);assert.equal(reads,0,'enabled button requires no OCR');

 reads=0;
 const second=fixture({...opts,onLayout(layout){opts.onLayout(layout);if(changed)layout.attributes.pagePath='ChangedSplash';}});

 assert.equal((await second.run(8)).clickCount,1);
 assert.equal(reads,0);
});

for(const found of [true,false]) test(`large artwork OCR budget and new-rule learning; found=${found}`,async()=>{
 let reads=0;
 const f=baseFixture({apiVersion:26,onImageAd(){reads++;return found;},onLayout(layout){
  const marker=layout.children.find(n=>n.attributes.text==='广告');if(!marker)return;
  marker.attributes.text='';marker.attributes.type='Image';marker.attributes.bounds='[40,90][1250,2050]';
  layout.children=[{attributes:{...layout.attributes,type:'Column',clickable:'true',enabled:'true'},children:layout.children}];
 }});
 const result=await f.run(8);assert.equal(result.clickCount,0,'new evidence cannot authorize input');
 assert.equal(reads,1,'large image is OCRed at most once per foreground session');
 const rules=f.learningStore.readRules();assert.equal(rules.length,found?1:0);
});

test('approved button survives missing ad evidence between snapshots with zero OCR',async()=>{
 let dumps=0,ocr=0;
 const f=fixture({apiVersion:26,onImageAd(){ocr++;throw Error('OCR must not run');},onApi(name,state){
  if(name==='driver.dumpLayout'&&++dumps===2)state.nodes=state.nodes.slice(0,1);
 }});
 assert.equal((await f.run(4)).clickCount,1);assert.equal(ocr,0);
});

test('execution preflight rejects changed button without invoking OCR and retries discovery later',async()=>{
 let dumps=0,ocr=0;
 const f=fixture({apiVersion:26,onImageAd(){ocr++;return true;},onLayout(layout){
  if(++dumps!==2)return;
  layout.children[0].attributes.id='changed_close';
  const marker=layout.children.find(n=>n.attributes.text==='广告');
  marker.attributes.text='';marker.attributes.type='Image';marker.attributes.bounds='[40,90][160,150]';
  layout.children=[{attributes:{...layout.attributes,type:'Column',clickable:'true',enabled:'true'},children:layout.children}];
 }});
 assert.equal((await f.run(5)).clickCount,1);assert.equal(ocr,0);assert.ok(dumps>=4);
});
test('expiry during final settings read leaves unsent opportunity available for fresh retry',async()=>{
 let dumps=0,delayed=false;
 const f=fixture({apiVersion:26,onApi(name){if(name==='driver.dumpLayout')dumps++;},onRead(path,state){
  if(dumps===2&&!delayed&&path.endsWith('/settings.json')){delayed=true;state.advance(350);}
 }});
 const status=await f.run(5);assert.equal(delayed,true);assert.equal(status.clickCount,1);assert.equal(status.attemptCount,1);
 assert.equal(f.state.apiCalls.filter(n=>n==='driver.click').length,1);assert.ok(dumps>=4);
 assert.ok(status.history.some(r=>r.message.includes('未发送点击')));
});

test('legacy approved text rule without labelSource remains eligible for selected-button preflight',async()=>{
 let ocr=0;const f=fixture({apiVersion:26,onImageAd(){ocr++;return false;}});
 const path=DIRECTORY+'/learned-rules.json';const rules=JSON.parse(f.state.files.get(path));
 for(const rule of rules)delete rule.labelSource;
 f.state.files.set(path,JSON.stringify(rules));
 const status=await f.run(5);assert.equal(status.clickCount,1);assert.equal(status.observedDismissedCount,1);assert.equal(ocr,0);
});

for(const settlesAt of [0,3000,7000]) test(`clean launch needs six continuous seconds within twelve-second budget; settles=${settlesAt}`,async()=>{
 const reads=[];const f=baseFixture({apiVersion:26,configure(s){s.nodes=cleanNodes(HUYA);},onLayout(layout,state){
  reads.push(state.elapsed);if(state.elapsed<settlesAt)layout.children=[];
 }});
 await f.run(14);assert.equal(f.adFree.read().length,settlesAt===7000?0:1);
 if(settlesAt<7000){assert.ok(reads.at(-1)>=settlesAt+6000);assert.ok(reads.at(-1)<settlesAt+7200);}
});
test('readability interruption restarts the continuous clean interval',async()=>{
 const f=baseFixture({apiVersion:26,configure(s){s.nodes=cleanNodes(HUYA);},onLayout(layout,state){
  if(state.elapsed>=4000&&state.elapsed<6000)layout.children=[];
 }});
 await f.run(11);assert.equal(f.adFree.read().length,0);
});

test('clean observation emits one completion record, no per-second progress or duplicate',async()=>{
 const f=baseFixture({apiVersion:26,configure(s){s.nodes=cleanNodes(HUYA);}});
 const status=await f.run(14);
 assert.equal(f.adFree.read()[0].cleanLaunches,1);
 const records=status.history.filter(r=>r.bundle===HUYA);
 assert.equal(records.filter(r=>r.message.includes('有效检查已计数')).length,1);
 assert.equal(records.filter(r=>r.message.includes('/6 秒')).length,0);
 assert.equal(records.filter(r=>r.message.includes('观察已结束')).length,0);
});
test('unfinished clean observation emits one summary on session end',async()=>{
 const f=baseFixture({apiVersion:26,configure(s){s.nodes=cleanNodes(HUYA);}});
 const status=await f.run(3);
 assert.equal(f.adFree.read().length,0);
 const records=status.history.filter(r=>r.bundle===HUYA);
 assert.equal(records.length,1);
 assert.match(records[0].message,/检查未完成/);
});
test('unreadable observation keeps only one timeout summary',async()=>{
 const f=baseFixture({apiVersion:26,configure(s){s.nodes=cleanNodes(HUYA);},onLayout(layout){layout.children=[];}});
 const status=await f.run(14);
 assert.equal(f.adFree.read().length,0);
 const records=status.history.filter(r=>r.bundle===HUYA);
 assert.equal(records.length,1);assert.match(records[0].message,/观察已结束/);
});

test('Android app provenance persists independently of rules and user labels',()=>{
 const f=baseFixture();assert.equal(f.learningStore.androidApps().includes(HUYA),false);
 f.learningStore.recordAndroidApp(HUYA);f.learningStore.renameSeenApp(HUYA,'自定义名称');
 assert.equal(f.learningStore.androidApps().includes(HUYA),true);
 assert.equal(f.learningStore.displayName(HUYA),'自定义名称');
 assert.equal(f.learningStore.readRules().length,0);
 f.learningStore.recordAndroidApp(HUYA);assert.equal(f.learningStore.androidApps().filter(x=>x===HUYA).length,1);
});
test('existing Android rules expose app provenance before next launch',()=>{
 const f=fixture();const path=DIRECTORY+'/learned-rules.json';const rules=JSON.parse(f.state.files.get(path));
 rules[0].buttonType='android.widget.ImageView';f.state.files.set(path,JSON.stringify(rules));
 assert.equal(f.learningStore.androidApps().includes(HUYA),true);
 f.state.files.set(path,'[]');assert.equal(f.learningStore.androidApps().includes(HUYA),true);
});

test('desktop observation fills an old package-only name without altering its user alias',async()=>{
 const target='com.epicgames.portal',desktop='com.ohos.sceneboard';let dumps=0;
 const f=baseFixture({apiVersion:26,bundle:desktop,configure(s){s.nodes=[homeNode(desktop)];},onLayout(layout){
  dumps++;layout.attributes={bundleName:desktop,visible:'true',type:'root',focused:'true',bounds:'[0,0][1320,2120]'};
  layout.children=[{attributes:{id:'Container_AppIcon_Image_'+target+'com.epicgames.portal.ui.MainActivityentry0_undefined_0',visible:'true'},children:[{attributes:{type:'Text',text:'Epic Games',visible:'true'}}]}];
 }});
 f.learningStore.recordSeenApp(target);await f.run(7);
 assert.equal(f.learningStore.displayName(target),'Epic Games');assert.ok(dumps<=2);
 f.learningStore.renameSeenApp(target,'我的游戏库');assert.equal(f.learningStore.displayName(target),'我的游戏库');
});

test('desktop metadata is collected once per visit, not while idling or losing focus briefly',async()=>{
 const desktop='com.ohos.sceneboard',target='com.epicgames.portal';let dumps=0;
 const f=baseFixture({apiVersion:26,bundle:desktop,onTime(state){
  state.foreground=state.elapsed>=10000&&state.elapsed<12000?'':
   state.elapsed>=20000&&state.elapsed<24000?'com.tonghongxiang.quietstart':desktop;
 },onLayout(layout,state,path){
  if(path.endsWith('/desktop-names-snapshot.json'))dumps++;
  layout.attributes={type:'root',bundleName:state.foreground,focused:'true',visible:'true',bounds:'[0,0][1320,2120]'};
  layout.children=[];
 }});
 f.learningStore.recordSeenApp(target);await f.run(40);
 assert.equal(dumps,2,'initial visit and return from app only');

});

test('upgrade removes obsolete icon files including orphans but preserves names and rules',()=>{
 const f=baseFixture();
 const removed=['app-icons.json','app-icon-failures.json','app-icon-com.example.orphan.png','desktop-icon-tmp.png'];
 const retained=['app-names.json','app-aliases.json','learned-rules.json','other.png'];
 for(const name of [...removed,...retained])f.state.files.set(DIRECTORY+'/'+name,'preserve');
 f.learningStore.clearLegacyAppIcons();f.learningStore.clearLegacyAppIcons();
 for(const name of removed)assert.equal(f.state.files.has(DIRECTORY+'/'+name),false);
 for(const name of retained)assert.equal(f.state.files.get(DIRECTORY+'/'+name),'preserve');
});

for (const side of ['left','right']) {
 test(`semantic graphical countdown without digits is sufficient at ${side} corner`,async()=>{
  const f=relationalFixture('countdown',(state)=>{
   const timer=state.nodes.find(n=>n.id==='timer');timer.id='splash_countdown_ring';timer.text='';timer.type='Progress';
   if(side==='left')for(const n of state.nodes){const b=n.bounds;n.bounds={...b,left:WINDOW.right-b.right,right:WINDOW.right-b.left};}
  });
  const rule=await observeAndApprove(f);assert.equal(rule.marker,'close-countdown');
  assert.equal((await f.run(4)).clickCount,1);
 });
}
for(const kind of ['loading','unrelated','hidden','clickable']){
 test(`graphical countdown rejects ${kind} control`,async()=>{
  const f=relationalFixture('countdown',(state)=>{
   const timer=state.nodes.find(n=>n.id==='timer');timer.id=kind==='loading'?'loading_spinner':'countdown_ring';timer.text='';timer.type=kind==='loading'?'LoadingProgress':'Progress';
   if(kind==='unrelated')timer.parent=undefined;
   if(kind==='hidden')timer.visible=false;
   if(kind==='clickable')timer.clickable=true;
  });
  await f.run(3);assert.equal(f.learningStore.readRules().length,0);assert.equal(f.state.clickCalls.length,0);
 });
}

for(const label of ['跳过','关闭'])for(const type of ['Progress','ArcProgress','android.widget.ProgressBar'])for(const layout of ['overlap','nested','adjacent']){
 test(`generic ${type} ${layout} with ${label} learns without ad marker or countdown text`,async()=>{
  const f=relationalFixture('countdown',(state,target)=>{
   target.text=label;
   const timer=state.nodes.find(n=>n.id==='timer');timer.id='anonymous_progress';timer.text='';timer.type=type;
   if(layout!=='adjacent')timer.bounds={...target.bounds};
   if(layout==='nested'){
    const wrapper={...timer,id:'wrapper',type:'Stack',parent:target};state.nodes.push(wrapper);timer.parent=wrapper;
   }
  });
  const rule=await observeAndApprove(f);
  assert.equal(rule.marker,label==='关闭'?'close-countdown':'countdown');
  assert.equal((await f.run(4)).clickCount,1);
 });
}
for(const bad of ['far','loading','playback','large-group','no-action']){
 test(`generic progress rejects ${bad}`,async()=>{
  const f=relationalFixture('countdown',(state,target)=>{
   const timer=state.nodes.find(n=>n.id==='timer');timer.id='anonymous_progress';timer.text='';timer.type='Progress';
   if(bad==='far')timer.bounds={left:500,top:100,right:550,bottom:160};
   if(bad==='large-group')target.parent.bounds={...WINDOW};
   if(bad==='no-action')target.text='取消';
   if(['loading','playback'].includes(bad))state.nodes.push({...timer,id:'context',type:'Text',text:bad==='loading'?'正在加载':'正在播放'});
  });
  await f.run(3);assert.equal(f.learningStore.readRules().length,0);assert.equal(f.state.clickCalls.length,0);
 });
}

test('sampled anonymous text and overlapping progress structure is recognized for arbitrary bundles and both corners',()=>{
 const f=fixture();
 for(const bundle of ['com.hupu.heroes','com.example.unlisted'])for(const left of [108,1077]){
  const bounds=`[${left},180][${left+135},315]`;
  const attrs=(type,clickable=false,text='')=>({type,bounds,text,enabled:'true',visible:'true',clickable:String(clickable),hitTestBehavior:'HitTestMode.Default'});
  const tree={attributes:{type:'root',bundleName:bundle,focused:'true',visible:'true',bounds:'[0,0][1320,2120]',hostWindowId:'1'},children:[
   {attributes:attrs('__Common__'),children:[{attributes:attrs('Stack',true),children:[
    {attributes:attrs('Text',false,'跳过')},{attributes:attrs('Progress')}
   ]}]}
  ]};
  const candidate=f.learningWorker.discoverSnapshot(JSON.stringify(tree),bundle,new f.learningWorker.ScanReport());
  assert.ok(candidate,`${bundle} ${left}`);assert.equal(candidate.rule.marker,'countdown');assert.equal(candidate.rule.progressStyle,'ring');
 }
});

test('stable approved target survives a 549ms layout read without OCR or extra snapshots',async()=>{
 let reads=0;
 const f=fixture({apiVersion:26,onApi(name,state){if(name==='driver.dumpLayout'&&++reads===2)state.advance(549);}});
 assert.equal((await f.run(4)).clickCount,1);
 const calls=f.state.apiCalls.slice(0,f.state.apiCalls.indexOf('driver.click'));
 assert.equal(calls.filter(n=>n==='driver.dumpLayout').length,2);
});
test('combined capture and post-read delay cannot exceed the total freshness budget',async()=>{
 let reads=0;
 const f=fixture({apiVersion:26,onApi(name,state){
  if(name==='driver.dumpLayout'){reads++;if(reads%2===0)state.advance(650);}
  if(reads>=2&&name==='driver.findWindow')state.advance(200);
 }});
 const result=await f.run(4);assert.equal(result.clickCount,0);
 assert.ok(result.history.some(x=>x.message.includes('总计超过 800 ms')));
});

test('click and dismissal records share one explicit process identity',async()=>{
 const f=fixture({apiVersion:26});const status=await f.run(4);
 const records=status.history.filter(r=>['attempt','clickSent','observedDismissed'].includes(r.result));
 assert.equal(records.length,3);assert.ok(records[0].processId);
 assert.equal(new Set(records.map(r=>r.processId)).size,1);
 assert.ok(records.every(r=>r.processStartedAt>0&&r.processStartedAt<=r.at));
});

test('input timeline uses action time rather than deferred logging time',async()=>{
 const f=fixture({apiVersion:26,onApi(name,state){if(name==='driver.click')state.advance(250);}});
 const status=await f.run(4);
 const attempt=status.history.find(r=>r.result==='attempt');const sent=status.history.find(r=>r.result==='clickSent');
 assert.ok(attempt&&sent);assert.ok(sent.at-attempt.at>=250);
 const ready=status.history.find(r=>r.result==='decision'&&r.message.includes('双快照复核通过'));
 assert.equal(ready.at,attempt.at);
});

test('community timer-image structure learns pending then clicks and verifies its own target',async()=>{
 const f=learningFixture({apiVersion:26,configure(state){
  const target=state.nodes[0];target.id='';target.text='';target.type='Image';target.bounds={left:1150,top:100,right:1210,bottom:160};
  const group={...target,id:'ad_skip_group',type:'Row',clickable:false,bounds:{left:1040,top:90,right:1220,bottom:170}};
  target.parent=group;
  state.nodes.push(group,{...target,id:'timer',type:'Text',text:'5s',clickable:false,parent:group,bounds:{left:1050,top:100,right:1100,bottom:160}});
 }});
 const rule=await observeAndApprove(f);assert.equal(rule.labelSource,'structure');assert.equal(rule.structureKind,'countdown-image');
 assert.equal(f.models.validRule(rule),true);
 const status=await f.run(4);assert.equal(status.clickCount,1);assert.equal(status.observedDismissedCount,1);
 assert.equal(f.state.clickCalls[0].id,'');
});

test('nonclickable semantic target learns pending and approved rule survives transient ids without fresh ad evidence', async () => {
 const f = learningFixture({ apiVersion: 26, configure(state) {
  const target = state.nodes[0];
  target.id = '977152'; target.text = '跳过5'; target.type = 'Text';
  const parent = { ...target, id: '338117', text: '', type: 'Row', clickable: false,
   bounds: { left: 1080, top: 80, right: 1240, bottom: 180 } };
  target.parent = parent;
  state.nodes.push(parent);
 }, onLayout(layout) {
  // The gesture handler exists, but accessibility reports false, as in the real snapshot.
  const visit = node => {
   if (node.attributes.type === 'Text') node.attributes.clickable = 'false';
   (node.children || []).forEach(visit);
  };
  visit(layout);
 } });
 const rule = await observeAndApprove(f);
 assert.equal(rule.recognition, 'semantic');
 assert.equal(rule.targetId, '');
 assert.equal(f.models.validRule(rule), true);
 f.state.nodes[0].id = '988000'; f.state.nodes[0].text = '跳过';
 const status = await f.run(4);
 assert.equal(status.clickCount, 1);
 assert.equal(status.observedDismissedCount, 1);
 assert.equal(f.learningStore.readRules().length, 1);
});


test('new auto rules inherit the setting once; turning it on never overrides rejection', async () => {
  const f = baseFixture({ configure(s) { s.setSettings({...s.getSettings(), autoEnableRules: true}); } });
  await f.run();
  const r=f.learningStore.readRules()[0]; assert.equal(r.autoApproved,true);
  assert.equal(f.models.ruleState(r,f.learningStore.readDecisions()),'approved');
  assert.equal(f.state.newRuleNotifications.length,1);
  f.learningStore.decide(r.key,'rejected');
  f.learningStore.observe(r,true);
  assert.equal(f.models.ruleState(f.learningStore.readRules()[0],f.learningStore.readDecisions()),'rejected');
});

test('manual training appends an enabled rule only after a matching click and two absent observations', async () => {
  const f=fixture();const old=f.learningStore.readRules().length;
  f.state.nodes[0].type='Text';f.learningStore.startManualLearning(HUYA);
  await f.manualWorker.scan(f.driver,HUYA);assert.equal(f.state.manualTimeout,1500);
  f.state.advance(100);
  f.state.manualCallback({bundleName:HUYA,type:'Text',text:'跳过',componentId:'huyaSkipButton',windowId:1,componentRect:BUTTON});
  f.state.nodes=[homeNode(HUYA)];
  assert.equal(await f.manualWorker.scan(f.driver,HUYA),undefined);
  f.state.advance(200);
  const r=await f.manualWorker.scan(f.driver,HUYA);assert.ok(r);
  assert.equal(r.origin,'manual');assert.equal(f.learningStore.readRules().length,old+1);
  assert.equal(f.models.ruleState(r,f.learningStore.readDecisions()),'approved');
  assert.equal(f.manualWorker.active(HUYA),false);
  assert.equal(f.state.clickCalls.length,0);
});

test('manual cancellation and leaving target cannot save delayed callbacks', async () => {
  for(const cancel of [true,false]){
    const f=fixture();f.state.nodes[0].type='Text';f.learningStore.startManualLearning(HUYA);
    await f.manualWorker.scan(f.driver,HUYA);const old=f.learningStore.readRules().length;
    if(cancel)f.learningStore.cancelManualLearning();else await f.manualWorker.scan(f.driver,HOME);
    f.state.manualCallback({bundleName:HUYA,type:'Text',text:'跳过',componentId:'huyaSkipButton',windowId:1,componentRect:BUTTON});
    f.state.nodes=[homeNode(HUYA)];
    await f.manualWorker.scan(f.driver,HUYA);await f.manualWorker.scan(f.driver,HUYA);
    assert.equal(f.learningStore.readRules().length,old);
  }
});

test('manual training expires without clicks and never issues automatic input',async()=>{
 const f=fixture();f.learningStore.startManualLearning(HUYA);await f.manualWorker.scan(f.driver,HUYA);
 f.state.advance(60001);await f.manualWorker.scan(f.driver,HUYA);
 assert.equal(f.manualWorker.active(HUYA),false);assert.equal(f.learningStore.readManualStatus().state,'expired');assert.equal(f.state.clickCalls.length,0);
});

test('single rule deletion preserves sibling rules, their approval and app settings',()=>{
 const f=fixture();const before=f.learningStore.readRules();const selected=before.find(r=>r.bundle===HUYA);
 const sibling={...selected,targetId:'anotherClose',successes:7};sibling.key=f.models.ruleKey(sibling);
 f.learningStore.saveRules([...before,sibling]);f.learningStore.decide(sibling.key,'approved');
 const settings=JSON.stringify(f.state.getSettings());f.learningStore.deleteRule(selected.key);
 const remaining=f.learningStore.readRules();assert.equal(remaining.length,before.length);assert.ok(!remaining.some(r=>r.key===selected.key));
 assert.equal(remaining.find(r=>r.key===sibling.key).successes,7);
 assert.equal(f.models.ruleState(remaining.find(r=>r.key===sibling.key),f.learningStore.readDecisions()),'approved');
 assert.equal(JSON.stringify(f.state.getSettings()),settings);
});
test('late saves and old observations cannot restore one deleted rule; a fresh sample needs fresh approval',()=>{
 const f=fixture();const old=f.learningStore.readRules();const rule=old.find(r=>r.bundle===HUYA);const decisions=f.learningStore.readDecisions();
 f.learningStore.deleteRule(rule.key);f.learningStore.saveRules(old);f.state.files.set(DIRECTORY+'/rule-decisions.json',JSON.stringify(decisions));
 assert.ok(!f.learningStore.readRules().some(r=>r.key===rule.key));assert.ok(!f.learningStore.readDecisions().some(d=>d.key===rule.key));
 assert.equal(f.learningStore.observe(rule),undefined);
 const deleted=JSON.parse(f.state.files.get(DIRECTORY+'/rule-deletions.json'))[rule.key];
 assert.equal(f.learningStore.observe({...rule,firstSeen:0,sampledAt:deleted-1}),undefined);
 f.state.advance(2);const fresh=f.learningStore.observe({...rule,firstSeen:0,sampledAt:deleted+1,attempts:0,successes:0});
 assert.ok(fresh.firstSeen>deleted);assert.equal(f.models.ruleState(fresh,f.learningStore.readDecisions()),'pending');
 f.learningStore.outcome(fresh.key,'success',rule.firstSeen);assert.equal(f.learningStore.readRules().find(r=>r.key===rule.key).successes,0);
});
test('deleting a rule between discovery and input cancels the pending click',async()=>{
 let f,deleted=false;
 f=fixture({apiVersion:26,onLayout(){if(!deleted&&f.state.apiCalls.filter(n=>n==='driver.dumpLayout').length===2){
  deleted=true;f.learningStore.deleteRule(f.learningStore.readRules().find(r=>r.bundle===HUYA).key);
 }}});
 assert.equal((await f.run(2)).clickCount,0);
});

test('presentation enrichment preserves historical approvals, statistics and rule identity',async()=>{
 const f=fixture({apiVersion:26}),rules=f.learningStore.readRules(),old=rules.find(r=>r.bundle===HUYA);
 old.successes=7;old.attempts=9;f.learningStore.saveRules(rules);
 const beforeDecision=JSON.stringify(f.learningStore.readDecisions());
 assert.ok(await f.driver.dumpLayout(DIRECTORY+'/profile-enrichment.json'));
 const layout=f.state.files.get(DIRECTORY+'/profile-enrichment.json');
 const c=f.learningWorker.discoverSnapshot(layout,HUYA,new f.learningWorker.ScanReport(),undefined,[old]);assert.ok(c);
 assert.ok(c.rule.profile);const stored=f.learningStore.observe(c.rule);
 assert.equal(stored.key,old.key);assert.equal(stored.firstSeen,old.firstSeen);assert.equal(stored.successes,7);assert.equal(stored.attempts,9);
 assert.equal(JSON.stringify(f.learningStore.readDecisions()),beforeDecision);assert.equal(f.models.ruleState(stored,f.learningStore.readDecisions()),'approved');
 assert.equal((await f.run(2)).clickCount,1);
});
test('corrupt presentation data cannot erase an otherwise valid approved rule',()=>{
 const f=fixture(),rules=f.learningStore.readRules(),key=rules[0].key;rules[0].profile={schema:1,strategyId:'S99',parts:[]};f.learningStore.saveRules(rules);
 const read=f.learningStore.readRules();assert.equal(read.length,rules.length);const stored=read.find(r=>r.key===key);assert.equal(stored.profile,undefined);
 assert.equal(f.models.ruleState(stored,f.learningStore.readDecisions()),'approved');
});
test('later memory-based observation cannot replace the original learning strategy',async()=>{
 const f=fixture({apiVersion:26});await f.driver.dumpLayout(DIRECTORY+'/profile-origin.json');
 const c=f.learningWorker.discoverSnapshot(f.state.files.get(DIRECTORY+'/profile-origin.json'),HUYA,new f.learningWorker.ScanReport());
 c.rule.profile.strategyId='S07';c.rule.profile.evidence=['image-ocr'];const stored=f.learningStore.observe(c.rule);
 const next=JSON.parse(JSON.stringify(stored));next.profile.strategyId='S02';next.profile.evidence=['text-countdown'];next.profile.parts[0].text='跳过 3';
 const updated=f.learningStore.observe(next);assert.equal(updated.profile.strategyId,'S07');
 assert.ok(updated.profile.evidence.includes('image-ocr'));assert.ok(updated.profile.evidence.includes('text-countdown'));
 assert.equal(updated.profile.parts[0].text,'跳过 3');assert.equal(updated.key,stored.key);
});

test('manual flow returns once with a saved result after the foreground UI opens the app', async()=>{
 const launches=[];const f=fixture({manualDelegator:{startAbility:async(want)=>launches.push(want)}});
 f.state.nodes[0].type='Text';f.learningStore.startManualLearning(HUYA);
 await f.manualWorker.scan(f.driver,HUYA);assert.equal(f.learningStore.readManualStatus().state,'listening');assert.equal(launches.length,0);
 f.state.advance(100);f.state.manualCallback({bundleName:HUYA,type:'Text',text:'跳过',componentId:'huyaSkipButton',windowId:1,componentRect:BUTTON});
 f.state.nodes=[homeNode(HUYA)];await f.manualWorker.scan(f.driver,HUYA);f.state.advance(200);await f.manualWorker.scan(f.driver,HUYA);
 assert.equal(f.learningStore.readManualStatus().state,'saved');assert.equal(launches[0].bundleName,f.models.OWN_BUNDLE);
 await f.manualWorker.scan(f.driver,HUYA);assert.equal(launches.length,1);assert.equal(f.state.clickCalls.length,0);
});
test('manual flow returns an unmappable click failure instead of waiting silently',async()=>{
 const launches=[];const f=fixture({manualDelegator:{startAbility:async(w)=>launches.push(w)}});
 f.state.nodes[0].type='Text';f.learningStore.startManualLearning(HUYA);await f.manualWorker.scan(f.driver,HUYA);
 f.state.advance(100);f.state.manualCallback({bundleName:HUYA,type:'Image',text:'',windowId:1,componentRect:{left:1,top:1,right:10,bottom:10}});await f.manualWorker.scan(f.driver,HUYA);
 const s=f.learningStore.readManualStatus();assert.equal(s.state,'failed');assert.match(s.message,/无法对应唯一/);
 assert.equal(launches.at(-1).bundleName,f.models.OWN_BUNDLE);assert.equal(f.state.clickCalls.length,0);
});
test('manual timeout does not take focus from an unrelated app and result acknowledgements persist',async()=>{
 const launches=[];const f=fixture({manualDelegator:{startAbility:async(w)=>launches.push(w)}});
 f.learningStore.startManualLearning(HUYA);await f.manualWorker.scan(f.driver,HUYA);const at=f.learningStore.readManualRequest().at;
 f.state.advance(60001);await f.manualWorker.scan(f.driver,YOUKU);assert.equal(launches.length,0);
 assert.equal(f.learningStore.manualResultAcknowledged(at),false);f.learningStore.acknowledgeManualResult(at);assert.equal(f.learningStore.manualResultAcknowledged(at),true);
});

const HEALTH_TOKEN = '1789400000000';
test('supervised recovery never clears an already requested stop', async () => {
  const f = fixture({supervisorToken: HEALTH_TOKEN, configure(s) {
    s.files.set(DIRECTORY + '/supervision-control.txt', HEALTH_TOKEN + ' active 1000\n');
    s.setSettings({...s.getSettings(), stopRequested: true});
  }});
  await f.run();
  assert.equal(f.state.getSettings().stopRequested, true);
  assert.equal(f.state.clickCalls.length, 0);
  assert.equal(f.state.apiCalls.length, 0);
});
test('stopped or superseded supervised worker cannot overwrite a new session', async () => {
  for (const control of [HEALTH_TOKEN + ' stopped 1000', '1789400000001 active 1000']) {
    const f = fixture({supervisorToken: HEALTH_TOKEN, rejectedSession: true, configure(s) {
      s.files.set(DIRECTORY + '/supervision-control.txt', control);
      s.files.set(DIRECTORY + '/debug-status.json', '{"newSession":true}');
    }});
    await f.run();
    assert.equal(f.state.files.get(DIRECTORY + '/debug-status.json'), '{"newSession":true}');
    assert.equal(f.state.apiCalls.length, 0);
    assert.equal(f.state.files.has(DIRECTORY + '/worker-health.txt'), false);
  }
});
test('revoking supervision during target lookup prevents input', async () => {
  const f = fixture({supervisorToken: HEALTH_TOKEN, configure(s) {
    s.files.set(DIRECTORY + '/supervision-control.txt', HEALTH_TOKEN + ' active 1000');
  }, onApi(name,s) {
    if (name === 'component.isClickable') s.files.set(DIRECTORY + '/supervision-control.txt', HEALTH_TOKEN + ' stopped 1000');
  }});
  await f.run(); assert.equal(f.state.clickCalls.length, 0);
});
