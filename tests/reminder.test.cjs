const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
function fixture(options = {}) {
  const files = new Map(), calls = [];
  const settings = { remindersEnabled: options.enabled === true, reminderDismissSeconds: options.seconds ?? 5,
    newRuleRemindersEnabled: options.learnedEnabled === true };
  let now = 100000;
  const fileIo = { OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    readTextSync: p => { if (!files.has(p)) throw Error('missing'); return files.get(p); },
    openSync: p => ({ fd: p }), writeSync: (p, s) => files.set(p, s), closeSync() {},
    renameSync: (a, b) => { files.set(b, files.get(a)); files.delete(a); } };
  const mocks = {
    '@kit.CoreFileKit': { fileIo },
    '@kit.AbilityKit': { wantAgent: { OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 },
      getWantAgent: async request => {
        assert.equal(request.wants[0].bundleName, 'com.tonghongxiang.quietstart');
        const learned = request.requestCode === 70603;
        assert.equal(request.wants[0].parameters[learned ? 'quietstartOpenRules' : 'quietstartOpenRecords'], true);
        if (options.onAction) await options.onAction(settings);
        return { action: learned ? 'open-rules' : 'open-records' };
      } } },
    '@kit.NotificationKit': { notificationManager: {
      SlotType: { SERVICE_INFORMATION: 2 }, ContentType: { NOTIFICATION_CONTENT_BASIC_TEXT: 0 },
      isNotificationEnabled: async () => { if (options.disableDuringCheck) settings.remindersEnabled = false; return options.permission !== false; },
      getActiveNotifications: async () => options.active ?? [],
      getNotificationSetting: async () => { if (options.settingsError) throw Error('settings'); return { bannerEnabled: options.banner !== false }; },
      publish: async r => { calls.push(['publish', r]); if (options.onPublish) await options.onPublish(settings); if (options.disableDuringPublish) settings.remindersEnabled = false; if (options.publishError) throw { code: 1600001 }; },
      cancel: async id => calls.push(['cancel', id])
    } },
    './LocalStore': { LocalStore: class { readSettings() { return settings; } } }
  };
  const exports = {};
  const code = ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/core/SkipReminder.ets'), 'utf8'),
    { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
  vm.runInNewContext(code, { exports, require: name => { assert.ok(mocks[name], name); return mocks[name]; }, Date: class extends Date { static now() { return now; } } });
  return { service: new exports.SkipReminder('/test'), restart: () => new exports.SkipReminder('/test'), files, settings, calls, published: () => calls.filter(c => c[0] === 'publish').map(c => c[1]), advance(ms) { now += ms; } };
}
test('disabled reminders publish nothing but confirmed successes still count', async () => {
  const f = fixture(); await f.service.show('测试应用'); assert.equal(f.calls.length, 0);
  f.settings.remindersEnabled = true; await f.service.show('B');
  assert.match(f.published()[0].content.normal.title, /2 次/);
});
test('permission denial keeps the count and provides a direct instruction', async () => {
  const f = fixture({ enabled: true, permission: false }); await f.service.show('测试应用');
  assert.equal(f.calls.length, 0); assert.equal(f.service.read().mode, 'permission');
  assert.equal(JSON.parse(f.files.get('/test/reminder-totals.json')).count, 1);
});
test('notification is silent, removable, self-expiring and opens records', async () => {
  const f = fixture({ enabled: true }); await f.service.show('测试应用'); const r = f.published()[0];
  assert.equal(r.content.normal.title, '已为你跳过 1 次'); assert.match(r.content.normal.text, /最近：测试应用/);
  assert.equal(r.notificationFlags.soundEnabled, 2); assert.equal(r.notificationFlags.vibrationEnabled, 2);
  assert.equal(r.notificationFlags.lockScreenEnabled, 2); assert.equal(r.tapDismissed, true);
  assert.equal(r.wantAgent.action, 'open-records'); assert.equal(r.autoDeletedTime, 105000);
  assert.equal(r.isAlertOnce, true); assert.equal(f.service.read().mode, 'notification');
});
test('all updates and previews use one id; rapid same-app successes count and previews do not', async () => {
  const f = fixture({ enabled: true }); await f.service.show('A'); await f.service.show('A');
  await f.service.show('B'); await f.service.show('B', true); await f.service.show('C');
  const sent = f.published(); assert.equal(sent.length, 5); assert.equal(new Set(sent.map(r => r.id)).size, 1);
  assert.match(sent[1].content.normal.title, /2 次/); assert.match(sent[2].content.normal.title, /3 次/);
  assert.equal(sent[3].content.normal.title, '跳过提醒 · 预览'); assert.match(sent[4].content.normal.title, /4 次/);
});
test('custom duration renews from each update; no-auto-dismiss uses the documented zero timestamp', async () => {
  const f = fixture({ enabled: true, seconds: 17 }); await f.service.show('A'); assert.equal(f.published()[0].autoDeletedTime, 117000);
  f.advance(1000); await f.service.show('B'); assert.equal(f.published()[1].autoDeletedTime, 118000);
  f.settings.reminderDismissSeconds = 0; await f.service.show('C'); assert.equal(f.published()[2].autoDeletedTime, 0);
  assert.match(f.service.read().message, /不自动收起/);
});
test('count survives new instances, manual notification clearing and failed publications', async () => {
  const f = fixture({ enabled: true }); await f.service.show('A'); await f.service.clear();
  await f.restart().show('B'); assert.match(f.published().at(-1).content.normal.title, /2 次/);
  const error = fixture({ enabled: true, publishError: true }); await error.service.show('A');
  assert.equal(error.service.read().errorCode, 1600001); assert.equal(JSON.parse(error.files.get('/test/reminder-totals.json')).count, 1);
});
test('a success arriving during publish is counted and eventually reflected by the same notification', async () => {
  let called = false, f;
  f = fixture({ enabled: true, onAction: async () => { if (!called) { called = true; await f.service.show('B'); } } });
  await f.service.show('A'); assert.match(f.published().at(-1).content.normal.title, /2 次/);
  assert.match(f.published().at(-1).content.normal.text, /最近：B/);
  assert.equal(new Set(f.published().map(r => r.id)).size, 1);
});
test('changing settings updates an existing notification without adding counts or resurrecting a cleared one', async () => {
  const f = fixture({ enabled: true, active: [{ id: 70601 }] }); await f.service.show('A');
  f.settings.reminderDismissSeconds = 0; await f.service.refreshVisible();
  assert.equal(f.published().at(-1).autoDeletedTime, 0); assert.match(f.published().at(-1).content.normal.title, /1 次/);
  const cleared = fixture({ enabled: true }); await cleared.service.refreshVisible(); assert.equal(cleared.published().length, 0);
});
test('preview-only notifications never invent confirmed successes', async () => {
  const f = fixture({ enabled: true, seconds: 0 }); await f.service.show('A', true); await f.service.show('A', true);
  assert.equal(f.files.has('/test/reminder-totals.json'), false); assert.equal(f.published().length, 2);
});
test('preview reports system banner setting and tolerates setting-query failure', async () => {
  const f = fixture({ enabled: true, banner: false }); await f.service.show('应用', true);
  assert.match(f.service.read().message, /横幅已关闭/);
  const g = fixture({ enabled: true, settingsError: true }); await g.service.show('应用', true); assert.equal(g.service.read().mode, 'notification');
});
test('disable races prevent publication or retract the in-flight publication', async () => {
  for (const options of [{ disableDuringCheck: true }, { onAction: async s => { s.remindersEnabled = false; } }]) {
    const f = fixture({ enabled: true, ...options }); await f.service.show('应用'); assert.equal(f.published().length, 0);
  }
  const f = fixture({ enabled: true, disableDuringPublish: true }); await f.service.show('应用');
  assert.deepEqual(f.calls.at(-1), ['cancel', 70601]);
});
test('clear retracts the current and legacy preview notifications without resetting totals', async () => {
  const f = fixture({ enabled: true }); await f.service.show('A'); await f.service.clear();
  assert.deepEqual(f.calls.slice(-2), [['cancel', 70601], ['cancel', 70602]]);
  assert.equal(JSON.parse(f.files.get('/test/reminder-totals.json')).count, 1);
});

test('duration changes during publication eventually update the same notification without a new count', async () => {
 let changed=false;
 const f=fixture({enabled:true,onPublish:async s=>{if(!changed){changed=true;s.reminderDismissSeconds=0;}}});
 await f.service.show('A');assert.equal(f.published().at(-1).autoDeletedTime,0);
 assert.match(f.published().at(-1).content.normal.title,/1 次/);
});
test('learned rule notifications use a separate fixed ID and never increment skip totals',async()=>{
 const f=fixture({learnedEnabled:true,seconds:10});await f.service.showLearned('A',false);await f.service.showLearned('B',true);
 assert.equal(f.published().length,2);assert.ok(f.published().every(r=>r.id===70603));
 assert.equal(f.published()[0].wantAgent.action,'open-rules');assert.equal(f.published()[0].autoDeletedTime,110000);
 assert.match(f.published()[0].content.normal.text,/等待确认/);assert.match(f.published()[1].content.normal.text,/已启用/);
 assert.equal(f.files.has('/test/reminder-totals.json'),false);
 assert.equal(f.published()[0].notificationFlags.soundEnabled,2);
});
test('learned notifications respect permission and disable before or during publication',async()=>{
 for(const options of [{},{learnedEnabled:true,permission:false},{learnedEnabled:true,onAction:s=>{s.newRuleRemindersEnabled=false;}}]){
  const f=fixture(options);await f.service.showLearned('A',true);assert.equal(f.published().length,0);
 }
 const f=fixture({learnedEnabled:true,onPublish:s=>{s.newRuleRemindersEnabled=false;}});await f.service.showLearned('A',true);
 assert.deepEqual(f.calls.at(-1),['cancel',70603]);
});
