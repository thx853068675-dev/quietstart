const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),crypto=require('node:crypto');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const source=fs.readFileSync(require('node:path').join(__dirname,'../entry/src/main/ets/core/WorkerInstaller.ets'),'utf8');
function fixture(options={}) {
 const files=new Map(),commands=[],progress=[];let installed=!!options.installed,encoded='';
 const bytes=new Uint8Array(Buffer.alloc(1200,71));
 const manifest={bundleName:'com.tonghongxiang.quietstart',moduleName:'entry_test',versionCode:94200,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),size:bytes.length};
 if(options.remembered)files.set('/private/installed-worker.sha256',manifest.sha256);
 const resources={getRawFileContent:async n=> n.endsWith('.json')?new Uint8Array(Buffer.from(JSON.stringify({...manifest,...options.manifest}))):options.badPayload?new Uint8Array(1200):bytes};
 const mocks={'@kit.LocalizationKit':{},'@kit.ArkTS':{util:{TextDecoder:class{decodeToString(b){return Buffer.from(b).toString()}},Base64Helper:class{encodeToStringSync(b){return Buffer.from(b).toString('base64')}}}},'@kit.CryptoArchitectureKit':{cryptoFramework:{createMd:()=>{let b;return {update:async x=>b=x.data,digest:async()=>({data:new Uint8Array(crypto.createHash('sha256').update(b).digest())})}}}},'@kit.CoreFileKit':{fileIo:{OpenMode:{},readTextSync:p=>{if(!files.has(p))throw Error('missing');return files.get(p)},openSync:p=>({fd:p}),writeSync:(p,v)=>files.set(p,v),closeSync(){},renameSync:(p,q)=>{files.set(q,files.get(p));files.delete(p)}}},'./LocalActivation':{}};
 const exports={};vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}}).outputText,{exports,require:n=>mocks[n],Uint8Array,Number,JSON,Error,Array,Math});
 const shell={execute:async c=>{commands.push(c);
  if(c.startsWith('bm dump'))return 'com.tonghongxiang.quietstart:\n'+JSON.stringify({hapModuleInfos:installed?[{moduleName:'entry_test',versionCode:options.wrongVersion?94100:94200}]:[]});
  if(c.startsWith('printf'))encoded+=c.match(/printf '%s' '([^']*)'/)[1];
  if(c.startsWith('sha256sum'))return (options.corrupt?'0'.repeat(64):crypto.createHash('sha256').update(Buffer.from(encoded,'base64')).digest('hex'))+' worker.hap';
  if(c.startsWith('bm install')){if(options.reject)return 'error: install failed due to signature';installed=!options.noInstall;return 'install bundle successfully.';}
  return '';
 }};
 return {run:()=>new exports.WorkerInstaller(resources,'/private').ensure(shell,x=>progress.push(x)),commands,files,manifest,progress};
}
test('fresh install transfers verified bytes, checks system module, and saves receipt',async()=>{const f=fixture();await f.run();assert.equal(f.commands.filter(x=>x.startsWith('bm install')).length,1);assert.equal(f.files.get('/private/installed-worker.sha256'),f.manifest.sha256);assert.match(f.commands.at(-1),/^rm -f /)});
test('matching installed module and receipt avoid repeated transfer',async()=>{const f=fixture({installed:true,remembered:true});await f.run();assert.equal(f.commands.length,1)});
test('receipt alone cannot hide a missing module',async()=>{const f=fixture({remembered:true});await f.run();assert.ok(f.commands.some(x=>x.startsWith('bm install')))});
test('an old module cannot be accepted through a matching receipt',async()=>{const f=fixture({installed:true,remembered:true,wrongVersion:true});await assert.rejects(f.run(),/未确认工作模块版本/);assert.ok(f.commands.some(x=>x.startsWith('bm install')))});
test('invalid metadata cannot issue shell commands',async()=>{const f=fixture({manifest:{sha256:"';id"}});await assert.rejects(f.run(),/信息无效/);assert.equal(f.commands.length,0)});
test('corrupt embedded bytes cannot be transferred',async()=>{const f=fixture({badPayload:true});await assert.rejects(f.run(),/校验失败/);assert.equal(f.commands.length,1)});
test('corrupt transfer cannot reach package manager and cleans up',async()=>{const f=fixture({corrupt:true});await assert.rejects(f.run(),/传输不完整/);assert.ok(!f.commands.some(x=>x.startsWith('bm install')));assert.match(f.commands.at(-1),/^rm -f /)});
test('rejected package or false success cannot be remembered',async()=>{for(const option of [{reject:true},{noInstall:true}]){const f=fixture(option);await assert.rejects(f.run());assert.ok(!f.files.has('/private/installed-worker.sha256'));assert.match(f.commands.at(-1),/^rm -f /)}});
