const assert=require('node:assert/strict');
const test=require('node:test');
const {convert,engine,read,replay}=require('../tools/community/replay.cjs');
const {cases}=require('../tools/community/cases.cjs');
const runtime=engine();
for(const id of ['13160866','13379565']) {
  test(`community ${id}: checksum, reference annotation and raw states remain intact`,()=>{
    const {snapshot,meta}=read(id);const saved=JSON.stringify(snapshot);const result=convert(snapshot);
    assert.equal(JSON.stringify(snapshot),saved);
    assert.equal(result.missing.enabled,snapshot.nodes.length);
    const target=snapshot.nodes.find(n=>n.id===meta.expectedTargetNodeId);
    assert.equal(target.attr.name,'android.widget.LinearLayout');
    assert.ok(snapshot.nodes.some(n=>n.pid===target.id&&n.attr.text==='关闭'&&n.attr.visibleToUser===true));
    assert.ok(result.assumptions.length);
    const flat=[];function walk(n){flat.push(n);n.children.forEach(walk);}result.tree.children.forEach(walk);
    for(const node of flat) {
      assert.equal(Object.hasOwn(node.attributes,'enabled'),false);
      assert.equal(node.attributes.visible,String(snapshot.nodes.find(n=>n.id===node.sourceNodeId).attr.visibleToUser));
    }
  });
  for(const c of cases(id)) test(`community ${id}/${c.name}: ${c.expected}`,()=>{
    const r=replay(runtime,c.snapshot,c.meta,c.name,c.expected==='correct-rejection');
    assert.equal(r.classification,c.expected,r.reason);
    assert.ok(r.reason.includes(c.reason),r.reason);
    if(c.provenance==='community-original') assert.equal(r.classification,'insufficient-data');
  });
}
const fixture=()=>({appId:'com.example.test',screenWidth:1000,screenHeight:2000,nodes:[
  {id:0,pid:-1,attr:{name:'View',left:10,top:20,right:0,bottom:40,visibleToUser:false,clickable:false,enabled:false}}
]});
test('converter keeps false states and invalid geometry, without manufacturing a clickable target',()=>{
  const a=convert(fixture()).tree.children[0].attributes;
  assert.equal(a.enabled,'false');assert.equal(a.visible,'false');assert.equal(a.clickable,'false');
  assert.equal(a.bounds,'[10,20][0,40]');
});
for(const kind of ['duplicate','orphan','cycle','conflicting-flags']) test(`converter rejects ${kind}`,()=>{
  const s=fixture();
  if(kind==='duplicate')s.nodes.push({...s.nodes[0]});
  if(kind==='orphan')s.nodes[0].pid=10;
  if(kind==='cycle')s.nodes[0].pid=0;
  if(kind==='conflicting-flags')s.nodes[0].attr.isClickable=true;
  assert.throws(()=>convert(s));
});
test('wrong target is recorded separately instead of counting any discovered candidate as success',()=>{
  const c=cases('13160866').find(c=>c.name==='isolated');
  const r=replay(runtime,c.snapshot,{...c.meta,expectedTargetNodeId:216});
  assert.equal(r.classification,'wrong-target');
});

for(const id of require('../tools/community/cases.cjs').SAMPLE_IDS.slice(2)) {
 test(`expanded community ${id}: independent source annotation`,()=>{
  const {snapshot,meta}=read(id);const target=snapshot.nodes.find(n=>n.id===meta.expectedTargetNodeId);assert.ok(target);
  if(snapshot.appId==='com.zhihu.android')assert.equal(target.attr.id,'com.zhihu.android:id/btn_skip');
  else {assert.match(target.attr.id,/close/);assert.ok(snapshot.nodes.some(n=>n.pid===target.id&&(n.attr.text||'').includes('跳过')));}
 });
 for(const c of cases(id))test(`expanded community ${id}/${c.name}`,()=>{
  const r=replay(runtime,c.snapshot,c.meta,c.name);
  assert.equal(r.classification,c.expected,r.reason);assert.ok(r.reason.includes(c.reason));
 });
}
