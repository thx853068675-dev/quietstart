const test=require('node:test'),assert=require('node:assert/strict');
const {store:{LearningStore,OWN_BUNDLE,discoverableBundle}}=require('../tools/community/replay.cjs').engine();
const app=(bundleName,label=bundleName)=>({bundleName,label});
const a='com.example.native',v='com.example.bridge',b='com.example.second';
function setup(){
 const store=new LearningStore('/memory');const files={};const seen=[{...app(a,'原生'),firstSeen:1,lastSeen:1},{...app(v,'卓易通应用'),firstSeen:1,lastSeen:1}];
 store.write=(n,s)=>{files[n]=JSON.parse(s)};
 store.nameMap=n=>Object.fromEntries(Object.entries(files[n]||{}).filter(([,v])=>v));
 store.readCatalog=()=>files['app-catalog.json']||{apps:[],updatedAt:0,requestAt:0};
 store.readSeenApps=()=>seen.map(x=>({...x}));store.androidApps=()=>[v];
 const rules=[{bundle:a,key:'rule-native'},{bundle:v,key:'rule-bridge'}];store.readRules=()=>rules;
 return {store,files,seen,rules};
}
const raw=apps=>JSON.stringify([app(OWN_BUNDLE,'轻启'),...apps]);
test('complete native snapshot removes known native uninstall while preserving bridge, aliases and rules',()=>{
 const {store,files,rules}=setup();files['app-aliases.json']={[a]:'我的备注'};
 store.syncNativeCatalog(raw([app(a,'原生')]),Date.now());
 store.syncNativeCatalog(raw([app(b)]),Date.now()+1);
 assert.equal(store.appUnavailable(a),'uninstalled');assert.equal(store.appUnavailable(v),'');
 assert.deepEqual(Array.from(store.managedApps([a,v,b]),x=>x.bundleName).sort(),[b,v].sort());
 assert.equal(files['app-aliases.json'][a],'我的备注');assert.equal(rules.length,2);
 store.syncNativeCatalog(raw([app(a,'新名称')]),Date.now()+2);
 assert.equal(store.appUnavailable(a),'');assert.equal(store.displayName(a),'我的备注');
});
test('failed, incomplete, oversized and stale catalogs do not wipe app state',()=>{
 const {store,files}=setup();store.syncNativeCatalog(raw([app(a)]),Date.now());
 const before=JSON.stringify(files);
 for(const input of ['','[]','error',JSON.stringify([app(b)]),raw([{bundleName:b,label:null}])])assert.throws(()=>store.syncNativeCatalog(input,Date.now()+1));
 assert.equal(JSON.stringify(files),before);
 assert.equal(store.syncNativeCatalog(raw([app(b)]),1),0);assert.equal(JSON.stringify(files),before);
});
test('unknown bridge absent from native catalog stays visible; foreground revives hidden history without deleting rules',()=>{
 const {store,files}=setup();store.syncNativeCatalog(raw([app(b)]),Date.now());
 assert.equal(store.appUnavailable(a),'');assert.equal(store.appUnavailable(v),'');
 store.hideApp(v);assert.equal(store.managedApps([v]).some(x=>x.bundleName===v),false);
 store.recordSeenApp(v);assert.equal(store.appUnavailable(v),'');assert.equal(store.readRules().length,2);
 assert.ok(files['seen-apps.json'].some(x=>x.bundleName===v));
});
test('a foreground observation newer than catalog request prevents stale uninstall removal',()=>{
 const {store,seen}=setup();store.syncNativeCatalog(raw([app(a)]),Date.now());const at=Date.now()+1;
 seen[0].lastSeen=at+5;store.syncNativeCatalog(raw([app(b)]),at);assert.equal(store.appUnavailable(a),'');
});
test('bridge host and permission controller are not standalone managed applications',()=>{
 assert.equal(discoverableBundle('com.huawei.shell_assistant'),false);assert.equal(discoverableBundle('com.android.permissioncontroller'),false);
 assert.equal(discoverableBundle('com.fan.app'),true);
});
