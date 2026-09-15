const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
function load(file,mocks={},globals={}) {
 const exports={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'..',file),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}}).outputText,
 {exports,require:n=>{assert.ok(n in mocks,n);return mocks[n]},Date,...globals});return exports;
}
const core='entry/src/main/ets/core/', worker='entry/src/ohosTest/ets/worker/';
function fixture() {
 let now=1000000,writes=0;const files=new Map();const io={OpenMode:{},readTextSync:p=>{if(!files.has(p))throw Error('missing');return files.get(p)},
 openSync:p=>({fd:p}),writeSync:(fd,s)=>{writes++;files.set(fd,s)},closeSync(){},renameSync:(p,q)=>{files.set(q,files.get(p));files.delete(p)},unlinkSync:p=>files.delete(p)};
 const globals={Date:class extends Date{static now(){return now}}}, kit={'@kit.CoreFileKit':{fileIo:io}};
 const supervision=load(core+'SupervisionStore.ets',kit,globals),debug=load(core+'DebugStore.ets',kit,globals);
 const exits=load(core+'SystemExitStore.ets',{...kit,'./DebugStore':debug},globals);
 const health=load(worker+'WorkerHealth.ets',kit,globals);
 return {files,supervision,debug,exits,health,getWrites:()=>writes,setTime:t=>now=t};
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
 assert.equal(s.read().length,20);assert.equal(JSON.parse(s.exportText()).exits[0].detail.timestamp,2024);
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


test('all non-user exit categories continue recovery including upgrade and unknown reasons',()=>{
 const f=fixture();
 for(const reason of [-1,0,1,2,3,4,5,6,7,8,10,99]) {
  const row=new f.exits.SystemExitRecord();row.reason=reason;
  assert.equal(f.exits.shouldStopRecovery(row),false,String(reason));
  row.message='User Request';assert.equal(f.exits.shouldStopRecovery(row),true);
  row.message='';row.plannedAction='user-stop';assert.equal(f.exits.shouldStopRecovery(row),true);
 }
 const store=new f.exits.SystemExitStore('/app');
 const row=store.capture({lastExitReason:8},new f.exits.ExitEnvironment(),'process-exited',8);
 assert.equal(row.stopDecision,'continue');assert.equal(row.recoveryAttempt,8);assert.equal(row.recoveryAttemptKnown,true);
});

test('explicit vendor User Request message stops recovery without treating every NORMAL as a user stop',()=>{
 const f=fixture(),p=f.exits.userRequestedExit;
 assert.equal(p(2,'User Request'),true);assert.equal(p(2,'Kill Reason: User Request'),true);assert.equal(p(9,''),true);
 assert.equal(p(2,''),false);assert.equal(p(0,'unknown'),false);assert.equal(p(2,'application request timeout'),false);
});

test('recovery runner resumes the worker without opening UI; first activation still opens it',async()=>{
 for (const attempt of [0,1,3,8]) {
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

test('exit capture returns recovery UI to background once, without hiding ordinary opens or cancelling repeated recovery',()=>{
 for(const mode of ['recovery','normal','stale','stopped','repeated','upgrade','exhausted','user-stop','own-restart']) {
  const f=fixture(),s=new f.supervision.SupervisionStore('/app'),token='1789400000000';s.start(token);
  if(mode==='stopped')s.stop();let moved=0;
  const Entry=load('entry/src/main/ets/entryability/EntryAbility.ets',{
   '@kit.AbilityKit':{UIAbility:class{},bundleManager:{getBundleInfoForSelfSync:()=>({versionName:'0.9.52'})}},
   '@kit.BasicServicesKit':{deviceInfo:{}},'@kit.ArkTS':{},'@kit.PerformanceAnalysisKit':{hilog:{info(){},warn(){}}},'@kit.ArkUI':{},
   '../core/SupervisionStressProbe':{armSupervisionStress(){}},
   '../core/LocalStore':{LocalStore:class{readSettings(){return {}}}},'../core/Theme':{themeIsDark:()=>false},
   '../core/SystemExitStore':f.exits,'../core/SupervisionStore':f.supervision,'../core/DebugStore':f.debug
  },{AppStorage:{setOrCreate(){}}}).default;
  const e=new Entry();e.context={getApplicationContext:()=>({filesDir:'/app'}),config:{},moveAbilityToBackground:async()=>{moved++}};
  const parameters=mode==='normal'?{}:{quietstartRecoveryToken:mode==='stale'?'1789400000001':token,
   ...(mode==='exhausted'?{quietstartSupervisorState:'exhausted'}:{quietstartRecoveryReason:'process-exited'}),quietstartRecoveryAttempt:mode==='repeated'?8:1};
  if(mode==='repeated') f.files.set('/app/debug-status.json',JSON.stringify({running:false,heartbeatAt:1,supervisorToken:token,recoveryAttempt:8}));
  if(mode==='own-restart') f.files.set('/app/supervisor-stop-intent.json',JSON.stringify({token,pid:42,at:999000,completed:true}));
  e.onCreate({parameters},{launchReason:1,lastExitReason:mode==='upgrade'?8:2,lastExitMessage:['user-stop','own-restart','exhausted'].includes(mode)?'User Request':'',
   ...(mode==='own-restart'?{lastExitDetailInfo:{pid:42,timestamp:999500}}:{})});
  assert.equal(s.read().active,!['stopped','exhausted','user-stop'].includes(mode),mode);
  assert.equal(new f.exits.SystemExitStore('/app').read().length,1);
  if(mode==='exhausted') assert.match(s.notice(),/4/);
  e.onForeground();e.onForeground();assert.equal(moved,['recovery','repeated','upgrade','own-restart'].includes(mode)?1:0,mode);
 }
});


test('supervisor stop requires completed command, matching token PID and exit timestamp',()=>{
 const f=fixture(), e=f.exits;
 const row=new e.SystemExitRecord(); Object.assign(row,{capturedAt:1030000,reason:2,message:'User Request',detail:{pid:42,timestamp:1020500}});
 const intent={token:'1789400000000',pid:42,at:1020000,completed:true};
 assert.equal(e.verifiedSelfStop(intent,row,intent.token),true);
 for(const bad of [{...intent,completed:false},{...intent,pid:43},{...intent,at:1040000},{...intent,token:'1789400000001'}])
  assert.equal(e.verifiedSelfStop(bad,row,intent.token),false);
 row.detail={pid:-1,timestamp:0}; assert.equal(e.verifiedSelfStop(intent,row,intent.token),false);
 row.plannedAction='worker-restart'; assert.equal(e.shouldStopRecovery(row),true);
 row.plannedAction='activation'; assert.equal(e.shouldStopRecovery(row),true);
 row.selfStopVerified=true; assert.equal(e.shouldStopRecovery(row),false);
 row.reason=8;assert.equal(e.shouldStopRecovery(row),false);
 row.reason=2;row.plannedAction='user-stop';assert.equal(e.shouldStopRecovery(row),true);
});

test('recovery cause is not overwritten by planned action and export includes bounded valid journal',()=>{
 const f=fixture(), s=new f.exits.SystemExitStore('/app');
 s.markExpected('worker-restart');
 const rows=Array.from({length:130},(_,i)=>JSON.stringify({token:'1789400000000',at:i+1,supervisorPid:123,state:'retrying',cause:'rpc-stalled'}));
 f.files.set('/app/supervisor-events.jsonl',rows.join('\n')+'\n{partial');
 const row=s.capture({lastExitReason:2,launchReason:1},new f.exits.ExitEnvironment(),'process-exited',1);
 assert.equal(row.recoveryReason,'process-exited');assert.equal(row.expectedAction,'process-exited');assert.equal(row.plannedAction,'worker-restart');
 assert.equal(row.recoveryAttemptKnown,true);
 assert.equal(s.capture({lastExitReason:2},new f.exits.ExitEnvironment()).recoveryAttemptKnown,false);
 const dump=JSON.parse(s.exportText());assert.equal(dump.schemaVersion,4);assert.ok(dump.supervisorTimeline.length<=120);
 assert.equal(dump.supervisorTimeline.at(-1).at,130);
});

test('supervisor transport accepts current-session events, deduplicates and bounds imported snapshots',()=>{
 const f=fixture(),s=new f.exits.SystemExitStore('/app'), token='1789400000000';
 const event={token,at:999000,supervisorPid:456,state:'command-result',cause:'rpc-stalled',command:'force-stop',exitCode:0};
 const line=JSON.stringify(event);
 s.importSupervisorEvents(line+'\n'+line+'\n{broken\n'+JSON.stringify({...event,token:'1789400000001'}),token);
 assert.equal(s.timeline().length,1);
 const before=f.getWrites(); s.importSupervisorEvents(line,token);assert.equal(f.getWrites(),before);
 s.importSupervisorEvents('x'.repeat(65537),token);assert.equal(s.timeline().length,1);
 f.files.set('/app/supervision-control.txt',token+' active 0');
 const row=s.capture({lastExitReason:2,lastExitMessage:'User Request',lastExitDetailInfo:{pid:42,timestamp:999500}},
  new f.exits.ExitEnvironment(),'rpc-stalled',1,JSON.stringify({token,pid:42,at:999000,completed:true}));
 assert.equal(row.selfStopVerified,true); assert.equal(row.stopDecision,'self-restart');
});

test('fault hook requires exact test version and current session, consumes once and rejects stale requests',async()=>{
 const f=fixture(),token='1789400000000'; new f.supervision.SupervisionStore('/app').start(token);
 let version='0.9.54', exits=0, waits=0;
 const io={OpenMode:{},readTextSync:p=>{if(!f.files.has(p))throw Error('missing');return f.files.get(p)},
  openSync:p=>({fd:p}),writeSync:(p,t)=>f.files.set(p,t),closeSync(){},unlinkSync:p=>f.files.delete(p)};
 const hook=load(core+'SupervisionStressProbe.ets',{
  '@kit.AbilityKit':{bundleManager:{getBundleInfoForSelfSync:()=>({versionName:version})}},'@kit.CoreFileKit':{fileIo:io},
  '@kit.ArkTS':{process:{exit:code=>{assert.equal(code,77);exits++}}},'./SupervisionStore':f.supervision
 },{Date:class extends Date{static now(){return 1005000}},setTimeout:fn=>{waits++;fn()}});
 const want={parameters:{quietstartStress:'exit',quietstartStressToken:token}};
 hook.armSupervisionStress('/app',want);assert.equal(f.files.has('/app/supervision-stress.json'),false);
 version='0.9.60-test';hook.armSupervisionStress('/app',{parameters:{...want.parameters,quietstartStressToken:'1789400000001'}});
 assert.equal(f.files.has('/app/supervision-stress.json'),false);
 hook.armSupervisionStress('/app',want);await hook.consumeSupervisionStress('/app',token);assert.equal(exits,0);
 f.files.set('/app/supervision-stress.json',JSON.stringify({token,kind:'exit',at:1000000}));
 await hook.consumeSupervisionStress('/app',token);await hook.consumeSupervisionStress('/app',token);assert.equal(exits,1);
 f.files.set('/app/supervision-stress.json',JSON.stringify({token,kind:'stall-rpc',at:1000000}));
 await hook.consumeSupervisionStress('/app',token);assert.equal(waits,1);
 f.files.set('/app/supervision-stress.json',JSON.stringify({token,kind:'exit',at:990000}));
 await hook.consumeSupervisionStress('/app',token);assert.equal(exits,1);
});

 test('terminal errors survive a replacement worker and are correlated only to the failing session',()=>{
 const f=fixture(),s=new f.exits.SystemExitStore('/app'),e=new f.exits.ExitEnvironment();
 const failure=new f.exits.WorkerFailure();Object.assign(failure,{at:1000,pid:42,token:'1789400000000',sessionStartedAt:900,
 code:'NO_CODE',name:'Error',message:'original failure',stack:'stack line',operation:'discovery-layout'});
 s.recordWorkerFailure(failure);
 f.files.set('/app/debug-status.json',JSON.stringify({expiresAt:0,supervisorToken:failure.token,startedAt:900,state:'error',message:'UiTest failed',errorCode:'NO_CODE'}));
 f.files.set('/app/worker-health.txt',failure.token+' 42 1 1 1 active ended 1 0');
 const row=s.capture({lastExitReason:2},e,'process-exited',1);
 assert.equal(row.workerFailure.message,'original failure');assert.equal(row.workerFailure.operation,'discovery-layout');
 assert.equal(row.sessionMessage,'UiTest failed');
 f.files.set('/app/debug-status.json',JSON.stringify({expiresAt:0,supervisorToken:failure.token,startedAt:2000,state:'waiting'}));
 assert.equal(s.capture({lastExitReason:2},e).workerFailure,undefined);
 assert.equal(JSON.parse(s.exportText()).workerFailures[0].stack,'stack line');
 for(let i=0;i<25;i++)s.recordWorkerFailure(Object.assign(new f.exits.WorkerFailure(),{at:3000+i,pid:44,message:'x'.repeat(3000),stack:'s'.repeat(7000)}));
 assert.equal(s.workerFailures().length,20);assert.equal(s.workerFailures()[0].message.length,2000);assert.equal(s.workerFailures()[0].stack.length,6000);
 });

test('recovered layout interruption remains diagnostic and is not assigned as exit cause',()=>{
 const f=fixture(),s=new f.exits.SystemExitStore('/app'),e=new f.exits.ExitEnvironment();
 s.recordWorkerFailure(Object.assign(new f.exits.WorkerFailure(),{at:1000,pid:42,token:'1789400000000',sessionStartedAt:900,terminal:false,message:'retried'}));
 f.files.set('/app/debug-status.json',JSON.stringify({supervisorToken:'1789400000000',startedAt:900,state:'waiting'}));
 f.files.set('/app/worker-health.txt','1789400000000 42 1 1 1 active delay 1 0');
 assert.equal(s.capture({lastExitReason:2},e).workerFailure,undefined);
 assert.equal(s.workerFailures()[0].terminal,false);
});

test('late system kill event retains evidence without overwriting launch reason or user stop',()=>{
 const f=fixture(),s=new f.exits.SystemExitStore('/app');
 s.capture({launchReason:1,lastExitReason:2},new f.exits.ExitEnvironment());
 const data={time:999990,reason:'LowMemoryKill',foreground:false,last_exit_detail_info:JSON.stringify({pid:'36823',kill_reason:'LowMemoryKill',timestamp:'999980',private:'discard'}),unrelated:'discard'};
 s.recordFaultEvent('APP_KILLED',data);s.recordFaultEvent('APP_KILLED',data);
 assert.equal(s.faultEvents().length,1);assert.equal(s.faultEvents()[0].pid,36823);
 assert.equal(s.read()[0].reason,2);assert.equal(s.read()[0].stopDecision,'continue');
 assert.equal(s.exportText().includes('private'),false);assert.equal(s.exportText().includes('unrelated'),false);
 s.recordFaultEvent('OTHER',data);s.recordFaultEvent('APP_KILLED',{time:'bad'});assert.equal(s.faultEvents().length,1);
 for(let i=0;i<50;i++)s.recordFaultEvent('APP_KILLED',{time:1000000+i,reason:'LowMemoryKill'});
 assert.equal(s.faultEvents().length,40);assert.equal(s.faultEvents()[0].time,1000049);
});

test('explicit user-stop detail is respected even when top-level system message is empty',()=>{
 const f=fixture();
 for(const detail of [{killReason:'User Request'},{exitMsg:'Kill Reason: User Request'}]) {
  const row=new f.exits.SystemExitRecord();row.reason=2;row.detail=detail;
  assert.equal(f.exits.shouldStopRecovery(row),true);
  row.selfStopVerified=true;assert.equal(f.exits.shouldStopRecovery(row),false);
 }
 const row=new f.exits.SystemExitRecord();row.reason=7;row.detail={exitMsg:'LowMemoryKill',killReason:'unknown'};
 assert.equal(f.exits.shouldStopRecovery(row),false);
});
