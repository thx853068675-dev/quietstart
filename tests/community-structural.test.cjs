const test=require('node:test'),assert=require('node:assert/strict');
const {engine}=require('../tools/community/replay.cjs');
const {IDS,prepared,evaluate}=require('../tools/community/structural-cases.cjs');const runtime=engine();
function all(tree){const a=[];function walk(n){a.push(n);n.children.forEach(walk)}walk(tree);return a;}
function discover(c,rules=[]){return runtime.worker.discoverSnapshot(JSON.stringify(c.tree),c.snapshot.appId,new runtime.worker.ScanReport(),runtime.pack,rules,rules.length>0);}
for(const id of IDS){
 test(`${id}: original never invents missing permission state`,()=>assert.equal(evaluate(runtime,id,'original').classification,'insufficient-data'));
 test(`${id}: separate enabled-state experiment`,()=>assert.equal(evaluate(runtime,id,'enabled-assumed').classification,['12620583','12621953','12775918','12775919'].includes(id)?'correct-target':'miss'));
 test(`${id}: explicit enabled and layer assumptions`,()=>assert.equal(evaluate(runtime,id,'enabled-and-z-assumed').classification,id==='13468987'?'miss':'correct-target'));
}
for(const id of ['12620583','12621953','13842826','13939089','12775919','13538616']){
 test(`${id}: enabled local structural rule rechecks its button without original evidence`,()=>{
  const c=prepared(id,'enabled-and-z-assumed'),first=discover(c);assert.ok(first);assert.equal(first.rule.labelSource,'structure');
  for(const n of all(c.tree))if(n.sourceNodeId!==c.meta.expectedTargetNodeId){n.attributes.text='';n.attributes.description='';n.attributes.id='';}
  const fresh=discover(c,[first.rule]);assert.ok(fresh);assert.equal(fresh.approvedButton,true);
  const target=all(c.tree).find(n=>n.sourceNodeId===c.meta.expectedTargetNodeId);target.attributes.text='立即购买';
  assert.equal(discover(c,[first.rule]),undefined);
 });
}
for(const id of ['13842826','13939089','12775919','13538616'])for(const mutation of ['hidden','disabled','large','foreign','no-context','duplicate']){
 test(`${id}: rejects ${mutation} structure`,()=>{
  const c=prepared(id,'enabled-and-z-assumed'),flat=all(c.tree),target=flat.find(n=>n.sourceNodeId===c.meta.expectedTargetNodeId);
  if(mutation==='hidden')target.attributes.visible='false';
  if(mutation==='disabled')target.attributes.enabled='false';
  if(mutation==='large')target.attributes.bounds=`[0,0][${c.snapshot.screenWidth},${c.snapshot.screenHeight}]`;
  if(mutation==='foreign')target.attributes.bundleName='com.other.app';
  if(mutation==='no-context')for(const n of flat){n.attributes.id='';n.attributes.text='';n.attributes.description='';}
  if(mutation==='duplicate'){
   const parent=flat.find(n=>n.children.includes(target)),copy=JSON.parse(JSON.stringify(target));copy.sourceNodeId=999999;
   // A second candidate in the same region must not be arbitrarily chosen.
   parent.children.push(copy);
  }
  assert.equal(discover(c),undefined);
 });
}
for(const id of ['13842826','13939089','12775919','13538616'])test(`${id}: no application-name special case and left-right mirror`,()=>{
 const c=prepared(id,'enabled-and-z-assumed');c.snapshot.appId='com.example.newapp';c.tree.attributes.bundleName=c.snapshot.appId;
 for(const n of all(c.tree)){
  if(n.attributes.id)n.attributes.id=n.attributes.id.replace(/^[^:]+:/,'com.example.newapp:');
  if(n!==c.tree&&n.attributes.bounds){const b=n.attributes.bounds.match(/\d+/g).map(Number);n.attributes.bounds=`[${c.snapshot.screenWidth-b[2]},${b[1]}][${c.snapshot.screenWidth-b[0]},${b[3]}]`;}
 }
 assert.ok(discover(c));
});
test('anonymous structural target disabling itself is still present, not a false disappearance',()=>{
 const c=prepared('13939089','enabled-and-z-assumed');const candidate=discover(c);assert.ok(candidate);
 const target=all(c.tree).find(n=>n.sourceNodeId===c.meta.expectedTargetNodeId);target.attributes.clickable='false';target.attributes.enabled='false';
 assert.equal(runtime.worker.snapshotTargetState(JSON.stringify(c.tree),candidate.rule,undefined,runtime.pack),'present');
});
