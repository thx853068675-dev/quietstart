const assert=require('node:assert/strict');
const test=require('node:test');
const fs=require('node:fs');
const path=require('node:path');
const {engine}=require('../tools/community/replay.cjs');
const {worker}=engine();
function tree(name='qq') {return JSON.parse(fs.readFileSync(path.join(__dirname,'fixtures',`${name}-splash-065.json`)));}
function nodes(tree) {const out=[];function walk(n){out.push(n);(n.children||[]).forEach(walk);}walk(tree);return out;}
function scan(t,name='qq'){const report=new worker.ScanReport();const result=worker.discoverSnapshot(JSON.stringify(t),name==='qq'?'com.tencent.hm.qqmusic':'com.lucky.luckincoffee',report);return {report,result};}
for(const name of ['qq','luckin']) {
 test(`HarmonyOS ${name}: non-interactive upper image no longer blocks the actual button`,()=>{
  const t=tree(name);const expected=scan(t,name).result;assert.ok(expected);
  const bg=nodes(t).find(n=>n.attributes.type==='Image'&&n.attributes.clickable==='true');
  bg.attributes.zIndex='999';bg.attributes.hitTestBehavior='HitTestMode.None';
  assert.deepEqual(scan(t,name).result.bounds,expected.bounds);
 });
 for(const mode of ['HitTestMode.Default','HitTestMode.Transparent','HitTestMode.Block','UNKNOWN']) test(`HarmonyOS ${name}: ${mode} upper overlay remains blocked`,()=>{
  const t=tree(name);const bg=nodes(t).find(n=>n.attributes.type==='Image'&&n.attributes.clickable==='true');
  bg.attributes.zIndex='999';bg.attributes.hitTestBehavior=mode;
  assert.equal(scan(t,name).result,undefined);
 });
}
test('None parent does not exempt its clickable child from occlusion checks',()=>{
 const t=tree();const match=scan(t).result;
 const bg=nodes(t).find(n=>n.attributes.type==='Image'&&n.attributes.clickable==='true');
 bg.attributes.zIndex='999';bg.attributes.hitTestBehavior='HitTestMode.None';
 bg.children=[{attributes:{...bg.attributes,id:'buy-overlay',text:'购买',hitTestBehavior:'HitTestMode.Default',
 bounds:`[${match.bounds.left},${match.bounds.top}][${match.bounds.right},${match.bounds.bottom}]`},children:[]}];
 assert.equal(scan(t).result,undefined);
});
test('Block overlay remains an occluder even without a clickable handler',()=>{
 const t=tree();const bg=nodes(t).find(n=>n.attributes.type==='Image'&&n.attributes.clickable==='true');
 bg.attributes.zIndex='999';bg.attributes.hitTestBehavior='HitTestMode.Block';bg.attributes.clickable='false';
 assert.equal(scan(t).result,undefined);
});
test('a target with None hit testing cannot itself become the click target',()=>{
 const t=tree();const all=nodes(t);
 for(const n of all)if(n.attributes.clickable==='true')n.attributes.hitTestBehavior='HitTestMode.None';
 assert.equal(scan(t).result,undefined);
});
for(const name of ['qq','luckin']) test(`HarmonyOS ${name}: distant reused ID does not suppress a unique real target`,()=>{
 const t=tree(name);const original=scan(t,name).result;assert.ok(original);
 const b=original.bounds;const bounds=`[${b.left},${b.top}][${b.right},${b.bottom}]`;
 const target=nodes(t).find(n=>n.attributes.clickable==='true'&&n.attributes.bounds===bounds);assert.ok(target);
 target.attributes.id='shared_sdk_control';
 t.children.push({attributes:{id:'shared_sdk_control',text:'更多内容',type:'Button',clickable:'true',enabled:'true',visible:'true',
  bounds:'[100,900][220,980]',zIndex:'0'},children:[]});
 const actual=scan(t,name);assert.ok(actual.result,actual.report.reason);assert.deepEqual(actual.result.bounds,b);
});
