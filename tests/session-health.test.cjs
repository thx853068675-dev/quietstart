const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
function load(file,mocks={},globals={}) {
 const exports={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'..',file),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}}).outputText,
 {exports,require:n=>{assert.ok(n in mocks,n);return mocks[n]},Date,...globals});return exports;
}
const core='entry/src/main/ets/core/', worker='entry/src/ohosTest/ets/worker/';
function fixture() {
 let now=1000000;const files=new Map();const io={OpenMode:{},readTextSync:p=>{if(!files.has(p))throw Error('missing');return files.get(p)},
 openSync:p=>({fd:p}),writeSync:(fd,s)=>files.set(fd,s),closeSync(){},renameSync:(p,q)=>{files.set(q,files.get(p));files.delete(p)},unlinkSync:p=>files.delete(p)};
 const globals={Date:class extends Date{static now(){return now}}}, kit={'@kit.CoreFileKit':{fileIo:io}};
 const supervision=load(core+'SupervisionStore.ets',kit,globals),debug=load(core+'DebugStore.ets',kit,globals);
 const exits=load(core+'SystemExitStore.ets',{...kit,'./DebugStore':debug},globals);
 const health=load(worker+'WorkerHealth.ets',kit,globals);
 return {files,supervision,debug,exits,health,setTime:t=>now=t};
}
test('stopped and superseded tokens cannot be revived by a worker',()=>{
 const f=fixture(),s=new f.supervision.SupervisionStore('/app');
 s.start('1789400000000');assert.equal(s.allows('1789400000000'),true);s.stop();assert.equal(s.allows('1789400000000'),false);
 s.start('1789400000001');assert.equal(s.allows('1789400000000'),false);assert.equal(s.allows('1789400000001'),true);
 f.files.set('/app/supervision-control.txt','malformed active 2');assert.equal(s.allows('malformed'),false);
});
test('heartbeat cannot refresh stalled RPC/progress and sleep preserves last RPC evidence',()=>{
 const f=fixture(),h=new f.health.WorkerHealth('/app','1789400000000',123);
 h.rpc();h.progress(false);f.setTime(1040000);h.begin('snapshot');h.save();
 assert.equal(h.rpcAt,1000000);assert.equal(h.progressAt,1000000);assert.equal(h.pulseAt,1040000);
 const fields=f.files.get('/app/worker-health.txt').trim().split(' ');
 assert.deepEqual(fields.slice(0,7),['1789400000000','123','1040','1000','1000','active','snapshot']);
 const s=new f.debug.DebugStatus();Object.assign(s,{running:true,heartbeatAt:1040000,supervisorToken:h.token,rpcAt:h.rpcAt,progressAt:h.progressAt});
 assert.equal(f.debug.isDebugOnline(s,1040000),false);s.state='sleeping';assert.equal(f.debug.isDebugOnline(s,1040000),true);
 h.progress(true);h.save();assert.equal(h.rpcAt,1000000);
});
test('system exit detail and prior session are preserved, deduplicated, and bounded',()=>{
 const f=fixture(),s=new f.exits.SystemExitStore('/app');
 f.files.set('/app/debug-status.json',JSON.stringify({running:false,expiresAt:0,startedAt:99,heartbeatAt:100,rpcAt:90,operation:'snapshot',state:'error',errorCode:'17000005'}));
 const detail={pid:1,processName:'quietstart',uid:2,exitSubReason:3,exitMsg:'CPU Highload',rss:100,pss:90,timestamp:999,processState:2};
 const launch={launchReason:1,launchReasonMessage:'start',lastExitReason:7,lastExitMessage:'resource',lastExitDetailInfo:detail,launchUTCTime:1000,launchUptime:30};
 const env=new f.exits.ExitEnvironment();env.apiVersion=24;env.osVersion='6.1.1';env.appVersion='0.9.52';
 const row=s.capture(launch,env,'process-exited',1);assert.deepEqual(row.detail,detail);assert.equal(row.operation,'snapshot');assert.equal(row.sessionError,'17000005');
 s.capture(launch,env);assert.equal(s.read().length,1);
 for(let i=0;i<25;i++) {f.setTime(1000000+i);s.capture({...launch,lastExitDetailInfo:{...detail,timestamp:2000+i}},env);}
 assert.equal(s.read().length,20);assert.equal(JSON.parse(s.exportText())[0].detail.timestamp,2024);
 assert.equal(f.exits.exitReasonLabel(2),'正常或直接终止');assert.equal(f.exits.exitReasonLabel(7),'系统资源管控');
});
test('expected actions annotate original system reason; stale intent is ignored',()=>{
 const f=fixture(),s=new f.exits.SystemExitStore('/app'),e=new f.exits.ExitEnvironment(),launch={launchReason:1,lastExitReason:2};
 s.markExpected('activation');assert.equal(s.capture(launch,e).expectedAction,'activation');
 assert.equal(s.capture(launch,e).expectedAction,'');
 s.markExpected('user-stop');f.setTime(1200001);assert.equal(s.capture(launch,e).expectedAction,'');
});
const program=load(core+'SupervisorProgram.ets');
test('supervisor command validates token and base64 program',()=>{
 assert.throws(()=>program.supervisorCommand('1;reboot','abc',100));assert.throws(()=>program.supervisorCommand('1789400000000',"';id",100));
 assert.throws(()=>program.supervisorCommand('1789400000000','YWJj',-1));
 const encoded=Buffer.from(program.SUPERVISOR_PROGRAM).toString('base64');
 assert.ok(program.supervisorCommand('1789400000000',encoded,100).includes(encoded));
});


test('a later manual open detects only an exhausted matching stale session',()=>{
 const f=fixture(),s=new f.debug.DebugStatus();Object.assign(s,{running:true,heartbeatAt:1000000,supervisorToken:'1789400000000',recoveryAttempt:3});
 assert.equal(f.debug.exhaustedRecovery(s,s.supervisorToken,1040000),true);
 assert.equal(f.debug.exhaustedRecovery(s,s.supervisorToken,1005000),false);
 assert.equal(f.debug.exhaustedRecovery(s,'1789400000001',1040000),false);
 s.recoveryAttempt=2;assert.equal(f.debug.exhaustedRecovery(s,s.supervisorToken,1040000),false);
});

test('explicit vendor User Request message stops recovery without treating every NORMAL as a user stop',()=>{
 const f=fixture(),p=f.exits.userRequestedExit;
 assert.equal(p(2,'User Request'),true);assert.equal(p(2,'Kill Reason: User Request'),true);assert.equal(p(9,''),true);
 assert.equal(p(2,''),false);assert.equal(p(0,'unknown'),false);assert.equal(p(2,'application request timeout'),false);
});

test('recovery runner resumes the worker without opening UI; first activation still opens it',async()=>{
 for (const attempt of [0,1,3]) {
  const f=fixture(),s=new f.supervision.SupervisionStore('/app'),token='1789400000000';s.start(token);
  const calls=[];
  const delegator={getAppContext:()=>({filesDir:'/app'}),startAbility:async()=>calls.push('UI'),
   printSync(){},finishTest:async()=>calls.push('finished')};
  const Runner=load('entry/src/ohosTest/ets/testrunner/OpenHarmonyTestRunner.ets',{
   '@kit.TestKit':{abilityDelegatorRegistry:{getAbilityDelegator:()=>delegator,getArguments:()=>({parameters:{mode:'skip',supervisor:token,recoveryAttempt:String(attempt)}})}},
   '@kit.PerformanceAnalysisKit':{hilog:{info(){}}},'@ohos/hypium':{},'@kit.ArkTS':{},
   '../../../main/ets/core/LearningStore':{},'../../../main/ets/core/SupervisionStore':f.supervision,
   '../worker/SkipWorker':{run:async(d,seconds,t,a)=>{assert.equal(t,token);assert.equal(a,attempt);calls.push('worker');return {state:'ended'}}}
  },{setTimeout:fn=>fn()}).default;
  await new Runner().onRun();
  assert.deepEqual(calls,attempt===0?['UI','worker','finished']:['worker','finished']);
  s.stop();calls.length=0;await new Runner().onRun();assert.deepEqual(calls,['finished']);
 }
});

test('exit capture returns recovery UI to background once, without hiding ordinary opens or exhaustion notices',()=>{
 for(const mode of ['recovery','normal','stale','stopped','exhausted','user-stop']) {
  const f=fixture(),s=new f.supervision.SupervisionStore('/app'),token='1789400000000';s.start(token);
  if(mode==='stopped')s.stop();let moved=0;
  const Entry=load('entry/src/main/ets/entryability/EntryAbility.ets',{
   '@kit.AbilityKit':{UIAbility:class{},bundleManager:{getBundleInfoForSelfSync:()=>({versionName:'0.9.52'})}},
   '@kit.BasicServicesKit':{deviceInfo:{}},'@kit.ArkTS':{},'@kit.PerformanceAnalysisKit':{hilog:{info(){},warn(){}}},'@kit.ArkUI':{},
   '../core/LocalStore':{LocalStore:class{readSettings(){return {}}}},'../core/Theme':{themeIsDark:()=>false},
   '../core/SystemExitStore':f.exits,'../core/SupervisionStore':f.supervision,'../core/DebugStore':f.debug
  },{AppStorage:{setOrCreate(){}}}).default;
  const e=new Entry();e.context={getApplicationContext:()=>({filesDir:'/app'}),config:{},moveAbilityToBackground:async()=>{moved++}};
  const parameters=mode==='normal'?{}:{quietstartRecoveryToken:mode==='stale'?'1789400000001':token,
   ...(mode==='exhausted'?{quietstartSupervisorState:'exhausted'}:{quietstartRecoveryReason:'process-exited'})};
  e.onCreate({parameters},{launchReason:1,lastExitReason:2,lastExitMessage:mode==='user-stop'?'User Request':''});
  assert.equal(new f.exits.SystemExitStore('/app').read().length,1);
  e.onForeground();e.onForeground();assert.equal(moved,mode==='recovery'?1:0,mode);
 }
});
