const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const root=path.join(__dirname,'../entry/src/main/ets/core');
function load(name,mocks={}) {
 const exports={};
 vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,name+'.ets'),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}}).outputText,
 {exports,require:n=>{if(!(n in mocks))throw Error(n);return mocks[n]},Uint8Array,DataView,Number,Date,Error,Promise,setInterval:()=>1,clearInterval:()=>{},setTimeout:()=>1,clearTimeout:()=>{}});
 return exports;
}
const protocol=load('HdcProtocol');
const bytes=s=>new Uint8Array(Buffer.from(s));
const tlv=(k,v)=>k.padEnd(16)+String(v.length).padEnd(16)+v;
function fixture(prepare) {
 const files=new Map(),handlers={},sends=[];let connected,closed=false,keygen=0;
 let status={running:false,startedAt:0};
 const settings={enabled:true,packages:['com.example.saved'],stopRequested:true,learningEnabled:true};
 const key={getEncoded:()=>({data:bytes('key material')})};
 const keypair={priKey:key,pubKey:key};
 class DebugStore { readStatus(){return status} }
 class LocalStore {readSettings(){return {...settings}}saveSettings(v){Object.assign(settings,v)}}
 class Encoder {encodeInto(s){return bytes(s)}}
 class Decoder {decodeToString(b){return Buffer.from(b).toString()}}
 class Base64 {encodeToStringSync(b){return Buffer.from(b).toString('base64')}decodeSync(s){return new Uint8Array(Buffer.from(s,'base64'))}}
 const api={constructTCPSocketInstance:()=>({on:(n,fn)=>handlers[n]=fn,connect:async o=>{connected=o},send:async o=>sends.push(...new protocol.HdcDecoder().push(new Uint8Array(o.data))),close:async()=>{closed=true}})};
 const crypto={createAsyKeyGenerator:()=>({convertKey:async()=>keypair,generateKeyPair:async()=>{keygen++;return keypair}}),createRandom:()=>({generateRandomSync:()=>({data:new Uint8Array([1,2,3,4])})}),createSign:alg=>{
  assert.equal(alg,'RSA3072|PSS|SHA512|MGF1_SHA512');return {init:async()=>{},setSignSpec:(k,v)=>assert.equal(v,64),sign:async()=>({data:bytes('signature')})}
 },SignSpecItem:{PSS_SALT_LEN_NUM:103}};
 const io={OpenMode:{},accessSync:p=>files.has(p),readTextSync:p=>{if(!files.has(p))throw Error('missing');return files.get(p)},openSync:p=>({fd:p}),writeSync:(p,t)=>files.set(p,t),closeSync:()=>{},renameSync:(p,q)=>{files.set(q,files.get(p));files.delete(p)}};
 const {LocalActivation}=load('LocalActivation',{'@kit.NetworkKit':{socket:api},'@kit.CryptoArchitectureKit':{cryptoFramework:crypto},'@kit.ArkTS':{util:{TextEncoder:Encoder,TextDecoder:Decoder,Base64Helper:Base64}},'@kit.CoreFileKit':{fileIo:io},'@kit.BasicServicesKit':{},'@kit.PerformanceAnalysisKit':{hilog:{info(){}}},'./DebugStore':{DebugStore,isDebugOnline:s=>s.running},'./LocalStore':{LocalStore},'./HdcProtocol':protocol});
 const {OnboardingStore}=load('OnboardingStore',{'@kit.CoreFileKit':{fileIo:io}});
 const instance=new LocalActivation('/private',prepare);
 async function receive(type,body) {
  const data=protocol.joinBytes([protocol.bytesField(1,bytes('OHOS HDC')),protocol.numberField(2,type),protocol.bytesField(5,bytes(body))]);
  handlers.message({message:protocol.hdcFrame(0,1,data).buffer});await instance.serial;
 }
 async function receiveClose(channel=0,count=1) {
  handlers.message({message:protocol.hdcFrame(channel,2,new Uint8Array([count])).buffer});await instance.serial;
 }
 async function receiveAuthorizedAndClose() {
  const data=protocol.joinBytes([protocol.bytesField(1,bytes('OHOS HDC')),protocol.numberField(2,4),protocol.bytesField(5,bytes(tlv('daemonauthstatus','SUCCESS')))]);
  handlers.message({message:protocol.joinBytes([protocol.hdcFrame(0,1,data),protocol.hdcFrame(0,2,new Uint8Array([1]))]).buffer});await instance.serial;
 }
 return {instance,files,sends,receive,receiveClose,receiveAuthorizedAndClose,settings,setStatus:s=>{status=s},connected:()=>connected,closed:()=>closed,keygen:()=>keygen,LocalActivation,OnboardingStore};
}

test('local activation connects only to loopback, authenticates, and sends only the fixed detached restart',async()=>{
 const f=fixture();await f.instance.activate('192.168.3.160:39445');
 assert.equal(f.connected().address.address,'127.0.0.1');assert.equal(f.connected().address.port,39445);
 await f.receive(3,tlv('authtype','1'));await f.receive(2,'challenge');
 await f.receive(4,tlv('daemonauthstatus','DAEMON_UNAUTH')+tlv('emgmsg','[E000002]: wait'));
 assert.equal(f.sends.filter(p=>p.command===1001).length,0);
 await f.receive(4,tlv('daemonauthstatus','SUCCESS'));await f.receive(4,tlv('daemonauthstatus','SUCCESS'));
 assert.equal(f.sends.filter(p=>p.command===1001).length,0);
 await f.receiveClose();
 const commands=f.sends.filter(p=>p.command===1001);assert.equal(commands.length,1);
 const command=Buffer.from(commands[0].data).toString();
 assert.match(command,/^\/bin\/nohup \/bin\/setsid \/bin\/sh -c 'echo QuietStartChildReady; sleep 2; aa force-stop com\.tonghongxiang\.quietstart; echo QuietStartOldProcessStopped; aa test /);
 assert.match(command,/-s seconds 0 -w 3/);assert.ok(command.endsWith('echo QuietStartLocalScheduled; wait'));assert.ok(!command.includes('\0'));assert.ok(!command.includes('192.168'));
 assert.equal(f.settings.stopRequested,false);assert.deepEqual(f.settings.packages,['com.example.saved']);
 assert.equal(f.instance.readState().success,false);
});
test('successful authentication waits for channel zero cleanup before starting a shell task',async()=>{
 const f=fixture();await f.instance.activate('39445');
 await f.receive(4,tlv('daemonauthstatus','SUCCESS'));
 assert.equal(f.sends.filter(p=>p.command===1001).length,0,'AUTH_OK alone must not start the task');
 assert.equal(f.instance.readState().commandAt,0);
 await f.receiveClose();
 const exchange=f.sends.filter(p=>p.command===2||p.command===1001);
 assert.deepEqual(exchange.map(p=>[p.channel,p.command]),[[0,2],[101,1001]],'ACK0 must precede shell101: ACK0 makes hdcd clear every existing task');
 assert.equal(exchange[0].data[0],0);
 assert.ok(f.instance.readState().commandAt>0);
});
test('coalesced AUTH_OK and channel zero close are processed in the safe wire order',async()=>{
 const f=fixture();await f.instance.activate('39445');await f.receiveAuthorizedAndClose();
 const exchange=f.sends.filter(p=>p.command===2||p.command===1001);
 assert.deepEqual(exchange.map(p=>[p.channel,p.command]),[[0,2],[101,1001]]);
});
test('duplicate authentication close cannot clear or restart the running activation task',async()=>{
 const f=fixture();await f.instance.activate('39445');await f.receiveAuthorizedAndClose();
 const before=f.sends.length;
 await f.receiveClose();await f.receiveClose(0,0);await f.receive(4,tlv('daemonauthstatus','SUCCESS'));await f.receiveClose();
 assert.equal(f.sends.length,before,'late ACK0 would kill the new shell task');
 assert.equal(f.sends.filter(p=>p.command===1001).length,1);
 await f.receiveClose(101,1);
 assert.equal(f.sends.at(-1).channel,101,'normal command channel close still receives its own ACK');
 assert.equal(f.sends.at(-1).command,2);
});
test('an unauthorized channel zero close never launches a shell or substitutes for successful authentication cleanup',async()=>{
 const f=fixture();await f.instance.activate('39445');
 await f.receive(4,tlv('daemonauthstatus','DAEMON_UNAUTH')+tlv('emgmsg','[E000002]: wait'));await f.receiveClose();
 assert.equal(f.sends.filter(p=>p.command===1001).length,0);
 assert.equal(f.settings.stopRequested,true);
 await f.receive(4,tlv('daemonauthstatus','SUCCESS'));
 assert.equal(f.sends.filter(p=>p.command===1001).length,0,'an earlier unauthorized close does not finish the successful handshake');
 const afterSuccess=f.sends.length;await f.receiveClose();
 assert.deepEqual(f.sends.slice(afterSuccess).map(p=>[p.channel,p.command]),[[0,2],[101,1001]]);
});
test('fresh heartbeat completes activation after the original application process exits',async()=>{
 const f=fixture();await f.instance.activate('39445');const started=f.instance.readState().startedAt;
 f.setStatus({running:true,startedAt:started+2000});const reopened=new f.LocalActivation('/private');
 assert.equal(reopened.readState().success,true);assert.ok(reopened.readState().finishedAt>0);
});
test('stale heartbeat cannot complete a new activation',async()=>{
 const f=fixture();await f.instance.activate('39445');const started=f.instance.readState().startedAt;
 f.setStatus({running:true,startedAt:started-5000});assert.equal(f.instance.readState().success,false);
});
test('rejecting authorization closes the socket and never sends a shell command',async()=>{
 const f=fixture();await f.instance.activate('39445');await f.receive(4,tlv('daemonauthstatus','DAEMON_UNAUTH')+tlv('emgmsg','[E000003]: denied'));
 assert.equal(f.closed(),true);assert.equal(f.sends.filter(p=>p.command===1001).length,0);
 assert.ok(f.instance.readState().message.includes('系统未授权'));assert.equal(f.instance.readState().success,false);
});
test('invalid input and an already online worker cannot create a new debug connection',async()=>{
 const f=fixture();await assert.rejects(f.instance.activate('39445; id'));assert.equal(f.connected(),undefined);
 f.setStatus({running:true,startedAt:Date.now()});await f.instance.activate('39445');assert.equal(f.connected(),undefined);
});
test('identity is reused after a new app instance, and timeouts never become success',async()=>{
 const f=fixture();await f.instance.activate('39445');f.instance.close();
 const reopened=new f.LocalActivation('/private');await reopened.activate('39445');assert.equal(f.keygen(),1);
 const state=reopened.readState();state.startedAt=Date.now()-100000;
 f.files.set('/private/local-activation.json',JSON.stringify(state));
 assert.equal(reopened.readState().success,false);assert.ok(reopened.readState().finishedAt>0);
});

test('read-only display-name query reuses local identity, leaves activation/settings intact and handles split UTF-8', async()=>{
 const f=fixture();
 const activation=JSON.stringify({port:'36167',startedAt:1,finishedAt:2,success:true});
 f.files.set('/private/local-activation.json',activation);
 f.files.set('/private/local-hdc-identity.json',JSON.stringify({publicKey:'a2V5',privateKey:'a2V5'}));
 f.setStatus({running:true,startedAt:1});
 const pending=f.instance.readAppLabel('com.ygkj.chelaile.standard.har');
 for(let i=0;i<12;i++)await Promise.resolve();
 await f.receiveAuthorizedAndClose();
 const commands=f.sends.filter(p=>p.command===1001).map(p=>Buffer.from(p.data).toString());
 assert.deepEqual(commands,['bm dump -n com.ygkj.chelaile.standard.har -l; echo __QuietStartLabelEnd__']);
 const data=bytes('车来了\n__QuietStartLabelEnd__\n');
 await f.instance.receive({channel:101,command:10,data:data.slice(0,2)});
 await f.instance.receive({channel:101,command:10,data:data.slice(2)});
 assert.equal(await pending,'车来了');
 assert.equal(f.files.get('/private/local-activation.json'),activation);
 assert.equal(f.settings.stopRequested,true);assert.equal(f.keygen(),0);assert.equal(f.closed(),true);
});
test('name lookup rejects shell injection and cannot create an unrequested debugging identity',async()=>{
 const f=fixture();
 assert.equal(await f.instance.readAppLabel('com.example.test;reboot'),'');
 assert.equal(await f.instance.readAppLabel('com.example.valid'),'');
 assert.equal(f.sends.length,0);assert.equal(f.keygen(),0);
});
test('error text returned with a successful shell exit cannot become an application label',async()=>{
 const f=fixture();f.files.set('/private/local-activation.json',JSON.stringify({port:'36167'}));
 f.files.set('/private/local-hdc-identity.json',JSON.stringify({publicKey:'a2V5',privateKey:'a2V5'}));
 const pending=f.instance.readAppLabel('com.example.app');for(let i=0;i<12;i++)await Promise.resolve();
 await f.receiveAuthorizedAndClose();
 await f.instance.receive({channel:101,command:10,data:bytes('error: failed to get information\n__QuietStartLabelEnd__\n')});
 assert.equal(await pending,'');
});


test('first-launch wizard saves progress across activation restart and stays completed afterwards',()=>{
 const f=fixture();const first=new f.OnboardingStore('/private');
 assert.equal(first.read().completed,false);assert.equal(first.read().step,0);
 first.save(2);const restarted=new f.OnboardingStore('/private');
 assert.equal(restarted.read().step,2);assert.equal(restarted.read().completed,false);
 restarted.save(3,true);assert.equal(new f.OnboardingStore('/private').read().completed,true);
});
test('deferring onboarding is distinct from completion and malformed progress restarts safely',()=>{
 const f=fixture();const store=new f.OnboardingStore('/private');store.save(1,false,true);
 assert.equal(store.read().deferred,true);assert.equal(store.read().completed,false);
 f.files.set('/private/onboarding.json','{"step":99,"completed":"true"}');
 assert.equal(store.read().step,0);assert.equal(store.read().completed,false);
});


test('installation uses the same authenticated socket without blocking the receive queue', async()=>{
 let prepared=false;
 const f=fixture(async(shell,progress)=>{progress('installing');assert.equal(await shell.execute('bm dump -n com.tonghongxiang.quietstart'),'module ready');prepared=true;});
 await f.instance.activate('41907');await f.receiveAuthorizedAndClose();
 assert.equal(f.sends.filter(p=>p.channel===101&&p.command===1001).length,0);
 assert.equal(f.instance.readState().phase,'installing');
 await f.receiveClose();
 assert.equal(f.sends.filter(p=>p.channel===0&&p.command===2).length,1);
 await f.instance.receive({channel:201,command:10,data:bytes('module ready\n__QuietStartExec_0__')});
 for(let i=0;i<8;i++)await Promise.resolve();
 assert.equal(prepared,true);
 const command=f.sends.find(p=>p.channel===101&&p.command===1001);
 assert.ok(command);assert.ok(!Buffer.from(command.data).toString().includes('2>&1'));
 assert.equal(f.instance.readState().success,false,'command dispatch is not a live heartbeat');
});
test('failed installation never starts the worker or marks activation successful',async()=>{
 const f=fixture(async(shell)=>{await shell.execute('bm install -p fixed-worker.hap');});
 await f.instance.activate('41907');await f.receiveAuthorizedAndClose();
 await f.instance.receive({channel:201,command:10,data:bytes('permission denied\n__QuietStartExec_1__')});
 for(let i=0;i<8;i++)await Promise.resolve();
 assert.ok(!f.sends.some(p=>p.channel===101&&p.command===1001));
 assert.equal(f.closed(),true);assert.equal(f.instance.readState().success,false);
 assert.match(f.instance.readState().message,/permission denied/);
});
