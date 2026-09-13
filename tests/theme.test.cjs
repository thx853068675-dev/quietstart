const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
function load(name, mocks) {
 const exports = {};
 const code = ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/core', name + '.ets'), 'utf8'), {compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}}).outputText;
 vm.runInNewContext(code, {exports, require:n=>mocks[n], Number, JSON}); return exports;
}
function store(raw) {
 const files = new Map([['/test/settings.json', JSON.stringify(raw)]]);
 const fileIo = {OpenMode:{},readTextSync:p=>files.get(p),openSync:p=>({fd:p}),writeSync:(p,v)=>files.set(p,v),closeSync(){},renameSync:(a,b)=>{files.set(b,files.get(a));files.delete(a);}};
 return new (load('LocalStore', {'@kit.CoreFileKit':{fileIo}}).LocalStore)('/test');
}
test('existing user settings gain follow-system theme without losing app choices or notification preference',()=>{
 const s=store({enabled:true,remindersEnabled:true,packages:['com.example.saved'],ignoredPackages:['com.example.paused']});
 const v=s.readSettings(); assert.equal(v.themeMode,'system');assert.equal(v.remindersEnabled,true);
 assert.deepEqual(Array.from(v.packages),['com.example.saved']);assert.deepEqual(Array.from(v.ignoredPackages),['com.example.paused']);
});
test('explicit theme survives save and a later settings write',()=>{
 const s=store({themeMode:'dark',remindersEnabled:true});
 let v=s.readSettings(); v.learningEnabled=false;s.saveSettings(v);assert.equal(s.readSettings().themeMode,'dark');
 v=s.readSettings();v.themeMode='light';s.saveSettings(v);assert.equal(s.readSettings().themeMode,'light');
});
test('unknown and malformed theme values safely follow system',()=>{
 for(const value of [null,7,{},'BLACK','auto'])assert.equal(store({themeMode:value}).readSettings().themeMode,'system');
});
test('theme resource mode and system-bar mode agree for explicit and automatic choices',()=>{
 const ColorMode={COLOR_MODE_LIGHT:1,COLOR_MODE_DARK:0,COLOR_MODE_NOT_SET:-1};
 const t=load('Theme',{'@kit.AbilityKit':{ConfigurationConstant:{ColorMode}}});
 assert.equal(t.themeColorMode('light'),1);assert.equal(t.themeColorMode('dark'),0);assert.equal(t.themeColorMode('system'),-1);
 assert.equal(t.themeIsDark('light',0),false);assert.equal(t.themeIsDark('dark',1),true);
 assert.equal(t.themeIsDark('system',0),true);assert.equal(t.themeIsDark('system',1),false);
});

test('notification expiry migrates to five seconds, persists zero and validates custom seconds',()=>{
 for(const value of [undefined,null,-1,61,1.5,'10',{}])assert.equal(store({reminderDismissSeconds:value}).readSettings().reminderDismissSeconds,5);
 for(const value of [0,1,17,60]){
  const s=store({reminderDismissSeconds:value,themeMode:'dark',remindersEnabled:true}); const v=s.readSettings();
  s.saveSettings(v);assert.equal(s.readSettings().reminderDismissSeconds,value);assert.equal(s.readSettings().themeMode,'dark');
 }
});

test('automatic pause settings validate bounds, migrate conservatively and preserve unrelated preferences',()=>{
 const defaults=store({themeMode:'dark',reminderDismissSeconds:17}).readSettings();
 assert.equal(defaults.adFreeMinDays,1);assert.equal(defaults.adFreeCleanChecks,3);assert.equal(defaults.adFreeRecheckDays,7);
 for(const [field,min,max,fallback] of [['adFreeMinDays',1,7,1],['adFreeCleanChecks',2,20,3],['adFreeRecheckDays',1,30,7]]) {
  for(const invalid of [null,0,min-1,max+1,1.5,'3',{}])assert.equal(store({[field]:invalid}).readSettings()[field],fallback);
  for(const valid of [min,max]) {const s=store({[field]:valid,themeMode:'dark',reminderDismissSeconds:17});s.saveSettings(s.readSettings());assert.equal(s.readSettings()[field],valid);assert.equal(s.readSettings().reminderDismissSeconds,17);}
 }
});
