const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const source=fs.readFileSync(require('node:path').join(__dirname,'../entry/src/ohosTest/ets/worker/LayoutCapture.ets'),'utf8');
function fixture(api, text='{"attributes":{},"children":[]}') {
 const files=new Map([['/app/layout.json','stale']]),calls=[];
 const io={OpenMode:{},unlinkSync:p=>files.delete(p),openSync:p=>({fd:p}),writeSync:(p,s)=>files.set(p,s),closeSync(){}};
 const deps={'@kit.PerformanceAnalysisKit':{hilog:{info(){}}},'@kit.CoreFileKit':{fileIo:io},'@kit.BasicServicesKit':{deviceInfo:{sdkApiVersion:api}},
 '@kit.TestKit':{abilityDelegatorRegistry:{getAbilityDelegator:()=>({getAppContext:()=>({filesDir:'/app'})})}},
 '../../../main/ets/core/LocalActivation':{LocalActivation:class{constructor(dir){assert.equal(dir,'/app')}canReuseLayout(){return true;} readLayoutTiming(){return {};} close(){} async readCurrentLayout(){calls.push('local');return text;}}}};
 const exports={};vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{exports,require:n=>deps[n]});
 return {files,calls,capture:exports.captureLayout};
}
test('API 24 uses trusted loopback layout, never the unavailable Driver method',async()=>{
 const f=fixture(24);assert.equal(await f.capture({dumpLayout(){throw Error('unavailable');}},'/app/layout.json'),true);
 assert.equal(f.files.get('/app/layout.json'),'{"attributes":{},"children":[]}');assert.equal(f.calls.length,1);
});
for(const value of ['', '{partial'])test('failed or partial capture removes stale target: '+value,async()=>{
 const f=fixture(24,value);await assert.rejects(f.capture({},'/app/layout.json'));assert.equal(f.files.has('/app/layout.json'),false);
});
test('API 26 continues using native dump without opening a local connection',async()=>{
 const f=fixture(26);let path='';assert.equal(await f.capture({dumpLayout:async p=>{path=p;return true;}},'/app/layout.json'),true);
 assert.equal(path,'/app/layout.json');assert.equal(f.calls.length,0);
});
test('real sanitized API 24 driving-app layout resolves separate label and countdown to its container',()=>{
 const e=require('../tools/community/replay.cjs').engine();const r=new e.worker.ScanReport();
 const c=e.worker.discoverSnapshot(fs.readFileSync(require('node:path').join(__dirname,'fixtures/jiaxiao-api24-countdown.json'),'utf8'),'com.jiaxiao.driveharmony',r,e.pack);
 assert.ok(c,r.reason);assert.equal(c.rule.profile.strategyId,'S03');assert.equal(c.rule.buttonType,'Flex');
 assert.deepEqual({...c.bounds},{left:1023,top:267,right:1193,bottom:355});
 assert.equal(c.rule.profile.parts.find(p=>p.role==='countdown').text,'5');
});
