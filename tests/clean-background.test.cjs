const test=require('node:test');const assert=require('node:assert/strict');
const {engine}=require('../tools/community/replay.cjs');
function layout({front=false,click=false,type='Image',tabs=true}={}) {
 const n=(type,children=[],extra={})=>({attributes:{type,bounds:'[0,0][1000,2000]',visible:'true',clickable:'false',zIndex:'0',...extra},children});
 const image=n(type,[],{clickable:String(click)});
 const content=n('Column',[n(tabs?'TabBar':'Row'),...Array.from({length:7},(_,i)=>n('Text',[],{text:'页面'+i,bounds:`[20,${100+i*100}][200,${150+i*100}]`}))]);
 return n('root',[n('Stack',front?[content,image]:[n('Column',[image]),content])],{bundleName:'com.example.app',focused:'true',hostWindowId:'1'});
}
for(const [name,opts,expected] of [['native background',{},true],['foreground image',{front:true},false],['clickable background',{click:true},false],['web background',{type:'Web'},false],['no navigation evidence',{tabs:false},false]])test(name,()=>{
 const e=engine(),r=new e.worker.ScanReport();e.worker.discoverSnapshot(JSON.stringify(layout(opts)),'com.example.app',r,e.pack);
 assert.equal(r.cleanPage,expected);if(!expected)assert.match(r.cleanReason,/无法核实/);
});
