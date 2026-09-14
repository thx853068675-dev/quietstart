const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const ROOT = path.resolve(__dirname, '../..');

// Retain missing values as missing. The root is an explicit offline harness
// assumption, never evidence that an Android window was focused on HarmonyOS.
function convert(snapshot) {
  if (!snapshot || !Array.isArray(snapshot.nodes) || snapshot.nodes.length > 20000 ||
      !Number.isSafeInteger(snapshot.screenWidth) || snapshot.screenWidth <= 0 ||
      !Number.isSafeInteger(snapshot.screenHeight) || snapshot.screenHeight <= 0 ||
      typeof snapshot.appId !== 'string') throw Error('Invalid snapshot');
  const byId = new Map(); const missing = { enabled: 0, visible: 0, clickable: 0 };
  for (const n of snapshot.nodes) {
    if (!Number.isSafeInteger(n.id) || byId.has(n.id) || !n.attr) throw Error('Invalid or duplicate node');
    const a = n.attr;
    const attributes = {};
    for (const [source, target] of [['id','id'],['name','type'],['text','text'],['desc','description']]) {
      if (typeof a[source] === 'string') attributes[target] = a[source];
    }
    for (const [sources, target] of [[['enabled','isEnabled'],'enabled'],[['visibleToUser'],'visible'],[['clickable','isClickable'],'clickable']]) {
      const values = sources.map(k=>a[k]).filter(v=>typeof v === 'boolean');
      if (values.length && values.some(v=>v !== values[0])) throw Error('Conflicting flags');
      if (values.length) attributes[target] = String(values[0]); else missing[target]++;
    }
    if (['left','top','right','bottom'].every(k=>Number.isSafeInteger(a[k])))
      attributes.bounds = `[${a.left},${a.top}][${a.right},${a.bottom}]`;
    byId.set(n.id, { attributes, children: [], sourceNodeId: n.id });
  }
  const children = [];
  for (const n of snapshot.nodes) {
    const node = byId.get(n.id);
    if (n.pid === -1 || n.pid === null || n.pid === undefined) children.push(node);
    else {
      if (!byId.has(n.pid)) throw Error('Missing parent');
      byId.get(n.pid).children.push(node);
    }
  }
  const seen = new Set();
  function visit(n, depth) {
    if (depth > 128 || seen.has(n.sourceNodeId)) throw Error('Cycle or excessive depth');
    seen.add(n.sourceNodeId); n.children.forEach(c=>visit(c,depth+1));
  }
  children.forEach(n=>visit(n,0));
  if (seen.size !== byId.size) throw Error('Unreachable nodes or cycle');
  return { tree: { attributes: { type:'root', bundleName:snapshot.appId, focused:'true', visible:'true',
    hostWindowId:'offline-fixture', bounds:`[0,0][${snapshot.screenWidth},${snapshot.screenHeight}]` }, children },
    missing, assumptions:['Synthetic full-screen focused root for offline replay only; node states are not inferred.'] };
}
function engine() {
  const ts = require(path.join(process.env.DEVECO_APP || '/Applications/DevEco-Studio.app',
    'Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript'));
  function load(file, deps) {
    const filename = path.join(ROOT,file); const exports = {};
    const code = ts.transpileModule(fs.readFileSync(filename,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2021,module:ts.ModuleKind.CommonJS}}).outputText;
    vm.runInNewContext(code,{exports,require(name){if (!(name in deps)) throw Error('Unexpected import '+name); return deps[name];}}, {filename});
    return exports;
  }
  const profile=load('entry/src/main/ets/core/RecognitionProfile.ets',{});
  const store=load('entry/src/main/ets/core/LearningStore.ets',{'./RecognitionProfile':profile,'@kit.CoreFileKit':{fileIo:{}},'@kit.BasicServicesKit':{}});
  const rules=load('entry/src/ohosTest/ets/worker/Rules.ets',{'../../../main/ets/core/LearningStore':store});
  const pack=load('entry/src/main/ets/core/RulePack.ets',{});
  const builtin=load('entry/src/main/ets/core/BuiltinRulePack.ets',{'./RulePack':pack});
  const snapshot=load('entry/src/ohosTest/ets/worker/SnapshotLayout.ets',{'@kit.TestKit':{},'../../../main/ets/core/LearningStore':store});
  const structural=load('entry/src/ohosTest/ets/worker/StructuralExperience.ets',{'@kit.TestKit':{},'../../../main/ets/core/LearningStore':store,'./Rules':rules});
  const capture=load('entry/src/ohosTest/ets/worker/ProfileCapture.ets',{'./StructuralExperience':structural,'../../../main/ets/core/RecognitionProfile':profile,'../../../main/ets/core/LearningStore':store});
  const worker=load('entry/src/ohosTest/ets/worker/LearningWorker.ets',{'@kit.TestKit':{},'./ProfileCapture':capture,'./SnapshotLayout':snapshot,'./StructuralExperience':structural,
    '../../../main/ets/core/LearningStore':store,'./Rules':rules,'../../../main/ets/core/RulePack':pack});
  return {worker,profile,capture,store,pack:builtin.builtinRulePack()};
}
function read(id) {
  const dir=path.join(ROOT,'tests/fixtures/community');
  const raw=fs.readFileSync(path.join(dir,id+'.json'));const meta=JSON.parse(fs.readFileSync(path.join(dir,id+'.meta.json')));
  if (crypto.createHash('sha256').update(raw).digest('hex') !== meta.sha256) throw Error('Fixture checksum mismatch');
  return {snapshot:JSON.parse(raw),meta};
}
function replay(runtime,snapshot,meta,variant='original', expectedRejection=false) {
  const converted=convert(snapshot);const report=new runtime.worker.ScanReport();
  const result=runtime.worker.discoverSnapshot(JSON.stringify(converted.tree),snapshot.appId,report,runtime.pack);
  const expected=snapshot.nodes.find(n=>n.id===meta.expectedTargetNodeId)?.attr;
  const exact=!!result && expected && (result.rule.targetId||'') === (expected.id||'') && ['left','top','right','bottom'].every(k=>result.bounds[k]===expected[k]);
  return {id:meta.id,variant,classification:result?(exact?'correct-target':'wrong-target'):
    (expectedRejection?'correct-rejection':(Object.values(converted.missing).some(n=>n>0)?'insufficient-data':'miss')),
    reason:report.reason,missing:converted.missing,expectedTargetNodeId:meta.expectedTargetNodeId,
    actualBounds:result?.bounds,assumptions:converted.assumptions};
}
module.exports={convert,engine,read,replay};
if(require.main===module){
 const {cases,SAMPLE_IDS}=require('./cases.cjs');
 const runtime=engine(); const results=SAMPLE_IDS.flatMap(id=>cases(id).map(c=>({
   ...replay(runtime,c.snapshot,c.meta,c.name,c.expected==='correct-rejection'),provenance:c.provenance,
   transformations:c.assumptions||[],expected:c.expected,passed:undefined
 }))).map(r=>({...r,passed:r.classification===r.expected}));
 const report={schema:1,scope:'Android community static snapshots; not HarmonyOS success rate or click verification',results};
 const output=JSON.stringify(report,null,2)+'\n'; if(process.argv[2])fs.writeFileSync(process.argv[2],output);else process.stdout.write(output);
 if(results.some(r=>!r.passed))process.exitCode=1;
}
