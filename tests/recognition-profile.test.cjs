const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const e=require('../tools/community/replay.cjs').engine(),{worker:w,profile:p,capture}=e;
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const geometry={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(__dirname+'/../entry/src/main/ets/core/ButtonPreviewLayout.ets','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{exports:geometry});
const bundle='com.example.splash';
function node(text='',bounds='[800,100][960,160]',type='Button',children=[],extra={}){return {attributes:{text,bounds,type,enabled:'true',visible:'true',clickable:type==='Button'?'true':'false',...extra},children};}
function tree(children){return node('','[0,0][1000,2000]','root',children,{bundleName:bundle,focused:'true',hostWindowId:'7'});}
function scan(t,approved=[],only=false){const r=new w.ScanReport();const c=w.discoverSnapshot(JSON.stringify(t),bundle,r,undefined,approved,only);return {c,r};}
const ad=()=>node('广告','[20,100][60,130]','Text');
function assertProfile(c,r){assert.ok(c,r?.reason);assert.ok(p.validProfile(c.rule.profile),JSON.stringify(c.rule.profile));return c.rule.profile;}
test('S01 explicit action, S02 ad marker, S03 inline countdown and S05 icon have stable IDs',()=>{
 for(const [expected,t] of [
  ['S01',tree([node('跳过广告')])],['S02',tree([node('关闭'),ad()])],['S03',tree([node('3s｜跳过')])],
  ['S05',tree([node('','[800,100][860,160]','Image',[],{id:'splash_close_button',clickable:'true'}),ad()])]
 ]){const {c,r}=scan(t),profile=assertProfile(c,r);assert.equal(profile.strategyId,expected);assert.equal(p.ruleStrategyId(c.rule),expected);}
});
test('S04 circular progress preserves text inside ring, not a fabricated countdown number',()=>{
 const t=tree([node('','[870,85][960,175]','Stack',[
  node('跳过','[890,110][940,145]'),node('','[875,90][955,170]','Progress')])]);
 const {c,r}=scan(t),profile=assertProfile(c,r);assert.equal(profile.strategyId,'S04');assert.equal(profile.shape,'circle');
 assert.equal(profile.content,'chinese');const ring=profile.parts.find(x=>x.role==='progress'),text=profile.parts.find(x=>x.text==='跳过');
 assert.ok(ring.left<text.left&&ring.right>text.right&&ring.top<text.top&&ring.bottom>text.bottom);
 assert.equal(profile.parts.filter(x=>x.role==='countdown').length,0);
});
test('both countdown evidence types are retained without duplicating strategy or rules',()=>{
 const t=tree([node('','[800,85][970,175]','Stack',[node('跳过 3'),node('','[870,85][960,175]','Progress')])]);
 const {c,r}=scan(t),profile=assertProfile(c,r);assert.equal(profile.strategyId,'S03');
 assert.ok(profile.evidence.includes('text-countdown'));assert.ok(profile.evidence.includes('graphical-countdown'));
 const original=c.rule.key;t.children[0].children[0].attributes.text='跳过 2';assert.equal(scan(t).c.rule.key,original);
});
test('text order follows positions, including countdown outside hit target and reversed tree order',()=>{
 for(const leftCount of [true,false]){
  const close=node('跳过',leftCount?'[890,110][950,145]':'[800,110][860,145]');
  const timer=node('3s',leftCount?'[800,110][850,145]':'[890,110][940,145]','Text');
  const t=tree([node('','[790,90][970,170]','Stack',[close,timer])]);
  const {c,r}=scan(t),profile=assertProfile(c,r);assert.equal(profile.strategyId,'S03');assert.equal(profile.content,'mixed');
  assert.equal(profile.parts[0].text,leftCount?'3s':'跳过');
  const layout=geometry.buttonSampleLayout(profile,.5,84,58),txt=layout.parts.find(x=>x.text==='跳过'),num=layout.parts.find(x=>x.text==='3s');
  assert.equal(num.x<txt.x,leftCount);assert.ok(num.x>=0&&num.x+num.width<=84);
 }
});
test('vertical and overlaid parts preserve their relative positions',()=>{
 const t=tree([node('','[850,90][960,200]','Stack',[node('跳过','[870,145][940,175]'),node('3s','[890,105][925,135]','Text')])]);
 const {c,r}=scan(t),profile=assertProfile(c,r),layout=geometry.buttonSampleLayout(profile,.5,84,58);
 assert.ok(layout.parts.find(x=>x.text==='3s').y<layout.parts.find(x=>x.text==='跳过').y);
});
test('parent receiver is captured independently of text and no unrelated page copy is retained',()=>{
 const t=tree([node('','[790,90][970,175]','Row',[node('跳过','[830,110][935,145]','Text')],{clickable:'true'}),ad(),node('私密账户 123456','[0,600][400,900]','Text')]);
 const {c,r}=scan(t),profile=assertProfile(c,r);assert.equal(profile.targetMode,'parent');
 assert.ok(profile.layers.some(x=>x.role==='label'));assert.ok(profile.layers.some(x=>x.role==='target'));
 assert.ok(profile.button.left<profile.parts[0].left);assert.doesNotMatch(JSON.stringify(profile),/私密|123456/);
});
test('shape metadata uses explicit evidence; square bounds alone use rounded fallback',()=>{
 const b={left:0,top:0,right:60,bottom:60};assert.equal(capture.capturedShape({type:'Button'},b),'unknown');
 for(const [a,expected] of [[{type:'Circle'},'circle'],[{type:'Ellipse'},'ellipse'],[{buttonType:'ButtonType.Capsule'},'capsule'],[{borderRadius:'0'},'rectangle'],[{borderRadius:'4px'},'rounded'],[{borderRadius:'50%'},'unknown']])assert.equal(capture.capturedShape(a,b),expected);
 assert.equal(p.shapeName('unknown'),'圆角矩形示意');
});
test('content classes retain Chinese, digits, mixed text, icon and no-text image',()=>{
 for(const [text,role,kind] of [['关闭','text','chinese'],['3s','countdown','numeric'],['３秒','countdown','numeric'],['3｜跳过','text','mixed'],['Skip','text','english'],['×','icon','icon'],['','icon','icon']])assert.equal(p.contentKind([{text,role}]),kind,text);
});
test('bare digits cannot autonomously become an ad rule; manual profile still depicts only digits',()=>{
 const t=tree([node('3','[870,110][930,155]','Text',[],{clickable:'true'})]);assert.equal(scan(t).c,undefined);
 const c=w.manualSnapshot(JSON.stringify(t),bundle,{bundleName:bundle,windowId:7,type:'Text',text:'3',componentRect:{left:870,top:110,right:930,bottom:155}});
 const profile=assertProfile(c);assert.equal(profile.strategyId,'S08');assert.equal(profile.content,'numeric');assert.equal(profile.parts[0].text,'3');assert.equal(profile.parts.length,1);
});
test('7x24 channels and dimensions are never close buttons, even with ad evidence or an old approval',()=>{
 const saved=scan(tree([node('×'),ad()])).c.rule;
 for(const label of ['7x24','7×24','24 X 7','７ｘ２４','8✕16']){
  const t=tree([node(label),ad()]);assert.equal(scan(t).c,undefined,label);assert.equal(scan(t,[saved],true).c,undefined,label);
 }
 for(const label of ['×','3s｜×','× 3'])assert.equal(e.store.skipLabel(label),'×');
});
test('S07 keeps original OCR provenance during approved reuse with no OCR evidence',()=>{
 const t=JSON.parse(fs.readFileSync(__dirname+'/fixtures/iqiyi-image-marker-0912.json'));const b='com.qiyi.video.hmy';
 const r=new w.ScanReport();w.discoverSnapshot(JSON.stringify(t),b,r);r.imageMarker=new w.AdMarkerEvidence('广告','image-ocr',r.imageRegions[0]);
 const c=w.discoverSnapshot(JSON.stringify(t),b,r),profile=assertProfile(c,r);assert.equal(profile.strategyId,'S07');
 const again=w.discoverSnapshot(JSON.stringify(t),b,new w.ScanReport(),undefined,[c.rule],true);
 assert.ok(again.approvedButton);assert.equal(again.rule.profile.strategyId,'S07');assert.equal(again.rule.key,c.rule.key);
});
for(const [file,b] of [['xiachufang','com.xiachufang.recipe'],['jiaxiao','com.jiaxiao.driveharmony'],['mgtv','com.mgtv.phone'],['damai','cn.damai.hongmeng'],['railway','com.chinarailway.ticketingHM']])test(`real ${file} sample has valid profile without altering approved target`,()=>{
 const t=fs.readFileSync(`${__dirname}/fixtures/${file}-splash-0945.json`,'utf8'),r=new w.ScanReport();
 const c=w.discoverSnapshot(t,b,r),profile=assertProfile(c,r);if(file==='railway')assert.equal(profile.strategyId,'S06');
 const again=w.discoverSnapshot(t,b,new w.ScanReport(),undefined,[c.rule],true);assert.ok(again.approvedButton);assert.equal(JSON.stringify(again.bounds),JSON.stringify(c.bounds));
 assert.equal(p.ruleStrategyId(again.rule),profile.strategyId);
});
test('historical adapters retain identity, default shape and original display text',()=>{
 for(const marker of ['label','广告','countdown','control-id','structure','manual']){
  const old={marker,label:'跳过',example:'4s｜跳过',left:.8,top:.05,right:.95,bottom:.1,aspect:.5};const before=JSON.stringify(old),profile=p.profileForRule(old);
  assert.equal(JSON.stringify(old),before);assert.equal(profile.shape,'unknown');assert.equal(profile.parts[0].text,'4s｜跳过');assert.ok(/^S0[1-8]$/.test(profile.strategyId));
 }
});
test('invalid metadata cannot render oversized text or out-of-range coordinates',()=>{
 const profile=p.strategySample('S03');assert.ok(p.validProfile(profile));
 for(const mutate of [x=>x.strategyId='S99',x=>x.button.left=-1,x=>x.parts[0].text='字'.repeat(65),x=>x.parts[0].right=5,x=>x.parts=Array(30).fill(x.parts[0]),x=>x.evidence=['unknown']]){const bad=JSON.parse(JSON.stringify(profile));mutate(bad);assert.equal(p.validProfile(bad),false);}
});
test('user-defined action wording is rendered verbatim only for its accepted label',()=>{
 const t=tree([node('直接进入'),ad()]);const pack={rules:[{field:'text',value:'直接进入',match:'equals',action:'skip',bundles:[],exclude:[],maxLength:10}]};
 const r=new w.ScanReport(),c=w.discoverSnapshot(JSON.stringify(t),bundle,r,pack),profile=assertProfile(c,r);
 assert.equal(profile.parts[0].text,'直接进入');assert.equal(profile.content,'chinese');
});
test('all strategy examples use the shared model and fit both preview sides',()=>{
 assert.equal(new Set(p.RECOGNITION_STRATEGIES.map(x=>x.id)).size,8);
 for(const id of p.RECOGNITION_STRATEGIES.map(x=>x.id))for(const width of [61,80,112]){
  const profile=p.strategySample(id);assert.ok(p.validProfile(profile),id);const g=geometry.buttonSampleLayout(profile,.62,width,54);
  for(const part of g.parts)assert.ok(part.x>=0&&part.y>=0&&part.x+part.width<=width+.01&&part.y+part.height<=54+.01,id);
 }
});
test('railway invisible padding keeps old rule identity but taps the visible image centre',()=>{
 const t=fs.readFileSync(`${__dirname}/fixtures/railway-splash-0945.json`,'utf8'),b='com.chinarailway.ticketingHM';
 const c=w.discoverSnapshot(t,b,new w.ScanReport());
 assert.deepEqual(JSON.parse(JSON.stringify(c.bounds)),{left:1068,top:158,right:1212,bottom:233});
 assert.equal(Math.round((c.bounds.top+c.bounds.bottom)/2),196);
 const display=p.profileForRule(c.rule);assert.equal(display.button.left,1068/1320);assert.equal(display.button.top,158/2120);
 assert.equal(c.rule.left,960/1320);assert.equal(c.rule.bottom,390/2120);
 const prior=JSON.parse(JSON.stringify(c.rule));delete prior.profile;
 const again=w.discoverSnapshot(t,b,new w.ScanReport(),undefined,[prior],true);assert.ok(again.approvedButton);assert.equal(again.rule.key,c.rule.key);
});
test('actual damai Circle stacks render circular without inventing progress evidence',()=>{
 const t=fs.readFileSync(`${__dirname}/fixtures/damai-splash-0945.json`,'utf8');const c=w.discoverSnapshot(t,'cn.damai.hongmeng',new w.ScanReport());
 const display=p.profileForRule(c.rule);assert.equal(display.shape,'circle');assert.ok(display.parts.some(x=>x.role==='outline'));
 assert.ok(!display.evidence.includes('graphical-countdown'));assert.equal(display.strategyId,'S02');
});
test('Mango text row is compact, keeps both labels inside, and leaves circular samples round',()=>{
 const t=fs.readFileSync(`${__dirname}/fixtures/mgtv-splash-0945.json`,'utf8');const c=w.discoverSnapshot(t,'com.mgtv.phone',new w.ScanReport());
 const display=p.profileForRule(c.rule),g=geometry.buttonSampleLayout(display,c.rule.aspect,84,54);
 const before=JSON.stringify(display);
 for(const part of g.parts){assert.ok(part.x>=g.frame.x-.001);assert.ok(part.x+part.width<=g.frame.x+g.frame.width+.001);
  assert.ok(part.y>=g.frame.y-.001);assert.ok(part.y+part.height<=g.frame.y+g.frame.height+.001);assert.ok(part.fontSize>=10);}
 assert.ok(g.parts.find(x=>x.text==='5').x<g.parts.find(x=>x.text==='跳过').x);
 assert.ok(g.frame.height<=18.001);assert.ok(g.frame.width/g.frame.height>2.5);
 const ring=geometry.buttonSampleLayout(p.strategySample('S04'),.625,84,54);assert.ok(ring.frame.height>30);
 assert.ok(Math.abs(ring.frame.width-ring.frame.height)<.01);
 geometry.buttonSampleLayout(display,c.rule.aspect,61,54);assert.equal(JSON.stringify(display),before);
});
test('child refinement rechecks the child click point for coverage',()=>{
 const t=tree([node('','[750,80][990,290]','Row',[node('','[820,100][940,160]','Image',[],{clickable:'true'})],{id:'splash_skip',clickable:'true'}),ad()]);
 const c=scan(t).c;assert.ok(c);assert.equal(c.bounds.top,100);
 t.children.push(node('购买','[810,90][950,165]','Button',[],{zIndex:'9'}));assert.equal(scan(t,[c.rule],true).c,undefined);
});
test('disabled or ambiguous image children cannot fall back to an oversized receiver',()=>{
 for(const extra of [{enabled:'false'},{clickable:'false'}]){
  const t=tree([node('','[750,80][990,290]','Row',[node('','[820,100][940,160]','Image',[],{clickable:'true',...extra})],{id:'splash_skip',clickable:'true'}),ad()]);
  assert.equal(scan(t).c,undefined);
 }
});
test('manual railway receiver uses the same visible image target on later reuse',()=>{
 const t=fs.readFileSync(`${__dirname}/fixtures/railway-splash-0945.json`,'utf8'),b='com.chinarailway.ticketingHM';
 const event={bundleName:b,type:'Row',componentId:'fl_skip_wrong',windowId:1402,componentRect:{left:960,top:117,right:1320,bottom:390}};
 const c=w.manualSnapshot(t,b,event);assert.ok(c);assert.equal(c.bounds.top,158);assert.equal(c.rule.top,117/2120);
 assert.equal(w.manualSnapshot(t,b,undefined,c.rule).bounds.top,158);
});
test('matching historical manual rules enriches circular presentation without changing identity',()=>{
 const t=fs.readFileSync(`${__dirname}/fixtures/damai-splash-0945.json`,'utf8'),b='cn.damai.hongmeng';
 const root=JSON.parse(t);let target;function visit(n){if(n.attributes.text==='跳过')target=n.attributes;for(const c of n.children||[])visit(c)}visit(root);
 const c=w.manualSnapshot(t,b,{bundleName:b,type:'Text',text:'跳过',windowId:Number(target.hostWindowId),componentRect:{left:1185,top:175,right:1245,bottom:210}});
 assert.ok(c);const old=JSON.parse(JSON.stringify(c.rule));old.profile.shape='unknown';old.profile.parts=old.profile.parts.filter(x=>x.role!=='outline');
 const again=w.manualSnapshot(t,b,undefined,old);assert.equal(again.rule.key,old.key);assert.equal(again.rule.profile.shape,'circle');assert.equal(again.rule.profile.strategyId,'S08');
});
