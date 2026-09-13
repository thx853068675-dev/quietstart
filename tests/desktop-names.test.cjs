const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const exportsModule={};vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/core/DesktopAppNames.ets','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText,{exports:exportsModule});
const parse=exportsModule.desktopAppNames,bundle='com.netease.cloudmusic';
function tree(owner='com.ohos.sceneboard',visible='true',extra=false){return JSON.stringify({attributes:{bundleName:owner,visible:'true'},children:[{attributes:{id:'Container_AppIcon_Image_'+bundle+'com.netease.cloudmusic.activity.IconChangeDefaultAliasentry0_undefined_0',visible},children:[{attributes:{type:'Text',text:'网易云音乐',visible:'true'}},...(extra?[{attributes:{type:'Text',text:'其他标题',visible:'true'}}]:[])]}]});}
test('maps Android launcher icon identity to its caption',()=>assert.equal(parse(tree(),[bundle])[bundle],'网易云音乐'));
test('ignores non-launcher, invisible, ambiguous and unknown icons',()=>{
 for(const raw of [tree('com.example.app'),tree(undefined,'false'),tree(undefined,undefined,true)])assert.equal(Object.keys(parse(raw,[bundle])).length,0);
 assert.equal(Object.keys(parse(tree(),['com.netease'])).length,0);
 assert.equal(Object.keys(parse('{broken',[bundle])).length,0);
});
