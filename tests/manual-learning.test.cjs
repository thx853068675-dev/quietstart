const test=require('node:test');const assert=require('node:assert/strict');const fs=require('fs');
const {worker}=require('../tools/community/replay.cjs').engine();
const inputs=[['xiachufang','com.xiachufang.recipe',{left:1109,top:228,right:1260,bottom:306}],['jiaxiao','com.jiaxiao.driveharmony',{left:1109,top:228,right:1260,bottom:306}],['mgtv','com.mgtv.phone',{left:1145,top:141,right:1236,bottom:237}],['damai','cn.damai.hongmeng',{left:1185,top:175,right:1245,bottom:210}],['railway','com.chinarailway.ticketingHM',{left:1068,top:158,right:1212,bottom:233}]];
function tree(name){return JSON.parse(fs.readFileSync(`${__dirname}/fixtures/${name}-splash-0945.json`));}
function all(t){const out=[];const visit=n=>{out.push(n);(n.children||[]).forEach(visit)};visit(t);return out;}
for(const [name,bundle,bounds] of inputs){test(`device replay ${name}: discover exact live target, preserve approved fast path`,()=>{
 const t=tree(name);const report=new worker.ScanReport();const c=worker.discoverSnapshot(JSON.stringify(t),bundle,report);
 assert.ok(c,report.reason);assert.deepEqual(JSON.parse(JSON.stringify(c.bounds)),bounds);assert.ok(c.rule.strategy);
 const r=new worker.ScanReport();const again=worker.discoverSnapshot(JSON.stringify(t),bundle,r,undefined,[c.rule],true);
 assert.ok(again,r.reason);assert.equal(again.approvedButton,true);
 });}
function manual(){const t=tree('damai');const bundle='cn.damai.hongmeng';const a=all(t).find(n=>n.attributes.text==='跳过').attributes;
 const event={bundleName:bundle,type:a.type,text:a.text,componentRect:{left:1185,top:175,right:1245,bottom:210},windowId:Number(a.hostWindowId)};
 return {t,bundle,event};}
test('explicit manual click creates source and strategy, matches without ad marker',()=>{
 const {t,bundle,event}=manual();const c=worker.manualSnapshot(JSON.stringify(t),bundle,event);assert.ok(c);assert.equal(c.rule.origin,'manual');
 for(const n of all(t))if(n.attributes.text==='广告'){n.attributes.text='';n.attributes.originalText='';}
 assert.ok(worker.discoverSnapshot(JSON.stringify(t),bundle,new worker.ScanReport(),undefined,[c.rule],true));
 const target=all(t).find(n=>n.attributes.text==='跳过');target.attributes.text='购买';target.attributes.originalText='购买';
 assert.equal(worker.manualSnapshot(JSON.stringify(t),bundle,undefined,c.rule),undefined);
});
test('manual event rejects another app/window, zero geometry and different component text',()=>{
 const {t,bundle,event}=manual();for(const change of [{bundleName:'com.other.app'},{windowId:99999},{text:'购买'},{componentRect:{left:0,top:0,right:0,bottom:0}},{type:'Image'}]){
 assert.equal(worker.manualSnapshot(JSON.stringify(t),bundle,{...event,...change}),undefined);
 }
});
test('manual rematch rejects disabled, hidden, moved and covered targets',()=>{
 for(const change of [{enabled:'false'},{visible:'false'},{bounds:'[800,300][900,350]'},{hitTestBehavior:'HitTestMode.None'}]){
 const {t,bundle,event}=manual();const c=worker.manualSnapshot(JSON.stringify(t),bundle,event);Object.assign(all(t).find(n=>n.attributes.text==='跳过').attributes,change);
 assert.equal(worker.manualSnapshot(JSON.stringify(t),bundle,undefined,c.rule),undefined);
 }
 const {t,bundle,event}=manual();const c=worker.manualSnapshot(JSON.stringify(t),bundle,event);
 t.children.push({attributes:{type:'Button',text:'购买',clickable:'true',enabled:'true',visible:'true',bounds:'[1180,170][1250,220]',zIndex:'99'},children:[]});
 assert.equal(worker.manualSnapshot(JSON.stringify(t),bundle,undefined,c.rule),undefined);
});
test('decorative rings without ad marker are not advertised as a real countdown',()=>{
 const t=tree('damai');for(const n of all(t))if(n.attributes.text==='广告'){n.attributes.text='';n.attributes.originalText='';}
 assert.equal(worker.discoverSnapshot(JSON.stringify(t),'cn.damai.hongmeng',new worker.ScanReport()),undefined);
});
test('bubbled toolbar click resolves its unique evidenced close child, not a full-screen surface',()=>{
 const {t,bundle}=manual(); const nodes=all(t); const source=nodes.find(n=>n.attributes.type==='__Common__' && n.attributes.bounds==='[0,117][1320,261]');
 assert.ok(source);const a=source.attributes; const event={bundleName:bundle,type:a.type,text:'',windowId:Number(a.hostWindowId),componentId:a.accessibilityId,componentRect:{left:0,top:0,right:1320,bottom:261}};
 const c=worker.manualSnapshot(JSON.stringify(t),bundle,event);assert.ok(c);assert.equal(c.rule.origin,'manual');assert.equal(c.rule.buttonType,'Text');assert.equal(c.bounds.left,1185);
 for(const n of nodes)if(n.attributes.text==='广告'){n.attributes.text='';n.attributes.originalText='';}
 assert.equal(worker.manualSnapshot(JSON.stringify(t),bundle,event),undefined);
 assert.equal(worker.manualSnapshot(JSON.stringify(t),bundle,{...event,componentRect:{left:0,top:0,right:1320,bottom:2120}}),undefined);
});
