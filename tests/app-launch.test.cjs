const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const exports_={};vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/core/AppLaunch.ets','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{exports:exports_});
const bundle='com.example.app';
const data={name:bundle,entryModuleName:'entry',hapModuleInfos:[{moduleName:'entry',mainElementName:'PhoneAbility',abilityInfos:[{name:'PhoneAbility',visible:true,enabled:true,type:1,skills:[{entities:['entity.system.home'],actions:['action.system.home'],uris:[{scheme:'custom'}]}]}]}]};
test('declared entry bypasses URI-requiring home skills and desktop folder placement',()=>assert.equal(exports_.nativeLaunchCommand(JSON.stringify(data),bundle),'aa start -b com.example.app -m entry -a PhoneAbility'));
test('foreign/private/ambiguous or shell-shaped metadata cannot become a launch',()=>{
 for(const edit of [d=>d.name='com.other.app',d=>d.hapModuleInfos[0].abilityInfos[0].visible=false,d=>d.hapModuleInfos[0].abilityInfos[0].name='X;echo bad']){
  const d=JSON.parse(JSON.stringify(data));edit(d);assert.equal(exports_.nativeLaunchCommand(JSON.stringify(d),bundle),'');
 }
 assert.equal(exports_.nativeLaunchCommand('error: failed to get information',bundle),'');assert.equal(exports_.nativeLaunchCommand(JSON.stringify(data),'com.app;touch bad'),'');
});
