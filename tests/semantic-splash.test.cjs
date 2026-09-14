const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {engine}=require('../tools/community/replay.cjs');
const e=engine(),bundle='com.douyu.ho.app';
const tree=()=>JSON.parse(fs.readFileSync(__dirname+'/fixtures/semantic-splash-0943.json','utf8'));
const all=t=>[t,...(t.children||[]).flatMap(all)];
const label=t=>all(t).find(n=>n.attributes.text==='跳过4');
const parent=(t,n)=>all(t).find(p=>(p.children||[]).includes(n));
function scan(t,approved=[],only=false){const report=new e.worker.ScanReport();return {report,c:e.worker.discoverSnapshot(JSON.stringify(t),bundle,report,e.pack,approved,only)};}
test('real semantic splash is learned and survives dynamic ID/countdown changes',()=>{
 const t=tree(),{c,report}=scan(t);assert.ok(c,report.reason);assert.equal(c.rule.recognition,'semantic');assert.equal(c.rule.targetId,'');assert.equal(c.approvedButton,false);
 const n=label(t);n.attributes.text='跳过';n.attributes.id='999999';
 for(const x of all(t))if(x.attributes.text==='广告')x.attributes.text='';
 const fresh=scan(t,[c.rule],true).c;assert.ok(fresh);assert.equal(fresh.approvedButton,true);assert.equal(fresh.rule.key,c.rule.key);
 assert.equal(e.worker.snapshotTargetState(JSON.stringify(t),c.rule,c.adMarker,e.pack),'present');
});
test('never treats a pending rule as approved in selected-only preflight',()=>{assert.equal(scan(tree(),[],true).c,undefined);});
for(const [name,change] of [
 ['missing evidence',t=>{label(t).attributes.text='跳过广告';all(t).forEach(n=>{if(n.attributes.text==='广告')n.attributes.text='';});}],
 ['disabled',t=>{label(t).attributes.enabled='false';}],
 ['hidden',t=>{label(t).attributes.visible='false';}],
 ['missing clickable',t=>{delete label(t).attributes.clickable;}],
 ['all no hit testing',t=>{label(t).attributes.hitTestBehavior='HitTestMode.None';parent(t,label(t)).attributes.hitTestBehavior='HitTestMode.None';}],

 ['large parent',t=>{parent(t,label(t)).attributes.bounds='[0,0][1320,2120]';}],
 ['purchase text',t=>{label(t).attributes.text='购买';}],
 ['foreign owner',t=>{label(t).attributes.bundleName='com.other.app';}],
 ['disabled parent',t=>{parent(t,label(t)).attributes.enabled='false';}],
 ['ambiguous targets',t=>{const n=label(t),p=parent(t,n),g=parent(t,p);const clone=structuredClone(p);clone.children[0].attributes.id='999888';g.children.push(clone);}],
 ['blocking overlay',t=>{const n=label(t),p=parent(t,n);p.children.push({attributes:{...n.attributes,text:'',type:'Image',bounds:n.attributes.bounds,hitTestBehavior:'HitTestMode.Block',zIndex:'999'},children:[]});}],
 ['interactive sibling',t=>{const n=label(t);parent(t,n).children.push({attributes:{...n.attributes,text:'购买',clickable:'true'},children:[]});}]
])test('reject '+name+' in discovery and approved preflight',()=>{const t=tree(),approved=scan(t).c.rule;change(t);assert.equal(scan(t).c,undefined);assert.equal(scan(t,[approved],true).c,undefined);});
test('approved target moves or changes type: preflight refuses',()=>{for(const patch of [{bounds:'[900,168][993,216]'},{type:'Image'}]){const t=tree(),a=scan(t).c.rule;Object.assign(label(t).attributes,patch);assert.equal(scan(t,[a],true).c,undefined);}});
test('not tied to Douyu package or numeric identifier',()=>{const t=tree();all(t).forEach(n=>{if(n.attributes.bundleName===bundle)n.attributes.bundleName='com.example.splash';});const c=e.worker.discoverSnapshot(JSON.stringify(t),'com.example.splash',new e.worker.ScanReport(),e.pack);assert.ok(c);});
