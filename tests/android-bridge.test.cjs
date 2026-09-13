const test=require('node:test'),assert=require('node:assert/strict'),{engine}=require('../tools/community/replay.cjs');
const bundle='com.ponyemu.main';
function layout({visible='true',rootType='android.widget.FrameLayout',hierarchy='ROOT515',host='515',focused='false'}={}){
 const child=(type,text,bounds,id='')=>({attributes:{type,text,bounds,id,visible,enabled:'true',clickable:'true',opacity:'0.000000',hostWindowId:host},children:[]});
 return {attributes:{type:'',bounds:'[0,0][1320,2120]'},children:[{attributes:{type:rootType,bundleName:bundle,hostWindowId:'515',hierarchy,visible,enabled:'true',focused,displayId:'0',bounds:'[0,117][1320,2120]',origBounds:'[0,0][1320,2120]',opacity:'0.000000'},children:[child('android.widget.TextView','跳过 3s','[1100,150][1280,220]'),child('android.widget.TextView','广告','[30,150][130,210]')]}]};
}
test('bridge exposes native text candidate and verification without OCR',()=>{
 const e=engine(),r=new e.worker.ScanReport(),t=layout(),raw=JSON.stringify(t);
 const c=e.worker.discoverSnapshot(raw,bundle,r,e.pack);assert.equal(r.readable,true);assert.ok(c);assert.equal(c.rule.bundle,bundle);
 assert.equal(e.worker.snapshotTargetState(raw,c.rule,c.adMarker,e.pack),'present');
 assert.equal(e.worker.soleVisibleAppBundle(raw),bundle);
});
for(const [name,opts] of [['hidden',{visible:'false'}],['missing bridge root',{hierarchy:''}],['native zero alpha',{rootType:'root'}],['foreign children',{host:'516'}]])test(name,()=>{
 const e=engine(),r=new e.worker.ScanReport();assert.equal(e.worker.discoverSnapshot(JSON.stringify(layout(opts)),bundle,r,e.pack),undefined);
});
function siblingLayout({disabled=false,offset=false,duplicate=false}={}){
 const t=layout(),root=t.children[0],label=root.children[0];label.attributes.clickable='false';
 const box='[1080,130][1300,240]',image={attributes:{type:'android.widget.ImageView',bounds:offset?'[900,130][1050,240]':box,visible:'true',enabled:disabled?'false':'true',clickable:'true',opacity:'0.000000',hostWindowId:'515'},children:[]};
 const overlay={attributes:{type:'android.view.ViewGroup',bounds:box,visible:'true',enabled:'false',clickable:'false',opacity:'0.000000',hostWindowId:'515'},children:[label]};
 root.children=[image,overlay,root.children[1]];if(duplicate)root.children.push(structuredClone(image));root.children=[{attributes:{type:'android.view.ViewGroup',bounds:'[0,0][1320,2120]',visible:'true',enabled:'true',clickable:'false',opacity:'0.000000',hostWindowId:'515'},children:root.children}];return t;
}
test('Android disabled label overlay links only the enabled co-located sibling image',()=>{
 const e=engine(),r=new e.worker.ScanReport(),raw=JSON.stringify(siblingLayout()),c=e.worker.discoverSnapshot(raw,bundle,r,e.pack);assert.ok(c);assert.equal(c.rule.buttonType,'android.widget.ImageView');assert.equal(e.worker.snapshotTargetState(raw,c.rule,c.adMarker,e.pack),'present');
 assert.equal(e.worker.discoverSnapshot(raw,bundle,new e.worker.ScanReport(),e.pack,[c.rule],true).approvedButton,true);
});
for(const opts of [{disabled:true},{offset:true},{duplicate:true}])test('reject unsafe sibling '+JSON.stringify(opts),()=>{
 const e=engine();assert.equal(e.worker.discoverSnapshot(JSON.stringify(siblingLayout(opts)),bundle,new e.worker.ScanReport(),e.pack),undefined);
});
