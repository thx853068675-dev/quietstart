const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');

function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'quietstart-delivery-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}
function exporter(t) {
  const dir = fixture(t);
  for (const sub of ['tools', 'AppScope', 'docs', 'entry']) fs.mkdirSync(path.join(dir, sub));
  fs.copyFileSync(path.join(root, 'tools/export-source.py'), path.join(dir, 'tools/export-source.py'));
  fs.writeFileSync(path.join(dir, 'AppScope/app.json5'), JSON.stringify({ app: { versionName: '1.0' } }));
  return { dir, run: () => spawnSync('python3', [path.join(dir, 'tools/export-source.py')], { encoding: 'utf8' }) };
}
test('source export includes install guide and excludes submission, signing, generated worker and symlinks', t => {
  const { dir, run } = exporter(t);
  for (const f of ['docs/INSTALL.md', 'docs/agc-description-draft.md', 'build-profile.json5', 'entry/worker.hap', 'entry/quietstart-worker.json']) {
    fs.writeFileSync(path.join(dir, f), 'fixture');
  }
  fs.symlinkSync(path.join(dir, 'docs/INSTALL.md'), path.join(dir, 'entry/link.md'));
  fs.mkdirSync(path.join(dir, 'docs/images'));
  fs.writeFileSync(path.join(dir, 'docs/images/overview.jpeg'), 'reviewed screenshot fixture');
  fs.writeFileSync(path.join(dir, 'docs/images/private.jpeg'), 'unreviewed screenshot fixture');
  assert.equal(run().status, 0);
  const archive = path.join(dir, 'dist/quietstart-source-1.0.zip');
  const listed = spawnSync('python3', ['-c', 'import sys,zipfile; print("\\n".join(zipfile.ZipFile(sys.argv[1]).namelist()))', archive], { encoding: 'utf8' });
  assert.equal(listed.status, 0);
  assert.match(listed.stdout, /docs\/INSTALL.md/);
  assert.match(listed.stdout, /docs\/images\/overview.jpeg/);
  assert.doesNotMatch(listed.stdout, /private.jpeg/);
  assert.doesNotMatch(listed.stdout, /agc-description|build-profile.json5|worker.hap|quietstart-worker.json|link.md/);
});
test('source export scans HTML for signing credentials', t => {
  const { dir, run } = exporter(t);
  fs.writeFileSync(path.join(dir, 'entry/unexpected.html'), JSON.stringify({ ['key' + 'Password']: 'fixture' }));
  const result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Review private data/);
});
function installer(t, targets, response, listStatus = 0) {
  const dir = fixture(t);
  fs.copyFileSync(path.join(root, 'tools/install-to-user-device.sh'), path.join(dir, 'install.sh'));
  fs.writeFileSync(path.join(dir, 'entry-default-signed.hap'), 'test-only');
  const hdc = path.join(dir, 'hdc');
  fs.writeFileSync(hdc, '#!/bin/bash\nif [[ "$1" == list ]]; then printf "%s\\n" "$MOCK_TARGETS"; exit "$MOCK_LIST_STATUS"; fi\nprintf "%s\\n" "$@" > "$MOCK_CAPTURE"\nprintf "%s\\n" "$MOCK_RESPONSE"\n');
  fs.chmodSync(hdc, 0o755);
  const capture = path.join(dir, 'args');
  const result = spawnSync('bash', [path.join(dir, 'install.sh')], { encoding: 'utf8', env: { ...process.env, HDC_BIN: hdc, MOCK_TARGETS: targets, MOCK_RESPONSE: response, MOCK_LIST_STATUS: String(listStatus), MOCK_CAPTURE: capture } });
  return { result, args: fs.existsSync(capture) ? fs.readFileSync(capture, 'utf8') : '' };
}
test('installer targets one authorized device and replaces only the main HAP', t => {
  const { result, args } = installer(t, 'test-device', 'install bundle successfully.');
  assert.equal(result.status, 0);
  assert.match(args, /^-t\ntest-device\ninstall\n-r\n/);
  assert.doesNotMatch(args, /ohosTest|uninstall/);
});
test('installer refuses multiple devices without running installation', t => {
  const { result, args } = installer(t, 'test-device-a\ntest-device-b', 'install bundle successfully.');
  assert.notEqual(result.status, 0); assert.equal(args, '');
});
test('installer refuses a failed device query even if it printed a device', t => {
  const { result, args } = installer(t, 'test-device', 'install bundle successfully.', 1);
  assert.notEqual(result.status, 0); assert.equal(args, '');
});
test('installer rejects misleading success text accompanied by failure', t => {
  const { result } = installer(t, 'test-device', 'install bundle successfully.\n[Fail] signature rejected');
  assert.notEqual(result.status, 0);
});
