const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
function load(name, dependencies) {
  const exports = {};
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/core', name + '.ets'), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 } }).outputText,
    { exports, require: name => { assert.ok(Object.hasOwn(dependencies, name), name); return dependencies[name]; } });
  return exports;
}
const learning = load('LearningStore', { '@kit.CoreFileKit': { fileIo: {} } });
const { appGroup } = load('AppGrouping', { './LearningStore': learning });
const APP = 'com.example.music';
const rule = { key: 'one', bundle: APP, firstSeen: 50, suspendedAt: 0 };
const approval = { key: 'one', templateAt: 50, state: 'approved', at: 80 };
function group(options = {}) {
  return appGroup(APP, options.allowed ?? [APP], options.ignored ?? [], options.rules ?? [],
    options.decisions ?? [], options.quiet ?? [], options.automatic ?? true, options.now ?? 1000);
}
const quiet = [{ bundle: APP, updatedAt: 100, pausedUntil: 2000 }];
test('selected apps with no rule, pending rule, rejected rule or stale approval stay under observation', () => {
  assert.equal(group(), 1);
  assert.equal(group({ rules: [rule] }), 1);
  assert.equal(group({ rules: [rule], decisions: [{ ...approval, state: 'rejected' }] }), 1);
  assert.equal(group({ rules: [{ ...rule, firstSeen: 90 }], decisions: [approval] }), 1);
});
test('automatic skipping requires both per-app selection and a currently approved rule', () => {
  assert.equal(group({ rules: [rule], decisions: [approval] }), 0);
  assert.equal(group({ rules: [rule], decisions: [approval], allowed: [] }), 1);
});
test('one enabled rule is sufficient; suspended rules alone need review', () => {
  assert.equal(group({ rules: [{ ...rule, suspendedAt: 100 }], decisions: [approval] }), 1);
  assert.equal(group({ rules: [rule, { ...rule, key: 'two' }], decisions: [approval] }), 0);
});
test('manual pause overrides both enabled rules and automatic pause', () => {
  assert.equal(group({ rules: [rule], decisions: [approval], ignored: [APP] }), 2);
  assert.equal(group({ ignored: [APP], quiet, automatic: false }), 2);
});
test('unexpired automatic pause is its own app group only without saved rules', () => {
  assert.equal(group({ quiet }), 2);
  assert.equal(group({ quiet, rules: [rule] }), 1);
  assert.equal(group({ quiet, rules: [rule], decisions: [approval] }), 0);
});
test('expired, future-dated, or disabled automatic pauses return to observation', () => {
  assert.equal(group({ quiet, now: 2000 }), 1);
  assert.equal(group({ quiet, now: 50 }), 1);
  assert.equal(group({ quiet, automatic: false }), 1);
});
test('other apps rules cannot grant automatic skipping', () => {
  assert.equal(group({ rules: [{ ...rule, bundle: 'com.other.app' }], decisions: [approval] }), 1);
});
