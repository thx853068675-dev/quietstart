const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const {worker}=require('../tools/community/replay.cjs').engine();
function tree(){return JSON.parse(fs.readFileSync(__dirname+'/fixtures/hupu-splash-0910.json','utf8'));}
function walk(t){const out=[];function w(n){out.push(n);(n.children||[]).forEach(w);} (Array.isArray(t)?t:[t]).forEach(w);return out;}
function run(t,collect=true){const report=new worker.ScanReport();report.collectTrace=collect;return {candidate:worker.discoverSnapshot(JSON.stringify(t),'com.hupu.heroes',report),report};}
test('captured Hupu explicit ad style remains recognized',()=>{assert.ok(run(tree()).candidate);});
test('missing evidence remains rejected, with bounded diagnostic when requested',()=>{
 const t=tree();for(const n of walk(t)){if(n.attributes.text==='跳过广告'){n.attributes.text='关闭';n.attributes.originalText='关闭';}}
 const {candidate,report}=run(t);assert.equal(candidate,undefined);assert.match(report.reason,/未生成新规则/);
 const trace=JSON.parse(report.candidateTrace);assert.ok(trace.nodes.length>0&&trace.nodes.length<=24);assert.ok(report.candidateTrace.length<16384);
 assert.equal(run(t,false).report.candidateTrace,'');
});
test('trace omits arbitrary text, descriptions, ids and image URLs',()=>{
 const t=tree();for(const n of walk(t)){if(n.attributes.text==='跳过广告'){
 n.attributes.text='关闭';n.attributes.originalText='关闭';n.attributes.id='private-account-123';
 n.attributes.description='私有账户资料';n.attributes.backgroundImage='https://private.example/image';
 }}
 const trace=run(t).report.candidateTrace;assert.ok(trace);assert.doesNotMatch(trace,/私有|private|https|originalText|backgroundImage/);
});
