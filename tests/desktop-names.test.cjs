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
function captionTree(id,text='十六番旅行',owner='com.ohos.sceneboard',visible='true') {
 return JSON.stringify({attributes:{bundleName:owner,visible:'true'},children:[{attributes:{id,type:'Text',text,visible}}]});
}
test('6.1 sibling caption IDs resolve exact bridge bundle, independent of icon parent',()=>{
 assert.equal(parse(captionTree('AppNameLite_text_com.fan.app_mu355y0n9yjiu6khn6s'),['com.fan.app'])['com.fan.app'],'十六番旅行');
 assert.equal(parse(captionTree('AppName_text_com.netease.cloudmusic_token','网易云音乐'),[bundle])[bundle],'网易云音乐');
});
test('caption identity rejects prefix packages, widgets, hidden and foreign window text',()=>{
 for(const raw of [captionTree('AppNameLite_text_com.fan.app_extra'),''].filter(Boolean)) assert.equal(Object.keys(parse(raw,['com.fan'])).length,0);
 for(const raw of [captionTree('AppNameLite_text_com.fan.app_extra','name','com.fan.app'),captionTree('AppNameLite_text_com.fan.app_extra','name',undefined,'false'),captionTree('AppName_text__天气_token','天气')]) assert.equal(Object.keys(parse(raw,['com.fan.app'])).length,0);
});
