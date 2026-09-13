const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/core/HdcProtocol.ets'), 'utf8');
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(source, {compilerOptions: {target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS}}).outputText,
  {exports: exportsObject, Uint8Array, DataView, Number, Error});
const {HdcDecoder, hdcFrame, joinBytes, readFields, numberField, bytesField, localDebugPort, hdcTlvValue} = exportsObject;
const enc = s => new Uint8Array(Buffer.from(s));

test('decodes an independently specified HDC wire fixture', () => {
  const fixture = Buffer.from('4857000001000900000003086510e90718002009696400', 'hex');
  const result = new HdcDecoder().push(fixture);
  assert.equal(result.length, 1);
  assert.equal(result[0].channel, 101);
  assert.equal(result[0].command, 1001);
  assert.equal(Buffer.from(result[0].data).toString(), 'id\0');
});
test('handles every fragmentation boundary and coalesced packets', () => {
  const packet = hdcFrame(101, 10, enc('worker started'));
  for(let cut=0;cut<=packet.length;cut++) {
    const decoder = new HdcDecoder();
    const results = [...decoder.push(packet.slice(0,cut)), ...decoder.push(packet.slice(cut))];
    assert.equal(results.length,1);
    assert.equal(Buffer.from(results[0].data).toString(),'worker started');
  }
  assert.equal(new HdcDecoder().push(joinBytes([packet, packet])).length,2);
});
test('rejects malformed headers, oversized payloads and invalid protect codes', () => {
  const valid=hdcFrame(1,10,enc('okay'));
  for(const pos of [0,1,4,18]) {
    const invalid=valid.slice();invalid[pos]=99;
    assert.throws(()=>new HdcDecoder().push(invalid));
  }
  const tooLarge=valid.slice();new DataView(tooLarge.buffer).setUint32(7, 1048577, false);
  assert.throws(()=>new HdcDecoder().push(tooLarge));
  assert.throws(()=>new HdcDecoder().push(new Uint8Array(2097153)));
});
test('validates truncated, overlong and overflowing protobuf data', () => {
  for (const bytes of [[8,128],[8,255,255,255,255,16],[10,20,1],[0,1],[9,1]]) {
    assert.throws(()=>readFields(new Uint8Array(bytes)));
  }
  const fields=readFields(joinBytes([numberField(3,4294967295),bytesField(5,enc('test'))]));
  assert.equal(fields[0].number,4294967295);
  assert.equal(Buffer.from(fields[1].data).toString(),'test');
});
test('port input cannot carry shell text or change the loopback destination', () => {
  for(const v of ['39445',' 39445 ','192.168.3.160:39445']) assert.equal(localDebugPort(v),39445);
  for(const v of ['','0','80','65536','39445;id','localhost:39445','39445\nwhoami','1e4','-39445','http://a:39445']) assert.equal(localDebugPort(v),0,v);
});
test('requires exact successful authentication status, not substring matches', () => {
  const tlv=(k,v)=>k.padEnd(16)+String(v.length).padEnd(16)+v;
  assert.equal(hdcTlvValue(tlv('emgmsg','SUCCESS elsewhere')+tlv('daemonauthstatus','DAEMON_UNAUTH'),'daemonauthstatus'),'DAEMON_UNAUTH');
  assert.equal(hdcTlvValue(tlv('daemonauthstatus','SUCCESS'),'daemonauthstatus'),'SUCCESS');
  assert.equal(hdcTlvValue('daemonauthstatus '+'999'.padEnd(16)+'SUCCESS','daemonauthstatus'),'');
});
