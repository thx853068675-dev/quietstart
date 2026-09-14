const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm'), crypto = require('node:crypto');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const source = fs.readFileSync(require('node:path').join(__dirname, '../entry/src/main/ets/core/WorkerInstaller.ets'), 'utf8');
function fixture(options = {}) {
  const files = new Map(), commands = [], progress = [], jobs = [];
  let installed = !!options.installed, encoded = '', completed = options.completed ? 'pending' : '';
  const bytes = new Uint8Array(Buffer.alloc(1200, 71));
  const manifest = { bundleName: 'com.tonghongxiang.quietstart', moduleName: 'entry_test', versionCode: 94600,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'), size: bytes.length };
  if (completed) completed = manifest.sha256;
  if (options.remembered) files.set('/private/installed-worker.sha256', manifest.sha256);
  const resources = { getRawFileContent: async n => n.endsWith('.json') ? new Uint8Array(Buffer.from(JSON.stringify({ ...manifest, ...options.manifest }))) : options.badPayload ? new Uint8Array(1200) : bytes };
  const mocks = {
    '@kit.LocalizationKit': {}, '@kit.ArkTS': { util: { TextDecoder: class { decodeToString(b) { return Buffer.from(b).toString(); } }, Base64Helper: class { encodeToStringSync(b) { return Buffer.from(b).toString('base64'); } } } },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd: () => { let b; return { update: async x => b = x.data, digest: async () => ({ data: new Uint8Array(crypto.createHash('sha256').update(b).digest()) }) }; } } },
    '@kit.CoreFileKit': { fileIo: { OpenMode: {}, readTextSync: p => { if (!files.has(p)) throw Error('missing'); return files.get(p); }, openSync: p => ({ fd: p }), writeSync: (p, v) => files.set(p, v), closeSync() {}, renameSync: (p, q) => { files.set(q, files.get(p)); files.delete(p); } } }, './LocalActivation': {}
  };
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText,
    { exports, require: n => mocks[n], Uint8Array, Number, JSON, Error, Array, Math });
  const shell = {
    execute: async c => {
      commands.push(c);
      if (c.startsWith('bm dump')) return JSON.stringify({ hapModuleInfos: installed ? [{ moduleName: 'entry_test', versionCode: options.wrongVersion ? 94500 : 94600 }] : [] });
      if (c.startsWith('cat ')) return completed;
      if (c.startsWith('tail ')) return options.installLog || 'install timed out';
      if (c.startsWith('printf')) encoded += c.match(/printf '%s' '([^']*)'/)[1];
      if (c.startsWith('sha256sum')) return (options.corrupt ? '0'.repeat(64) : crypto.createHash('sha256').update(Buffer.from(encoded, 'base64')).digest('hex')) + ' worker.hap';
      return '';
    },
    installWorker: async hash => { jobs.push(hash); }
  };
  return { run: (resume = '') => new exports.WorkerInstaller(resources, '/private').ensure(shell, x => progress.push(x), resume),
    commands, files, manifest, progress, jobs, complete() { installed = true; completed = manifest.sha256; } };
}
test('first install stages verified bytes and hands off without prematurely recording success', async () => {
  const f = fixture(); assert.equal(await f.run(), false); assert.deepEqual(f.jobs, [f.manifest.sha256]);
  assert.ok(!f.files.has('/private/installed-worker.sha256'));
  assert.ok(!f.commands.some(c => c.startsWith('bm install') || c.startsWith('rm -f')));
});
test('a restarted app recovers a completed installation and never transfers or installs it again', async () => {
  const f = fixture(); await f.run(); f.complete(); const before = f.commands.length;
  assert.equal(await f.run(f.manifest.sha256), true); assert.equal(f.jobs.length, 1);
  assert.equal(f.files.get('/private/installed-worker.sha256'), f.manifest.sha256);
  assert.ok(!f.commands.slice(before).some(c => c.startsWith('printf')));
});
test('matching installed module and private receipt avoid repeated transfer', async () => {
  const f = fixture({ installed: true, remembered: true }); assert.equal(await f.run(), true); assert.equal(f.commands.length, 1); assert.equal(f.jobs.length, 0);
});
test('a durable receipt also recovers a manually reopened app without another installation', async () => {
  const f = fixture({ installed: true, completed: true }); assert.equal(await f.run(), true); assert.equal(f.jobs.length, 0);
});
test('a receipt cannot hide a missing or wrong-version module', async () => {
  for (const options of [{ remembered: true }, { installed: true, remembered: true, wrongVersion: true }]) {
    const f = fixture(options); assert.equal(await f.run(), false); assert.equal(f.jobs.length, 1);
  }
  const f = fixture({ completed: true }); await assert.rejects(f.run(f.manifest.sha256), /安装未完成/); assert.equal(f.jobs.length, 0);
});
test('failed or timed-out installation returns an error and cannot loop on automatic resume', async () => {
  const f = fixture({ installLog: 'error: signature rejected' }); await f.run();
  await assert.rejects(f.run(f.manifest.sha256), /signature rejected/); assert.equal(f.jobs.length, 1); assert.ok(!f.files.has('/private/installed-worker.sha256'));
});
test('invalid metadata and mismatched resume cannot schedule installation', async () => {
  const f = fixture({ manifest: { sha256: "';id" } }); await assert.rejects(f.run(), /信息无效/); assert.equal(f.commands.length, 0);
  const g = fixture(); await assert.rejects(g.run('0'.repeat(64)), /安装包已更新/); assert.equal(g.jobs.length, 0);
});
test('corrupt embedded bytes or transport never reach installation', async () => {
  const f = fixture({ badPayload: true }); await assert.rejects(f.run(), /校验失败/); assert.equal(f.jobs.length, 0);
  const g = fixture({ corrupt: true }); await assert.rejects(g.run(), /传输不完整/); assert.equal(g.jobs.length, 0); assert.match(g.commands.at(-1), /^rm -f /);
});
