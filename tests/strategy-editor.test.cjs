const test=require('node:test');const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');const vm=require('node:vm');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
function load(file,deps={}){const exports={};const code=ts.transpileModule(fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/core',file),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;vm.runInNewContext(code,{exports,require(n){assert.ok(n in deps);return deps[n];}});return exports;}
const model=load('RulePack.ets');const editor=load('StrategyEditor.ets',{'./RulePack':model});
function rule(){const r=new model.RecognitionRule();r.id='preview';r.value='跳过';r.match='contains';r.maxLength=10;return r;}
test('preview uses the real matcher and explains contains versus exact matching',()=>{
 const r=rule();assert.equal(editor.strategyPreview(r,'跳过 3秒'),'能匹配这段文字');r.match='equals';
 assert.match(editor.strategyPreview(r,'跳过 3秒'),/完全相同/);assert.equal(editor.strategyPreview(r,' 跳过 '),'能匹配这段文字');
});
test('preview does not imply permission to click when a safety exclusion applies',()=>{
 const r=rule();assert.match(editor.strategyPreview(r,'跳过登录'),/防误触/);r.exclude=['教程'];
 assert.match(editor.strategyPreview(r,'跳过教程'),/排除的“教程”/);assert.match(editor.strategyPreview(r,'跳过这是一段很长的正文描述'),/字上限/);
});
test('invalid inputs have actionable field-specific feedback',()=>{
 const r=rule();r.value='';assert.match(editor.strategyProblem(r),/至少 2/);r.value='关闭广告';r.maxLength=2;assert.match(editor.strategyProblem(r),/4～32/);
 r.maxLength=10;r.bundles=['wrong'];assert.match(editor.strategyProblem(r),/包名格式/);
});
test('preview preserves hidden field, action and app scope settings',()=>{
 const r=rule();r.field='description';r.action='close';r.bundles=['com.example.real'];const original=JSON.stringify(r);
 assert.equal(editor.strategyPreview(r,'跳过'),'能匹配这段文字');assert.equal(JSON.stringify(r),original);
});
