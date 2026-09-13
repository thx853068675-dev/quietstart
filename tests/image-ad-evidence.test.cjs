const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const {worker}=require('../tools/community/replay.cjs').engine();
function tree(){return JSON.parse(fs.readFileSync(__dirname+'/fixtures/iqiyi-image-marker-0912.json','utf8'));}
function flat(t){let a=[];function w(n){a.push(n);(n.children||[]).forEach(w);}w(t);return a;}
function scan(t,proof){const r=new worker.ScanReport();r.imageMarker=proof;return {r,c:worker.discoverSnapshot(JSON.stringify(t),'com.qiyi.video.hmy',r)};}
test('actual image badge is proposed for OCR but cannot alone authorize discovery',()=>{
 const {r,c}=scan(tree());assert.equal(c,undefined);assert.ok(r.imageRegions.length <= 6);assert.equal(JSON.stringify(r.imageRegions[0]),JSON.stringify({left:60,top:84,right:180,bottom:144}));
});
test('OCR proof must match current eligible image; existing learned geometry retained',()=>{
 const t=tree(), region=scan(t).r.imageRegions[0], proof=new worker.AdMarkerEvidence('广告','image-ocr',region);
 const c=scan(t,proof).c;assert.ok(c);assert.equal(c.rule.marker,'广告');assert.equal(c.adMarker.source,'image-ocr');assert.equal(c.bounds.left,1062);
 assert.equal(scan(t,new worker.AdMarkerEvidence('广告','image-ocr',{...region,left:59})).c,undefined);
 const img=flat(t).find(n=>n.attributes.bounds==='[60,84][180,144]');img.attributes.visible='false';assert.equal(scan(t,proof).c,undefined);
});
test('interactive, hidden and disabled image badges are excluded',()=>{
 for(const patch of [{clickable:'true'},{visible:'false'},{enabled:'false'}]){
 const t=tree();Object.assign(flat(t).find(n=>n.attributes.bounds==='[60,84][180,144]').attributes,patch);
 assert.ok(!scan(t).r.imageRegions.some(r=>r.left===60&&r.top===84&&r.right===180));
 }
});
for(const bounds of ['[600,600][720,660]','[1100,1800][1220,1860]','[60,1700][180,1760]'])test(`image badge anywhere in same splash layer: ${bounds}`,()=>{
 const t=tree();flat(t).find(n=>n.attributes.bounds==='[60,84][180,144]').attributes.bounds=bounds;
 const v=bounds.match(/\d+/g).map(Number),region={left:v[0],top:v[1],right:v[2],bottom:v[3]};
 assert.ok(scan(t).r.imageRegions.some(r=>JSON.stringify(r)===JSON.stringify(region)));
 assert.equal(scan(t).c,undefined);
 assert.ok(scan(t,new worker.AdMarkerEvidence('广告','image-ocr',region)).c);
});
test('embedded badge can use one large artwork fallback after small regions',()=>{
 const t=tree(),r=scan(t).r.imageRegions;const large=r.filter(b=>(b.right-b.left)*(b.bottom-b.top)>160000);
 assert.equal(large.length,1);assert.equal(r.at(-1),large[0]);assert.ok(scan(t,new worker.AdMarkerEvidence('广告','image-ocr',large[0])).c);
});
test('plain image remaining at marker location prevents false dismissal',()=>{
 const t=tree(), proof=new worker.AdMarkerEvidence('广告','image-ocr',scan(t).r.imageRegions[0]), c=scan(t,proof).c;
 for(const n of flat(t))if(n.attributes.text==='关闭')n.attributes.text=n.attributes.originalText='';
 assert.equal(worker.snapshotTargetState(JSON.stringify(t),c.rule,proof),'blocked');
});
test('learned layout signature ignores window identity but detects button, structure and page changes',()=>{
 const t=tree(),sig=worker.imageLayoutSignature(JSON.stringify(t));assert.ok(sig);
 for(const n of flat(t))n.attributes.hostWindowId='999';
 assert.equal(worker.imageLayoutSignature(JSON.stringify(t)),sig);
 for(const patch of [{bounds:'[1060,57][1260,165]'},{text:'返回'},{enabled:'false'},{pagePath:'Login'}]){
 const changed=tree();Object.assign(flat(changed).find(n=>n.attributes.text==='关闭').attributes,patch);
 assert.notEqual(worker.imageLayoutSignature(JSON.stringify(changed)),sig);
 }
 assert.equal(worker.imageLayoutSignature('bad'), '');
});
test('splash fingerprint excludes loading homepage behind ad, retains changes within ad layer',()=>{
 const t=tree(),region=scan(t).r.imageRegions[0];
 const sig=worker.imageLayoutSignature(JSON.stringify(t),region);assert.ok(sig);
 const root=flat(t).find(n=>n.attributes.type==='root');
 root.children.unshift({attributes:{type:'Text',text:'首页正在加载',bounds:'[0,300][500,500]',visible:'true'}});
 assert.equal(worker.imageLayoutSignature(JSON.stringify(t),region),sig);
 const marker=flat(t).find(n=>n.attributes.bounds==='[60,84][180,144]');marker.attributes.opacity='0.98';
 assert.equal(worker.imageLayoutSignature(JSON.stringify(t),region),sig);
 marker.attributes.enabled='false';assert.notEqual(worker.imageLayoutSignature(JSON.stringify(t),region),sig);
});
test('homepage image near old badge without the splash layer does not block dismissal',()=>{
 const t=tree(),proof=new worker.AdMarkerEvidence('广告','image-memory',scan(t).r.imageRegions[0]),c=scan(t,proof).c;
 const root=flat(t).find(n=>n.attributes.type==='root');root.children=[{attributes:{type:'Image',bounds:'[60,84][180,144]',visible:'true',enabled:'true',clickable:'false'}}];
 assert.equal(worker.snapshotTargetState(JSON.stringify(t),c.rule,proof),'absent');
});
test('whole splash fallback covers Canvas content without an image badge',()=>{
 const t=tree();for(const n of flat(t))if(n.attributes.type==='Image')n.attributes.type='Canvas';
 const {r,c}=scan(t);assert.equal(c,undefined);assert.equal(r.imageRegions.length,1);
 assert.ok(worker.imageLayoutSignature(JSON.stringify(t),r.imageRegions[0]));
 assert.ok(scan(t,new worker.AdMarkerEvidence('广告','image-ocr',r.imageRegions[0])).c);
});
test('ordinary small dialog has no whole-screen OCR fallback',()=>{
 const t=tree();const layer=flat(t).find(n=>n.attributes.type==='Column'&&n.attributes.clickable==='true'&&n.attributes.bounds==='[0,0][1320,2120]');
 layer.attributes.bounds='[700,0][1320,400]';
 assert.equal(scan(t).r.imageRegions.length,0);
});
test('approved button ignores all artwork and surrounding layout without OCR proof',()=>{
 const original=tree(),proof=new worker.AdMarkerEvidence('广告','image-ocr',scan(original).r.imageRegions[0]);
 const saved=scan(original,proof).c.rule;
 const t=tree(),root=flat(t).find(n=>n.attributes.type==='root');
 const button=flat(t).find(n=>n.attributes.type==='Row'&&n.attributes.bounds==='[1062,0][1320,165]');
 root.children=[button];
 const report=new worker.ScanReport();const c=worker.discoverSnapshot(JSON.stringify(t),saved.bundle,report,undefined,[saved]);
 assert.ok(c);assert.equal(c.adMarker.source,'approved-button');assert.equal(c.rule.key,saved.key);
 assert.equal(report.imageRegions.length,0);
 root.children=[];
 root.children.push({attributes:{type:'Text',text:'首页',visible:'true',enabled:'true',bounds:'[0,300][100,350]'}});
 assert.equal(worker.snapshotTargetState(JSON.stringify(t),c.rule,c.adMarker),'absent');
});
test('approved button requires same label, type and geometry; unapproved list cannot bypass evidence',()=>{
 const original=tree(),proof=new worker.AdMarkerEvidence('广告','image-ocr',scan(original).r.imageRegions[0]),saved=scan(original,proof).c.rule;
 for(const kind of ['unapproved','type','label','position']){
 const t=tree(),root=flat(t).find(n=>n.attributes.type==='root');const button=flat(t).find(n=>n.attributes.type==='Row'&&n.attributes.bounds==='[1062,0][1320,165]');root.children=[button];
 if(kind==='type')button.attributes.type='Button';
 if(kind==='label')button.children[0].attributes.text=button.children[0].attributes.originalText='跳过';
 if(kind==='position'){button.attributes.bounds='[800,0][1058,165]';button.children[0].attributes.bounds='[800,57][998,165]';}
 const report=new worker.ScanReport();assert.equal(worker.discoverSnapshot(JSON.stringify(t),saved.bundle,report,undefined,kind==='unapproved'?[]:[saved]),undefined,kind);
 }
});
