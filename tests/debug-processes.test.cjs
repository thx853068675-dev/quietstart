const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const out={};vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/core/DebugStore.ets','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText,{exports:out,require:()=>({})});
const row=(processId,at,result='decision',bundle='app.one')=>({processId,processStartedAt:1000,at,result,bundle,message:result==='attempt'?'发现前台至点击 1691 ms':'detail'});
test('one process keeps timestamped steps in order and uses its final outcome',()=>{
 const groups=out.groupDebugRecords([row('a',3000,'observedDismissed'),row('a',2000,'clickSent'),row('a',2000,'attempt'),row('a',1500)]);
 assert.equal(groups.length,1);assert.equal(groups[0].records.length,4);
 assert.equal(groups[0].records[1].result,'attempt');assert.equal(groups[0].records[2].result,'clickSent');
 assert.equal(groups[0].result,'observedDismissed');assert.equal(groups[0].timing,'发出点击 1.69 秒');
});
test('same app reopened and interleaved verification remain separate processes',()=>{
 const g=out.groupDebugRecords([row('first',5000,'observedDismissed'),row('second',4500),row('first',4000,'attempt')]);
 assert.equal(g.length,2);assert.equal(g.find(x=>x.id==='first:app.one').records.length,2);
});
test('legacy history merges adjacent steps but splits after completion or app switch',()=>{
 const g=out.groupDebugRecords([row('',6000),row('',5000,'decision','app.two'),row('',3000,'observedDismissed'),row('',2000,'attempt'),row('',1500)]);
 assert.equal(g.length,3);assert.equal(g.find(x=>x.result==='observedDismissed').records.length,3);
});
test('deferred writes sort by event time and preflight precedes input at the same millisecond',()=>{
 const g=out.groupDebugRecords([row('a',2000,'decision'),row('a',2200,'clickSent'),row('a',2000,'attempt'),row('a',1500)]);
 assert.equal(g.length,1);
 assert.equal(g[0].records.map(r=>r.result).join(','),'decision,decision,attempt,clickSent');
 assert.equal(g[0].result,'clickSent');
});
