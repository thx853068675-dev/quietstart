const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const vm=require('node:vm');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const exportsObject={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(__dirname+'/../entry/src/main/ets/core/PreviewGeometry.ets','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{exports:exportsObject});
const make=exportsObject.previewGeometry;
test('portrait, square and landscape retain aspect and centred frame without colliding with labels',()=>{
 for(const aspect of [0.45,1320/2120,1,16/9,4.9])for(const x of [0.01,0.95]){
  const g=make(aspect,x,.05,x+.01,.06);
  assert.ok(Math.abs(g.width/g.height-aspect)<1e-10);assert.equal(g.x+(g.width+6)/2,140);
  assert.ok(g.labelX>=0&&g.labelX+g.labelWidth<=280);
  if(g.labelRight)assert.ok(g.labelX>=g.x+g.width+6+9);else assert.ok(g.labelX+g.labelWidth<=g.x-9);
 }
});
test('tiny corner markers remain enlarged and entirely inside screen',()=>{
 for(const aspect of [0.45,1,16/9,4.9])for(const p of [0,.499,.999]){
  const g=make(aspect,p,p,p+.001,p+.001);
  assert.ok(g.markerWidth>=5.28&&g.markerHeight>=3.12);
  assert.ok(g.markerLeft>=0&&g.markerTop>=0);
  assert.ok(g.markerLeft+g.markerWidth<=g.width+1e-9&&g.markerTop+g.markerHeight<=g.height+1e-9);
 }
});
test('missing historical aspect uses the previous preview ratio',()=>{for(const a of [0,NaN,-1,Infinity])assert.equal(make(a,.8,.1,.9,.2).width/104,66/104);});
