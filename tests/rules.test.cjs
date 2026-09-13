const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
function load(relative, mocks = {}) {
  const code = ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', relative), 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const exports = {};
  vm.runInNewContext(code, { exports, require: (name) => {
    if (!(name in mocks)) throw new Error('Unexpected dependency: ' + name);
    return mocks[name];
  }, Date, setTimeout: () => 1, clearTimeout: () => {} });
  return exports;
}
const rules = load('core/Rules.ets');

test('recognizes skip labels including countdown, without accepting unrelated actions', () => {
  for (const label of ['跳过', '跳过广告', '跳过 5s', '5秒跳过', 'Skip ad', '跳过（3秒）']) assert.equal(rules.isSkipLabel(label), true, label);
  for (const label of ['跳过登录', '跳过验证', '跳过支付', '跳过广告并领取奖励', '不可跳过', '跳过此步骤', '关闭', '立即购买']) assert.equal(rules.isSkipLabel(label), false, label);
});
test('accepts relative top-right position across portrait and folded-screen sizes', () => {
  for (const [width, height] of [[1080, 2340], [2120, 1320], [500, 500]]) {
    assert.equal(rules.isSafePosition({ left: width * .8, top: height * .04, width: width * .15, height: height * .06 }, { left: 0, top: 0, width, height }), true);
  }
});
test('rejects bottom, left, invisible-sized and oversized targets', () => {
  const screen = { left: 0, top: 0, width: 1000, height: 2000 };
  for (const button of [
    { left: 800, top: 1500, width: 150, height: 80 },
    { left: 20, top: 30, width: 100, height: 70 },
    { left: 800, top: 30, width: 0, height: 70 },
    { left: 500, top: 30, width: 500, height: 70 },
    { left: 980, top: 30, width: 100, height: 70 }
  ]) assert.equal(rules.isSafePosition(button, screen), false);
});
test('normalizes package whitelist and excludes invalid entries', () => {
  assert.equal(rules.parsePackages('com.example.app\ncom.example.app，bad name;com.example.two').join(','), 'com.example.app,com.example.two');
});

class FakeStore {
  readSettings() { return this.settings; }
  readStatus() { return { connected: false, history: [], clickCount: 0, message: '', lastExternalBundle: '' }; }
  saveStatus(value) { this.status = value; }
}
const Service = load('service/SkipService.ets', {
  '@ohos.application.AccessibilityExtensionAbility': { default: class {} },
  '@kit.PerformanceAnalysisKit': { hilog: { info() {} } },
  '../core/LocalStore': { LocalStore: FakeStore, ServiceStatus: class { history=[]; clickCount=0; message=''; } },
  '../core/Rules': rules
}).default;
function scenario({ label = '跳过5s', marker = false, enabled = true, allowed = true, visible = true, changesApp = false, disables = false } = {}) {
  let clicks = 0;
  let roots = 0;
  const bundle = 'com.example.target';
  const store = new FakeStore();
  store.settings = { enabled, packages: allowed ? [bundle] : [], testUntil: 0 };
  const candidate = {
    async attributeValue(key) {
      return { bundleName: bundle, text: label, accessibilityText: '', clickable: true, isVisible: visible, isEnable: true,
        screenRect: { left: 800, top: 30, width: 150, height: 80 } }[key];
    },
    async actionNames() { if (disables) store.settings.enabled = false; return ['click']; },
    async performAction(action) { assert.equal(action, 'click'); clicks++; }
  };
  const root = {
    async attributeValue(key) {
      if (key === 'bundleName') return changesApp && roots > 1 ? 'com.example.other' : bundle;
      return { left: 0, top: 0, width: 1000, height: 2000 };
    },
    async findElement(_, value) {
      if (value === '跳过') return [candidate];
      if (value === '广告' && marker) return [{ async attributeValue(key) { return { bundleName: bundle, isVisible: true, text: '广告' }[key]; } }];
      return [];
    }
  };
  const service = new Service();
  service.alive = true; service.store = store;
  service.context = { async getWindowRootElement() { roots++; return root; } };
  return { service, clicks: () => clicks };
}
test('dispatches at most one click during a foreground session, including concurrent events', async () => {
  const s = scenario();
  await Promise.all([s.service.scan(), s.service.scan()]);
  await s.service.scan();
  assert.equal(s.clicks(), 1);
});
test('never clicks disabled, non-whitelisted, invisible or changed-foreground targets', async () => {
  for (const config of [{ enabled: false }, { allowed: false }, { visible: false }, { changesApp: true }, { disables: true }]) {
    const s = scenario(config); await s.service.scan(); assert.equal(s.clicks(), 0, JSON.stringify(config));
  }
});
test('plain skip requires an ad marker so onboarding skip is ignored', async () => {
  const onboarding = scenario({ label: '跳过' }); await onboarding.service.scan(); assert.equal(onboarding.clicks(), 0);
  const ad = scenario({ label: '跳过', marker: true }); await ad.service.scan(); assert.equal(ad.clicks(), 1);
});
test('does not click after the startup time window', async () => {
  const s = scenario(); s.service.activeBundle = 'com.example.target'; s.service.windowStarted = Date.now() - 9000;
  await s.service.scan(); assert.equal(s.clicks(), 0);
});
