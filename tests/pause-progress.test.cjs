const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const out={};vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/core/PauseProgress.ets','utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}}).outputText,{exports:out,require:()=>({CLEAN_GAP_MS:1800000})});
const day=86400000,base=100000000;
test('no observation starts the time span only after first complete check',()=>{
 const p=out.pauseProgress(undefined,2,7,base);assert.equal(p.progress,'有效检查 0/7 次');assert.match(p.remaining,/7 次.*首次有效检查后观察 2 天/);
});
test('remaining counts and time use current thresholds',()=>{
 const p=out.pauseProgress({cleanLaunches:2,firstCleanAt:base,lastCleanAt:base},1,5,base+6*3600000);
 assert.match(p.progress,/2\/5/);assert.match(p.remaining,/3 次.*18 小时/);
});
test('elapsed time does not mean automatic admission without another complete check',()=>{
 const p=out.pauseProgress({cleanLaunches:5,firstCleanAt:base,lastCleanAt:base+day-1000},1,5,base+day+1);
 assert.match(p.progress,/时长已满/);assert.match(p.remaining,/1 次完整检查确认.*30 分钟后/);
});
test('satisfied thresholds still require a current check and never show negative remainder',()=>{
 const p=out.pauseProgress({cleanLaunches:9,firstCleanAt:base,lastCleanAt:base+day},1,3,base+2*day);
 assert.equal(p.progress,'有效检查 3/3 次 · 时长已满');assert.match(p.remaining,/1 次完整检查确认.*下次打开/);assert.ok(!p.remaining.includes('-'));
});
