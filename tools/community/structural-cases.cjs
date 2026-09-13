const {read,convert,engine}=require('./replay.cjs');
const IDS=['12620583','12621953','13842826','13939089','12775918','12775919','13468987','13538616'];
function prepared(id,variant){
 const {snapshot,meta}=read(id);const copy=JSON.parse(JSON.stringify(snapshot));
 if(variant!=='original')for(const n of copy.nodes)n.attr.enabled=true;
 const converted=convert(copy);
 if(variant==='enabled-and-z-assumed'){
  const walk=n=>{n.attributes.zIndex='0';n.children.forEach(walk)};walk(converted.tree);
 }
 return {snapshot,meta,tree:converted.tree,missing:converted.missing};
}
function evaluate(runtime,id,variant){
 const c=prepared(id,variant),report=new runtime.worker.ScanReport();
 const target=c.snapshot.nodes.find(n=>n.id===c.meta.expectedTargetNodeId).attr;
 const got=runtime.worker.discoverSnapshot(JSON.stringify(c.tree),c.snapshot.appId,report,runtime.pack);
 const exact=got&&(got.rule.targetId||'')===(target.id||'')&&['left','top','right','bottom'].every(k=>got.bounds[k]===target[k]);
 return {id,variant,kind:c.meta.kind,classification:got?(exact?'correct-target':'wrong-target'):variant==='original'?'insufficient-data':'miss',reason:report.reason,
  assumptions:variant==='original'?['Synthetic focused root only']:variant==='enabled-assumed'?['All enabled=true, not supplied by original']:['All enabled=true and zIndex=0, not supplied by original'],
  source:c.meta.ruleSource,sha256:c.meta.sha256};
}
module.exports={IDS,prepared,evaluate};
if(require.main===module){const r=engine();const results=IDS.flatMap(id=>['original','enabled-assumed','enabled-and-z-assumed'].map(v=>evaluate(r,id,v)));const text=JSON.stringify({scope:'Offline recognition only. Original, enabled assumption, and enabled+layer assumptions reported separately; not device success rate.',results},null,2)+'\n';if(process.argv[2])require('fs').writeFileSync(process.argv[2],text);else process.stdout.write(text);}
