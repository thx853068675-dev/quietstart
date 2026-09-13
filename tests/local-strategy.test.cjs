const assert=require('node:assert/strict'),test=require('node:test'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const ts=require(path.join(process.env.DEVECO_APP||'/Applications/DevEco-Studio.app','Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript'));
const root=path.join(__dirname,'..','entry/src/main/ets/core');
function load(name,deps){const exports={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,name+'.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{exports,require:n=>{assert.ok(n in deps,n);return deps[n];}});return exports;}
function fixture(initial={}){
 const files=new Map(Object.entries(initial).map(([n,v])=>['/local/'+n,JSON.stringify(v)]));
 const io={OpenMode:{},readTextSync:p=>{if(!files.has(p))throw Error('missing');return files.get(p);},openSync:p=>({fd:p}),writeSync:(p,t)=>files.set(p,t),closeSync(){},renameSync:(a,b)=>{files.set(b,files.get(a));files.delete(a);},unlinkSync:p=>files.delete(p)};
 const model=load('RulePack',{}),builtin=load('BuiltinRulePack',{'./RulePack':model});
 const Store=load('RulePackStore',{'@kit.CoreFileKit':{fileIo:io},'./RulePack':model,'./BuiltinRulePack':builtin}).RulePackStore;
 return {files,store:new Store('/local'),builtin:builtin.builtinRulePack(),restart:()=>new Store('/local')};
}
test('legacy active conditions migrate once and remote metadata is removed',()=>{
 const base=fixture().builtin;base.rules[0].value='立即跳过';
 const f=fixture({'recognition-pack.json':{current:JSON.stringify(base),previous:''},'recognition-preferences.json':{url:'https://example.invalid'}});
 assert.equal(f.store.read().rules[0].value,'立即跳过');assert.ok(!f.files.has('/local/recognition-pack.json'));
 assert.ok(!f.files.get('/local/recognition-preferences.json').includes('url'));
 assert.equal(f.restart().read().rules[0].value,'立即跳过');
 f.store.resetLocalRules();assert.equal(f.restart().read().rules[0].value,f.builtin.rules[0].value);
});
test('personal empty conditions take precedence over old downloaded conditions',()=>{
 const f=fixture({'recognition-preferences.json':{url:'broken',rules:[]},'recognition-pack.json':{current:JSON.stringify(fixture().builtin)}});
 assert.equal(f.store.read().rules.length,0);assert.equal(f.restart().read().rules.length,0);
});
test('corrupt legacy current falls back to previous and corrupt data to builtin',()=>{
 const base=fixture().builtin;base.rules[0].value='立即跳过';
 assert.equal(fixture({'recognition-pack.json':{current:'broken',previous:JSON.stringify(base)}}).store.read().rules[0].value,'立即跳过');
 assert.equal(fixture({'recognition-pack.json':{current:'broken',previous:'broken'}}).store.read().rules.length,8);
});
test('runtime networking has no HTTP client and local activation stays on loopback',()=>{
 const files=fs.readdirSync(root).filter(n=>n.endsWith('.ets'));
 const source=files.map(n=>fs.readFileSync(path.join(root,n),'utf8')).join('\n');
 assert.doesNotMatch(source,/http\.createHttp|https?:\/\//);
 assert.match(fs.readFileSync(path.join(root,'LocalActivation.ets'),'utf8'),/address: '127\.0\.0\.1'/);
 const ui=fs.readFileSync(path.join(root,'../pages/Index.ets'),'utf8');assert.doesNotMatch(ui,/订阅|检查更新|回退上一版/);
});
