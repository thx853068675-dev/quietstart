const {read} = require('./replay.cjs');
const SAMPLE_IDS=['13160866','13379565','12707641','12899263','13070251','12841423','12883329','12981146','21708258'];
const clone = value => JSON.parse(JSON.stringify(value));
function cases(id) {
  const {snapshot,meta}=read(id);
  const original={name:'original',snapshot,meta,provenance:'community-original',expected:'insufficient-data',reason:'缺少 enabled 状态'};
  const enabled=clone(snapshot);for(const n of enabled.nodes)n.attr.enabled=true;
  if (!['13160866','13379565'].includes(id)) {
    return [original,{name:'enabled-assumed',snapshot:enabled,meta,provenance:'synthetic-state-completion',
      assumptions:['All node enabled states set to true for an ablation experiment; not supplied by source.'],
      expected:id==='21708258'?'miss':'correct-target',reason:id==='21708258'?'与其他控件重叠':'已识别'}];
  }
  const result=[original,{name:'enabled-assumed',snapshot:enabled,meta,provenance:'synthetic-state-completion',
    assumptions:['All node enabled states set to true for an ablation experiment; not supplied by source.'],
    expected:id==='13160866'?'correct-target':'miss',reason:id==='13160866'?'已识别':'与其他控件重叠'}];
  if(id==='13160866') {
    // Keep the actual button subtree and one real visible ad marker, removing
    // unrelated page nodes. Explicitly synthetic: not a full-screen community success.
    const kept=new Set([meta.expectedTargetNodeId]);
    for(let i=0;i<enabled.nodes.length;i++) for(const n of enabled.nodes) if(kept.has(n.pid))kept.add(n.id);
    const isolated=clone(enabled);const marker=enabled.nodes.find(n=>n.attr.text==='广告'&&n.attr.visibleToUser&&n.attr.left<n.attr.right);
    isolated.nodes=isolated.nodes.filter(n=>kept.has(n.id)||n.id===marker.id);
    for(const n of isolated.nodes)if(!kept.has(n.pid))n.pid=-1;
    const make=(name,mutate,expected,reason)=>{const s=clone(isolated);mutate(s);result.push({name,snapshot:s,meta,
      provenance:'synthetic-isolated-community-fragment',assumptions:['Enabled=true; only real target subtree and visible ad marker retained.',name],expected,reason});};
    make('isolated',()=>{},'correct-target','已识别');
    make('moved-left',s=>{for(const n of s.nodes){const a=n.attr;[a.left,a.right]=[s.screenWidth-a.right,s.screenWidth-a.left];}},'correct-target','已识别');
    make('hidden-parent',s=>{s.nodes.find(n=>n.id===meta.expectedTargetNodeId).attr.visibleToUser=false;},'correct-rejection','未匹配');
    make('disabled-parent',s=>{s.nodes.find(n=>n.id===meta.expectedTargetNodeId).attr.enabled=false;},'correct-rejection','容器已禁用');
    make('no-ad-evidence',s=>{s.nodes=s.nodes.filter(n=>n.attr.text!=='广告');},'correct-rejection','缺少广告');
    make('login-description',s=>{s.nodes.find(n=>n.id===meta.expectedTargetNodeId).attr.desc='登录授权';},'correct-rejection','场景排除');
    make('split-label',s=>{
      const label=s.nodes.find(n=>n.attr.text==='关闭');label.attr.text='关';const right=clone(label);right.id=99999;right.attr.text='闭';
      const mid=Math.floor((label.attr.left+label.attr.right)/2);label.attr.right=mid;right.attr.left=mid;
      // The original button also has another child. Remove it explicitly to
      // form a two-part label variant, not a claim about the source screenshot.
      s.nodes=s.nodes.filter(n=>n.id===meta.expectedTargetNodeId||n.id===label.id||n.id===marker.id);s.nodes.push(right);
    },'correct-target','已识别');
  }
  return result;
}
module.exports={cases,SAMPLE_IDS};
